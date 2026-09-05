import Foundation
import IndieCore

public struct InstalledRenderers: Sendable, Equatable {
    public var available: Set<RendererKind>
    public var overlayPaths: [RendererKind: URL]

    public init(available: Set<RendererKind> = [.wineD3D], overlayPaths: [RendererKind: URL] = [:]) {
        self.available = available
        self.overlayPaths = overlayPaths
    }
}

public struct RendererResolution: Sendable, Equatable {
    public let renderer: RendererKind
    public let warnings: [String]
}

public enum RendererResolver {
    public static func resolve(
        analysis: GameAnalysis,
        preferred: RendererKind?,
        recipe: GameRecipe?,
        installed: InstalledRenderers
    ) throws -> RendererResolution {
        if analysis.antiCheat == .kernel {
            throw IndieError.unsupported(L("检测到内核级反作弊；Mac Gaming Uncle 不尝试绕过"))
        }

        let candidates: [RendererKind]
        if let preferred {
            candidates = [preferred]
        } else if let recipe, !recipe.profiles.isEmpty {
            candidates = recipe.profiles.map(\.renderer)
        } else {
            switch analysis.directX {
            case .d3d12: candidates = [.d3dMetal, .vkd3d]
            case .d3d10, .d3d11: candidates = [.dxmt, .d3dMetal, .dxvk, .wineD3D]
            case .d3d9: candidates = [.wineD3D, .dxvk]
            case .d3d8, .none: candidates = [.wineD3D]
            }
        }

        for renderer in candidates where installed.available.contains(renderer) {
            if renderer == .d3dMetal && analysis.architecture == .i386 { continue }
            var warnings = analysis.warnings
            if renderer == .vkd3d { warnings.append(L("VKD3D/MoltenVK 是实验性 DX12 路径")) }
            return RendererResolution(renderer: renderer, warnings: warnings)
        }
        if analysis.directX == .d3d12, !installed.available.contains(.d3dMetal) {
            throw IndieError.notFound(L("此 DX12 游戏需要 D3DMetal；请从 Apple 官方 GPTK 导入"))
        }
        throw IndieError.notFound(L("没有适合此游戏的已安装图形后端"))
    }
}

public enum LaunchPlanBuilder {
    public static func build(
        executable: URL,
        windowsExecutablePath: String? = nil,
        bottle: BottleRecord,
        profile: LaunchProfile,
        analysis: GameAnalysis,
        recipe: GameRecipe?,
        installed: InstalledRenderers
    ) throws -> LaunchPlan {
        let resolution = try RendererResolver.resolve(analysis: analysis, preferred: profile.preferredRenderer, recipe: recipe, installed: installed)
        let recipeProfile = recipe?.profiles.first { $0.renderer == resolution.renderer }
        var environment = recipeProfile?.environment ?? [:]
        environment.merge(profile.environment) { _, user in user }
        environment["WINEPREFIX"] = bottle.root.path
        environment["INDIE_RENDERER"] = resolution.renderer.rawValue
        if profile.metalHUD {
            environment["MTL_HUD_ENABLED"] = "1"
        }
        let syncBackend = profile.syncBackend == .automatic
            ? (recipeProfile?.syncBackend ?? .automatic)
            : profile.syncBackend
        if syncBackend == .msync {
            environment["WINEMSYNC"] = "1"
        } else {
            environment.removeValue(forKey: "WINEMSYNC")
        }
        if let overlay = installed.overlayPaths[resolution.renderer] {
            // D3DMetalLaunchEnvironment supplies two deliberately different
            // paths: the Wine PE bridge and the native `external` libraries.
            // Preserve those values instead of collapsing both to the overlay
            // root at the final LaunchPlan assembly step.
            if environment["WINEDLLPATH"] == nil {
                environment["WINEDLLPATH"] = overlay.path
            }
            if resolution.renderer == .dxmt {
                environment["WINEDLLPATH_PREPEND"] = overlay.path
            }
            if resolution.renderer == .d3dMetal,
               environment["DYLD_FALLBACK_LIBRARY_PATH"] == nil {
                environment["DYLD_FALLBACK_LIBRARY_PATH"] = overlay.path
            }
        }
        if resolution.renderer == .d3dMetal {
            environment["WINEDLLOVERRIDES"] = "dxgi,d3d10,d3d10core,d3d11,d3d12=n,b"
            if environment["D3DM_ENABLE_METALFX"] == "1" {
                environment["WINEDLLOVERRIDES"]! += ";nvapi,nvapi64,nvngx=n,b"
            }
        } else if resolution.renderer == .dxmt {
            environment["WINEDLLOVERRIDES"] = "dxgi,d3d11,d3d10core=b"
        } else if resolution.renderer == .dxvk {
            environment["WINEDLLOVERRIDES"] = BottleDXVKInstaller.dllOverrides
        }
        if let overrides = recipeProfile?.dllOverrides, !overrides.isEmpty {
            environment["WINEDLLOVERRIDES"] = overrides.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ";")
        }
        return LaunchPlan(
            executable: executable,
            windowsExecutablePath: windowsExecutablePath,
            bottle: bottle,
            runtimeID: profile.runtimeID,
            renderer: resolution.renderer,
            // Explicit launcher/project arguments may be positional (notably
            // UE's generated project name), so keep them before compatibility
            // switches contributed by a recipe.
            arguments: profile.arguments + (recipeProfile?.arguments ?? []),
            environment: environment,
            warnings: resolution.warnings + (recipe?.knownIssues ?? []),
            virtualDesktop: profile.virtualDesktop
        )
    }
}
