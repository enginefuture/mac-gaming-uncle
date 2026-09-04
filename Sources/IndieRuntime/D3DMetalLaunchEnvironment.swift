import Foundation
import IndieCore

public enum D3DMetalLaunchEnvironment {
    public static func make(
        rendererRoot: URL,
        runtimeRoot: URL,
        metalHUD: Bool,
        metalFX: Bool,
        dxr: Bool = false,
        metal4: Bool = false,
        fileManager: FileManager = .default
    ) throws -> [String: String] {
        let wineBridge = rendererRoot.appendingPathComponent("wine", isDirectory: true)
        let external = rendererRoot.appendingPathComponent("external", isDirectory: true)
        let shared = external.appendingPathComponent("libd3dshared.dylib")
        let required = [
            shared,
            wineBridge.appendingPathComponent("x86_64-windows/dxgi.dll"),
            wineBridge.appendingPathComponent("x86_64-windows/d3d11.dll"),
            wineBridge.appendingPathComponent("x86_64-windows/d3d12.dll"),
        ]
        guard required.allSatisfy({ fileManager.fileExists(atPath: $0.path) }) else {
            throw IndieError.invalidData("导入的 D3DMetal Wine Bridge 不完整")
        }

        var fallbackRoots = [external.path]
        let runtimeLibraries = runtimeRoot.appendingPathComponent("lib", isDirectory: true)
        if fileManager.fileExists(atPath: runtimeLibraries.path) {
            fallbackRoots.append(runtimeLibraries.path)
        }
        var environment = [
            "LANG": "zh_CN.UTF-8",
            "LC_ALL": "zh_CN.UTF-8",
            "WINEDEBUG": "-all",
            "GRAPHICS_BACKEND": "d3dmetal",
            "CX_GRAPHICS_BACKEND": "d3dmetal",
            "CX_ACTIVE_GRAPHICS_BACKEND": "d3dmetal",
            "D3DMETAL_RUNTIME_DIR": rendererRoot.path,
            "CX_APPLEGPTK_LIBD3DSHARED_PATH": shared.path,
            "WINEDLLPATH_PREPEND": wineBridge.path,
            "DYLD_FALLBACK_LIBRARY_PATH": fallbackRoots.joined(separator: ":"),
            "D3DM_SUPPORT_DXR": dxr ? "1" : "0",
            "ROSETTA_ADVERTISE_AVX": "1",
        ]
        if metalHUD {
            environment["MTL_HUD_ENABLED"] = "1"
            environment["D3DM_SHOW_HUD_STATS"] = "1"
        } else {
            environment["D3DM_UNBUFFERED_OUTPUT"] = "0"
        }
        if metalFX {
            environment["D3DM_ENABLE_METALFX"] = "1"
            environment["D3DMETAL_UPSCALER_PROFILE"] = "nvidia"
            environment["D3DM_VENDOR_ID"] = "4318"
            environment["D3DM_DEVICE_ID"] = "10370"
            environment["D3DM_DEVICE_DESCRIPTION"] = "NVIDIA GeForce RTX 4080"
        }
        if metal4 {
            environment["D3DM_MTL4"] = "1"
        }
        return environment
    }
}
