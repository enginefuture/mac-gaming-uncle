import CryptoKit
import Foundation
import XCTest
@testable import IndieCore
@testable import IndieRuntime

final class IndieRuntimeTests: XCTestCase {
    func testManifestSignature() throws {
        let key = Curve25519.Signing.PrivateKey()
        let unsigned = makeManifest(signature: nil)
        let signature = try key.signature(for: ManifestSecurity.canonicalPayload(for: unsigned)).base64EncodedString()
        let signed = makeManifest(signature: signature)
        XCTAssertNoThrow(try ManifestSecurity.verify(signed, publicKeyBase64: key.publicKey.rawRepresentation.base64EncodedString()))
    }

    func testRendererResolution() throws {
        let analysis = GameAnalysis(
            identity: GameIdentity(executableName: "demo.exe"), architecture: .x86_64,
            directX: .d3d11, antiCheat: .none, importedLibraries: ["d3d11.dll"]
        )
        let result = try RendererResolver.resolve(
            analysis: analysis, preferred: nil, recipe: nil,
            installed: InstalledRenderers(available: [.wineD3D, .dxmt])
        )
        XCTAssertEqual(result.renderer, .dxmt)
    }

    func testLaunchPlanKeepsPositionalArgumentsBeforeRecipeSwitches() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("indie-argument-order-\(UUID().uuidString)")
        let bottle = BottleRecord(name: "Arguments", root: root, runtimeID: "wine")
        let executable = root.appendingPathComponent("Game-Win64-Shipping.exe")
        let analysis = GameAnalysis(
            identity: GameIdentity(steamAppID: 1, executableName: executable.lastPathComponent),
            architecture: .x86_64, directX: .d3d12, antiCheat: .none,
            importedLibraries: ["d3d12.dll"]
        )
        let recipe = GameRecipe(
            id: "test.arguments", name: "Arguments", steamAppIDs: [1],
            profiles: [RendererProfile(renderer: .d3dMetal, arguments: ["-norhithread"])]
        )
        let plan = try LaunchPlanBuilder.build(
            executable: executable, bottle: bottle,
            profile: LaunchProfile(runtimeID: "wine", preferredRenderer: .d3dMetal, arguments: ["Game"], metalHUD: true),
            analysis: analysis, recipe: recipe,
            installed: InstalledRenderers(available: [.d3dMetal])
        )
        XCTAssertEqual(plan.arguments, ["Game", "-norhithread"])
        XCTAssertEqual(plan.environment["MTL_HUD_ENABLED"], "1")
        XCTAssertNil(plan.environment["MTL_HUD_LOG_ENABLED"])
    }

    func testSubprocessEnvironmentDoesNotLeakUnrelatedSecrets() {
        let environment = Subprocess.sanitizedEnvironment(
            inherited: ["HOME": "/Users/test", "PATH": "/usr/bin", "API_SECRET": "do-not-inherit"],
            overrides: ["WINEPREFIX": "/tmp/bottle", "LANG": "zh_CN.UTF-8"]
        )
        XCTAssertEqual(environment["HOME"], "/Users/test")
        XCTAssertEqual(environment["WINEPREFIX"], "/tmp/bottle")
        XCTAssertEqual(environment["LANG"], "zh_CN.UTF-8")
        XCTAssertNil(environment["API_SECRET"])
    }

    func testKernelAntiCheatIsBlocked() {
        let analysis = GameAnalysis(
            identity: GameIdentity(executableName: "blocked.exe"), architecture: .x86_64,
            directX: .d3d12, antiCheat: .kernel, importedLibraries: ["vgk.sys"]
        )
        XCTAssertThrowsError(try RendererResolver.resolve(analysis: analysis, preferred: nil, recipe: nil, installed: .init(available: [.d3dMetal])))
    }

    func testSteamInstallerUsesValveOfficialCDN() {
        XCTAssertEqual(SteamInstaller.officialURL.scheme, "https")
        XCTAssertEqual(SteamInstaller.officialURL.host, "cdn.fastly.steamstatic.com")
        XCTAssertEqual(SteamInstaller.officialURL.lastPathComponent, "SteamSetup.exe")
    }

    func testWineVulkanGraphicsConfigurationIsStable() {
        XCTAssertEqual(
            WineRuntimeProvider.vulkanRegistryArguments,
            ["reg", "add", #"HKCU\Software\Wine\Direct3D"#, "/v", "renderer", "/t", "REG_SZ", "/d", "vulkan", "/f"]
        )
        XCTAssertEqual(WineRuntimeProvider.vulkanEnvironment["MVK_CONFIG_RESUME_LOST_DEVICE"], "1")
        XCTAssertEqual(
            WineRuntimeProvider.wineD3DRegistryArguments,
            ["reg", "add", #"HKCU\Software\Wine\Direct3D"#, "/v", "renderer", "/t", "REG_SZ", "/d", "gl", "/f"]
        )
    }

    func testPinnedDXVKReleaseMetadata() {
        XCTAssertEqual(CommunityDXVKBootstrapper.release.version, "1.10.3")
        XCTAssertEqual(CommunityDXVKBootstrapper.release.downloadSize, 2_793_443)
        XCTAssertEqual(CommunityDXVKBootstrapper.release.sha256.count, 64)
    }

    func testPinnedDXMTReleaseMetadata() {
        XCTAssertEqual(CommunityDXMTBootstrapper.release.version, "0.80")
        XCTAssertEqual(CommunityDXMTBootstrapper.release.downloadSize, 18_681_669)
        XCTAssertEqual(CommunityDXMTBootstrapper.release.sha256.count, 64)
    }

    func testDXMTLaunchPlanPrependsBuiltinBridge() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("indie-dxmt-plan-\(UUID().uuidString)")
        let bottle = BottleRecord(name: "DXMT", root: root.appendingPathComponent("bottle"), runtimeID: "wine")
        let overlay = root.appendingPathComponent("dxmt")
        let analysis = GameAnalysis(
            identity: GameIdentity(executableName: "game.exe"), architecture: .x86_64,
            directX: .d3d11, antiCheat: .none, importedLibraries: ["d3d11.dll"]
        )
        let plan = try LaunchPlanBuilder.build(
            executable: root.appendingPathComponent("game.exe"), bottle: bottle,
            profile: LaunchProfile(runtimeID: "wine", preferredRenderer: .dxmt),
            analysis: analysis, recipe: nil,
            installed: InstalledRenderers(available: [.dxmt], overlayPaths: [.dxmt: overlay])
        )
        XCTAssertEqual(plan.environment["WINEDLLPATH_PREPEND"], overlay.path)
        XCTAssertEqual(plan.environment["WINEDLLOVERRIDES"], "dxgi,d3d11,d3d10core=b")
    }

    func testIndieWine11RuntimeManifestIsPinned() {
        let manifest = CommunityIndieWineBootstrapper.manifest
        XCTAssertEqual(manifest.id, "org.indie.wine11")
        XCTAssertEqual(manifest.version, SemanticVersion(major: 11, minor: 0, patch: 1))
        XCTAssertEqual(manifest.artifacts.count, 1)
        XCTAssertTrue(manifest.artifacts.allSatisfy { $0.sha256.count == 64 && $0.size > 0 })
        XCTAssertTrue(manifest.capabilities.renderers.contains(.d3dMetal))
        XCTAssertTrue(manifest.capabilities.supportsWoW64)
        XCTAssertTrue(manifest.capabilities.supportsMSync)
    }

    func testIndieWine11LocalBuildInstallation() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("indie-wine11-local-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = IndiePaths(root: root.appendingPathComponent("data"))
        let payload = root.appendingPathComponent("build/wine-runtime")
        for relativePath in [
            "bin/wine", "bin/wineserver", "lib/wine/x86_64-unix/ntdll.so",
            "lib/wine/i386-windows/ntdll.dll", "lib/libgnutls.30.dylib",
        ] {
            let file = payload.appendingPathComponent(relativePath)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data().write(to: file)
        }
        for executable in ["bin/wine", "bin/wineserver"] {
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: payload.appendingPathComponent(executable).path)
        }

        let installed = try await CommunityIndieWineBootstrapper(paths: paths).installLocalBuild(
            from: payload.deletingLastPathComponent()
        )
        XCTAssertEqual(installed.manifest.id, CommunityIndieWineBootstrapper.runtimeID)
        XCTAssertTrue(CommunityIndieWineBootstrapper.isCompleteRuntime(installed.root))
        XCTAssertTrue(FileManager.default.fileExists(atPath: installed.root.appendingPathComponent("local-runtime.json").path))
    }

    func testD3DMetalEnvironmentUsesWine11HostHooks() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("indie-d3dmetal-env-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let renderer = root.appendingPathComponent("renderer")
        let runtime = root.appendingPathComponent("runtime")
        for relativePath in [
            "external/libd3dshared.dylib",
            "wine/x86_64-windows/dxgi.dll",
            "wine/x86_64-windows/d3d11.dll",
            "wine/x86_64-windows/d3d12.dll",
        ] {
            let file = renderer.appendingPathComponent(relativePath)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data().write(to: file)
        }
        try FileManager.default.createDirectory(at: runtime.appendingPathComponent("lib"), withIntermediateDirectories: true)

        let environment = try D3DMetalLaunchEnvironment.make(
            rendererRoot: renderer,
            runtimeRoot: runtime,
            metalHUD: true,
            metalFX: true,
            metal4: true
        )

        XCTAssertEqual(environment["CX_ACTIVE_GRAPHICS_BACKEND"], "d3dmetal")
        XCTAssertEqual(environment["CX_APPLEGPTK_LIBD3DSHARED_PATH"], renderer.appendingPathComponent("external/libd3dshared.dylib").path)
        XCTAssertEqual(environment["WINEDLLPATH_PREPEND"], renderer.appendingPathComponent("wine").path)
        XCTAssertNil(environment["WINEDLLPATH"])
        XCTAssertEqual(environment["MTL_HUD_ENABLED"], "1")
        XCTAssertEqual(environment["D3DM_SHOW_HUD_STATS"], "1")
        XCTAssertEqual(environment["D3DM_ENABLE_METALFX"], "1")
        XCTAssertEqual(environment["D3DM_MTL4"], "1")
        XCTAssertTrue(environment["DYLD_FALLBACK_LIBRARY_PATH"]?.contains(runtime.appendingPathComponent("lib").path) == true)
    }

    func testD3DMetalLaunchPlanPreservesNativeAndPEBridgePaths() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("indie-d3dm-plan-\(UUID().uuidString)")
        let renderer = root.appendingPathComponent("renderer")
        let bridge = renderer.appendingPathComponent("wine")
        let external = renderer.appendingPathComponent("external")
        let runtimeLibraries = root.appendingPathComponent("runtime/lib")
        let bottle = BottleRecord(name: "D3DMetal", root: root.appendingPathComponent("bottle"), runtimeID: "org.indie.wine11")
        let analysis = GameAnalysis(
            identity: GameIdentity(executableName: "game.exe"), architecture: .x86_64,
            directX: .d3d12, antiCheat: .none, importedLibraries: ["d3d12.dll"]
        )
        let fallback = "\(external.path):\(runtimeLibraries.path)"
        let plan = try LaunchPlanBuilder.build(
            executable: root.appendingPathComponent("game.exe"), bottle: bottle,
            profile: LaunchProfile(
                runtimeID: "org.indie.wine11", preferredRenderer: .d3dMetal,
                environment: ["WINEDLLPATH_PREPEND": bridge.path, "DYLD_FALLBACK_LIBRARY_PATH": fallback]
            ),
            analysis: analysis, recipe: nil,
            installed: InstalledRenderers(available: [.d3dMetal], overlayPaths: [.d3dMetal: bridge])
        )
        XCTAssertEqual(plan.environment["WINEDLLPATH_PREPEND"], bridge.path)
        XCTAssertEqual(plan.environment["WINEDLLPATH"], bridge.path)
        XCTAssertEqual(plan.environment["DYLD_FALLBACK_LIBRARY_PATH"], fallback)
    }

    func testLocalWineImporterFindsNestedBundleLayout() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("indie-sikarugir-layout-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let wine = root.appendingPathComponent("wswine.bundle/bin/wine")
        try FileManager.default.createDirectory(at: wine.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: wine)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: wine.path)
        XCTAssertEqual(LocalWineImporter.findWine(in: root)?.standardizedFileURL, wine.standardizedFileURL)
    }

    func testGPTKDownloadWatcherFindsCompletedImageAndReportsPartialDownload() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("indie-gptk-download-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let old = root.appendingPathComponent("Game_Porting_Toolkit_3.0.dmg")
        let complete = root.appendingPathComponent("Evaluation_environment_for_Windows_games_4.0_beta_2.dmg")
        let partial = root.appendingPathComponent("Evaluation_environment_for_Windows_games_4.0.dmg.crdownload")
        try Data("old".utf8).write(to: old)
        try Data("complete".utf8).write(to: complete)
        try Data(repeating: 1, count: 128).write(to: partial)

        let snapshot = GPTKDownloadWatcher.scan(root)
        XCTAssertEqual(snapshot.completedImage?.standardizedFileURL, complete.standardizedFileURL)
        XCTAssertEqual(snapshot.partialDownload?.standardizedFileURL, partial.standardizedFileURL)
        XCTAssertEqual(snapshot.partialSize, 128)
        XCTAssertFalse(GPTKDownloadWatcher.isGPTK4Name(old.lastPathComponent))
        XCTAssertFalse(GPTKDownloadWatcher.isGPTK4Name("Game_Porting_Toolkit_4.0_beta_2.dmg"))
    }

    func testAppleGPTKRuntimeDiscoveryRequiresCompleteRuntime() throws {
        let applications = FileManager.default.temporaryDirectory.appendingPathComponent("indie-gptk-discovery-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: applications) }
        let app = applications.appendingPathComponent("Game Porting Toolkit.app")
        let wine = app.appendingPathComponent("Contents/Resources/wine/bin/wine64")
        let external = app.appendingPathComponent("Contents/Resources/wine/lib/external")
        let wineLibraries = app.appendingPathComponent("Contents/Resources/wine/lib/wine")
        let framework = external.appendingPathComponent("D3DMetal.framework")
        try FileManager.default.createDirectory(at: wine.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: wineLibraries, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: framework.appendingPathComponent("Resources"), withIntermediateDirectories: true)
        try Data().write(to: wine)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: wine.path)
        try Data().write(to: external.appendingPathComponent("libd3dshared.dylib"))
        let plist = try PropertyListSerialization.data(
            fromPropertyList: ["CFBundleShortVersionString": "4.0b1"], format: .xml, options: 0
        )
        try plist.write(to: framework.appendingPathComponent("Resources/Info.plist"))

        let runtime = AppleGPTKRuntime.discover(applicationsDirectory: applications)
        XCTAssertEqual(runtime?.version, "4.0b1")
        XCTAssertEqual(runtime?.majorVersion, 4)
        XCTAssertEqual(runtime?.manifest.capabilities.renderers, [.d3dMetal])

        let imported = ImportedD3DMetal(
            version: "4.0b1", root: app, framework: framework,
            sharedLibrary: external.appendingPathComponent("libd3dshared.dylib"),
            rendererRoot: nil,
            runtimeRoot: app.appendingPathComponent("Contents/Resources/wine", isDirectory: true),
            sourceSHA256: nil, importedAt: Date()
        )
        XCTAssertEqual(AppleGPTKRuntime.discover(importedComponents: [imported])?.majorVersion, 4)
    }

    func testDXVKLaunchPlanOnlyOverridesMacOSPackageDLLs() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("indie-dxvk-plan-\(UUID().uuidString)")
        let bottle = BottleRecord(name: "DXVK", root: root, runtimeID: "wine")
        let executable = root.appendingPathComponent("game.exe")
        let analysis = GameAnalysis(
            identity: GameIdentity(executableName: "game.exe"), architecture: .x86_64,
            directX: .d3d11, antiCheat: .none, importedLibraries: ["d3d11.dll"]
        )
        let plan = try LaunchPlanBuilder.build(
            executable: executable, bottle: bottle,
            profile: LaunchProfile(runtimeID: "wine", preferredRenderer: .dxvk),
            analysis: analysis, recipe: nil,
            installed: InstalledRenderers(available: [.dxvk])
        )
        XCTAssertEqual(plan.environment["WINEDLLOVERRIDES"], "d3d11,d3d10core=n,b")
    }

    func testBottleDXVKInstallationBacksUpAndIsIdempotent() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("indie-dxvk-install-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let overlayRoot = root.appendingPathComponent("overlay")
        let bottle = BottleRecord(name: "DXVK", root: root.appendingPathComponent("bottle"), runtimeID: "wine")
        for folder in ["x64", "x32"] {
            let directory = overlayRoot.appendingPathComponent(folder)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data("new-\(folder)-d3d11".utf8).write(to: directory.appendingPathComponent("d3d11.dll"))
            try Data("new-\(folder)-d3d10".utf8).write(to: directory.appendingPathComponent("d3d10core.dll"))
        }
        for folder in ["system32", "syswow64"] {
            let directory = bottle.root.appendingPathComponent("drive_c/windows/\(folder)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data("original-\(folder)-d3d11".utf8).write(to: directory.appendingPathComponent("d3d11.dll"))
            try Data("original-\(folder)-d3d10".utf8).write(to: directory.appendingPathComponent("d3d10core.dll"))
        }
        let overlay = RendererOverlay(kind: .dxvk, version: "1.10.3", root: overlayRoot, importedAt: Date())

        let first = try BottleDXVKInstaller.install(overlay: overlay, in: bottle)
        XCTAssertEqual(
            try Data(contentsOf: bottle.root.appendingPathComponent("drive_c/windows/system32/d3d11.dll")),
            Data("new-x64-d3d11".utf8)
        )
        XCTAssertEqual(
            try Data(contentsOf: first.backupDirectory.appendingPathComponent("system32/d3d11.dll")),
            Data("original-system32-d3d11".utf8)
        )
        let second = try BottleDXVKInstaller.install(overlay: overlay, in: bottle)
        XCTAssertEqual(second.version, first.version)
        XCTAssertEqual(second.installedFiles, first.installedFiles)
        XCTAssertEqual(second.installedAt.timeIntervalSince1970, first.installedAt.timeIntervalSince1970, accuracy: 1.0)
    }

    func testSteamInstallerStagesOnBottleCDrive() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("indie-steam-stage-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = IndiePaths(root: root.appendingPathComponent("data"))
        let bottle = BottleRecord(
            name: "Steam",
            root: paths.bottles.appendingPathComponent("Steam-Test"),
            runtimeID: "wine"
        )
        let source = root.appendingPathComponent("SteamSetup.exe")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("valid-fixture".utf8).write(to: source)

        let staged = try await SteamInstaller(paths: paths).stageForLaunch(source, in: bottle)
        XCTAssertTrue(FileManager.default.fileExists(atPath: staged.fileURL.path))
        XCTAssertTrue(staged.windowsPath.hasPrefix("C:\\users\\Public\\Downloads\\Indie\\SteamSetup-"))
        XCTAssertEqual(try Data(contentsOf: staged.fileURL), Data("valid-fixture".utf8))
    }

    func testBottleFontsInstallAndRegisterCJKFallback() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("indie-font-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let bottle = BottleRecord(name: "Fonts", root: root, runtimeID: "wine")
        let registration = try BottleFonts.prepare(in: bottle)
        XCTAssertFalse(registration.installedFonts.isEmpty)
        XCTAssertTrue(registration.installedFonts.allSatisfy { $0.path.contains("drive_c/windows/Fonts") })
        XCTAssertTrue(registration.installedFonts.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
        XCTAssertEqual(registration.registryWindowsPath, "C:\\windows\\temp\\indie-cjk-fonts.reg")
        let data = try Data(contentsOf: registration.registryFile)
        XCTAssertEqual(Array(data.prefix(2)), [0xff, 0xfe])
        let text = String(data: data.dropFirst(2), encoding: .utf16LittleEndian)
        XCTAssertTrue(text?.contains(#"HKEY_CURRENT_USER\Software\Microsoft\Windows NT\CurrentVersion\Fonts"#) == true)
        XCTAssertTrue(text?.contains(#"FontLink\SystemLink"#) == true)
        XCTAssertTrue(text?.contains("hex(7):") == true)
        if FileManager.default.fileExists(atPath: "/System/Library/Fonts/Hiragino Sans GB.ttc") {
            XCTAssertTrue(text?.contains("Hiragino Sans GB") == true)
            XCTAssertTrue(registration.installedFonts.contains { $0.lastPathComponent == "hiraginosansgb.ttc" })
        }
    }

    func testD3DMetalShaderCacheInvalidatesWhenRendererProfileChanges() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("indie-d3dm-cache-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let d3dm = root.appendingPathComponent("Game.exe")
        let cache = d3dm.appendingPathComponent("shaders.cache")
        let backups = root.appendingPathComponent("backups")
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        try Data("old-cache".utf8).write(to: cache.appendingPathComponent("pipeline.bin"))
        let firstProfile = D3DMetalShaderProfile(
            rendererVersion: "4.0b2", rendererSHA256: "first", metalFX: false,
            dxr: false, metal4: false, operatingSystem: "test"
        )

        let first = try D3DMetalShaderCacheManager.prepare(
            executableName: "Game.exe", profile: firstProfile,
            backupRoot: backups, d3dmRoot: d3dm, now: Date(timeIntervalSince1970: 1)
        )
        XCTAssertTrue(first.profileChanged)
        XCTAssertNotNil(first.backup)
        XCTAssertFalse(FileManager.default.fileExists(atPath: cache.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.backup!.appendingPathComponent("pipeline.bin").path))

        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        let same = try D3DMetalShaderCacheManager.prepare(
            executableName: "Game.exe", profile: firstProfile,
            backupRoot: backups, d3dmRoot: d3dm
        )
        XCTAssertFalse(same.profileChanged)
        XCTAssertNil(same.backup)

        let changedProfile = D3DMetalShaderProfile(
            rendererVersion: "4.0b2", rendererSHA256: "first", metalFX: true,
            dxr: false, metal4: false, operatingSystem: "test"
        )
        let changed = try D3DMetalShaderCacheManager.prepare(
            executableName: "Game.exe", profile: changedProfile,
            backupRoot: backups, d3dmRoot: d3dm
        )
        XCTAssertTrue(changed.profileChanged)
        XCTAssertNotNil(changed.backup)
    }

    func testSteamCompatibilityWrapperIsRepairedAndArgumentsAreStable() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("indie-steam-wrapper-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let bottle = BottleRecord(name: "Steam", root: root.appendingPathComponent("Bottle"), runtimeID: "wine")
        let cef = SteamCompatibilityManager.steamRoot(in: bottle).appendingPathComponent("bin/cef/cef.win64", isDirectory: true)
        try FileManager.default.createDirectory(at: cef, withIntermediateDirectories: true)
        let upstream = cef.appendingPathComponent("steamwebhelper.exe")
        let wrapper = root.appendingPathComponent("wrapper.exe")
        try Data("upstream".utf8).write(to: upstream)
        let wrapperData = Data("INDIE_STEAM_WEBHELPER_WRAPPER_V1-wrapper".utf8)
        try wrapperData.write(to: wrapper)

        let first = try SteamCompatibilityManager.prepare(bottle: bottle, wrapper: wrapper)
        XCTAssertTrue(first.wrapperInstalled)
        XCTAssertEqual(try Data(contentsOf: upstream), wrapperData)
        XCTAssertEqual(try Data(contentsOf: first.upstreamWebHelper), Data("upstream".utf8))
        XCTAssertNotNil(first.backupDirectory)

        let second = try SteamCompatibilityManager.prepare(bottle: bottle, wrapper: wrapper)
        XCTAssertFalse(second.wrapperInstalled)
        XCTAssertEqual(SteamCompatibilityManager.launchArguments(appID: 42), ["-noverifyfiles", "-no-cef-sandbox", "-applaunch", "42"])
        XCTAssertEqual(
            SteamCompatibilityManager.launchArguments(appID: 42, gameArguments: ["-nothreadtimeout"]),
            ["-noverifyfiles", "-no-cef-sandbox", "-applaunch", "42", "-nothreadtimeout"]
        )
        XCTAssertEqual(
            SteamCompatibilityManager.launchArguments(appID: 42, launchOption: 1),
            ["-noverifyfiles", "-no-cef-sandbox", "steam://launch/42/dialog"]
        )
        let relayed = SteamCompatibilityManager.relayEnvironment(for: [
            "MTL_HUD_ENABLED": "1",
            "WINEDLLOVERRIDES": "d3d11,dxgi=n,b",
        ])
        XCTAssertEqual(relayed["MTL_HUD_ENABLED"], "1")
        XCTAssertEqual(relayed["WINE_WAIT_CHILD_PIPE_IGNORE"], "steam.exe")
        XCTAssertEqual(relayed["WINEDLLOVERRIDES"], "d3d11,dxgi=n,b;mscoree,mshtml=;winedbg.exe=d")
    }

    func testSteamDefaultLaunchOptionIsUpdatedWithBackup() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("indie-steam-option-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let bottle = BottleRecord(name: "Steam", root: root, runtimeID: "wine")
        let config = SteamCompatibilityManager.steamRoot(in: bottle)
            .appendingPathComponent("userdata/123/config/localconfig.vdf")
        try FileManager.default.createDirectory(at: config.deletingLastPathComponent(), withIntermediateDirectories: true)
        let original = #"""
        "apps"
        {
            "219990"
            {
                "DefaultLaunchOption"
                {
                    "opaque-machine-key" "0"
                }
            }
        }
        """#
        try original.write(to: config, atomically: true, encoding: .utf8)

        XCTAssertTrue(try SteamCompatibilityManager.setDefaultLaunchOption(appID: 219990, option: 1, in: bottle))
        XCTAssertTrue(try String(contentsOf: config, encoding: .utf8).contains(#""opaque-machine-key" "1""#))
        let backup = root.appendingPathComponent(".indie-backups/steam-launch-options/123-localconfig.vdf")
        XCTAssertEqual(try String(contentsOf: backup, encoding: .utf8), original)
    }

    func testSteamLoggedOnDetectionUsesLatestConnectionState() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("indie-steam-login-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let bottle = BottleRecord(name: "Steam", root: root, runtimeID: "wine")
        let log = SteamCompatibilityManager.steamRoot(in: bottle).appendingPathComponent("logs/connection_log.txt")
        try FileManager.default.createDirectory(at: log.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("[Logged On, 4, 7]\n[Logged Off, 0, 0]\n".utf8).write(to: log)
        XCTAssertFalse(SteamCompatibilityManager.isLoggedOn(in: bottle))
        try Data("[Logged Off, 0, 0]\n[Logged On, 4, 7]\n".utf8).write(to: log)
        XCTAssertTrue(SteamCompatibilityManager.isLoggedOn(in: bottle))
    }

    func testD3DMetalPreparerCreatesMetalFXAliasesAndBottleFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("indie-metalfx-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let renderer = root.appendingPathComponent("renderer")
        let unix = renderer.appendingPathComponent("wine/x86_64-unix")
        let windows = renderer.appendingPathComponent("wine/x86_64-windows")
        try FileManager.default.createDirectory(at: unix, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: windows, withIntermediateDirectories: true)
        try Data("unix-nvngx".utf8).write(to: unix.appendingPathComponent("nvngx-on-metalfx.so"))
        try Data("windows-nvngx".utf8).write(to: windows.appendingPathComponent("nvngx-on-metalfx.dll"))
        try Data("nvapi".utf8).write(to: windows.appendingPathComponent("nvapi64.dll"))
        let bottle = BottleRecord(name: "MetalFX", root: root.appendingPathComponent("bottle"), runtimeID: "wine")

        try D3DMetalRendererPreparer.enableMetalFX(rendererRoot: renderer, version: "4.0b2", bottle: bottle)
        XCTAssertTrue(FileManager.default.fileExists(atPath: unix.appendingPathComponent("nvngx.so").path))
        XCTAssertEqual(
            try Data(contentsOf: bottle.root.appendingPathComponent("drive_c/windows/system32/nvngx.dll")),
            Data("windows-nvngx".utf8)
        )
    }

    func testD3DMetalPreparerInstallsNativeBridgeAndKeepsOriginalBackup() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("indie-d3dmetal-bridge-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let renderer = root.appendingPathComponent("renderer")
        let windows = renderer.appendingPathComponent("wine/x86_64-windows")
        try FileManager.default.createDirectory(at: windows, withIntermediateDirectories: true)
        for name in ["dxgi.dll", "d3d10.dll", "d3d11.dll", "d3d12.dll"] {
            try Data("gptk-\(name)".utf8).write(to: windows.appendingPathComponent(name))
        }
        let bottle = BottleRecord(name: "D3DMetal", root: root.appendingPathComponent("bottle"), runtimeID: "wine")
        let system32 = bottle.root.appendingPathComponent("drive_c/windows/system32")
        try FileManager.default.createDirectory(at: system32, withIntermediateDirectories: true)
        try Data("original".utf8).write(to: system32.appendingPathComponent("d3d11.dll"))

        try D3DMetalRendererPreparer.installBridge(rendererRoot: renderer, version: "4.0b2", bottle: bottle)
        XCTAssertEqual(try Data(contentsOf: system32.appendingPathComponent("d3d11.dll")), Data("gptk-d3d11.dll".utf8))
        XCTAssertEqual(
            try Data(contentsOf: bottle.root.appendingPathComponent(".indie-backups/d3dmetal/4.0b2/system32/d3d11.dll")),
            Data("original".utf8)
        )

        try D3DMetalRendererPreparer.installBridge(rendererRoot: renderer, version: "4.0b2", bottle: bottle)
        XCTAssertEqual(
            try Data(contentsOf: bottle.root.appendingPathComponent(".indie-backups/d3dmetal/4.0b2/system32/d3d11.dll")),
            Data("original".utf8)
        )
    }

    func testSteamCompatibilityDoesNotTurnOldWrapperIntoRealBinary() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("indie-wrapper-upgrade-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let bottle = BottleRecord(name: "Steam", root: root.appendingPathComponent("Bottle"), runtimeID: "wine")
        let cef = SteamCompatibilityManager.steamRoot(in: bottle).appendingPathComponent("bin/cef/cef.win64", isDirectory: true)
        try FileManager.default.createDirectory(at: cef, withIntermediateDirectories: true)
        let current = cef.appendingPathComponent("steamwebhelper.exe")
        let real = cef.appendingPathComponent("steamwebhelper_real.exe")
        let newWrapper = root.appendingPathComponent("new-wrapper.exe")
        var legacyWrapper = Data("legacy".utf8)
        legacyWrapper.append("steamwebhelper_real.exe".data(using: .utf16LittleEndian)!)
        legacyWrapper.append("--single-process".data(using: .utf16LittleEndian)!)
        try legacyWrapper.write(to: current)
        try Data("real-upstream".utf8).write(to: real)
        try Data("INDIE_STEAM_WEBHELPER_WRAPPER_V1-new".utf8).write(to: newWrapper)

        _ = try SteamCompatibilityManager.prepare(bottle: bottle, wrapper: newWrapper)
        XCTAssertEqual(try Data(contentsOf: real), Data("real-upstream".utf8))
        XCTAssertEqual(try Data(contentsOf: current), Data("INDIE_STEAM_WEBHELPER_WRAPPER_V1-new".utf8))
    }

    private func makeManifest(signature: String?) -> RuntimeManifest {
        RuntimeManifest(
            id: "org.indie.wine", displayName: "Wine 11",
            version: SemanticVersion(major: 11, minor: 0), channel: .stable,
            hostArchitecture: .x86_64, minimumMacOS: SemanticVersion(major: 15, minor: 0),
            capabilities: RuntimeCapabilities(architectures: [.i386, .x86_64], renderers: [.wineD3D], supportsWoW64: true, supportsMSync: true),
            artifacts: [],
            licenses: [], publishedAt: Date(timeIntervalSince1970: 1_780_000_000), signature: signature
        )
    }
}
