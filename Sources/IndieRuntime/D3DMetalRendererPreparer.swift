import Foundation
import IndieCore

public enum D3DMetalRendererPreparer {
    public static func enableMetalFX(
        rendererRoot: URL,
        version: String,
        bottle: BottleRecord,
        fileManager: FileManager = .default
    ) throws {
        let unix = rendererRoot.appendingPathComponent("wine/x86_64-unix", isDirectory: true)
        let windows = rendererRoot.appendingPathComponent("wine/x86_64-windows", isDirectory: true)
        let aliases = [
            (unix.appendingPathComponent("nvngx-on-metalfx.so"), unix.appendingPathComponent("nvngx.so")),
            (windows.appendingPathComponent("nvngx-on-metalfx.dll"), windows.appendingPathComponent("nvngx.dll")),
        ]
        for (source, target) in aliases {
            guard fileManager.fileExists(atPath: source.path) else {
                throw IndieError.invalidData("GPTK \(version) 缺少 MetalFX NVNGX Bridge")
            }
            if !fileManager.fileExists(atPath: target.path) {
                try fileManager.copyItem(at: source, to: target)
            }
        }

        let system32 = bottle.root.appendingPathComponent("drive_c/windows/system32", isDirectory: true)
        let backup = bottle.root.appendingPathComponent(".indie-backups/d3dmetal/\(version)/system32", isDirectory: true)
        try fileManager.createDirectory(at: system32, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: backup, withIntermediateDirectories: true)
        for name in ["nvngx.dll", "nvapi64.dll"] {
            let source = windows.appendingPathComponent(name)
            guard fileManager.fileExists(atPath: source.path) else {
                throw IndieError.invalidData("GPTK \(version) 缺少 \(name)")
            }
            let destination = system32.appendingPathComponent(name)
            let original = backup.appendingPathComponent(name)
            if fileManager.fileExists(atPath: destination.path), !fileManager.fileExists(atPath: original.path) {
                try fileManager.copyItem(at: destination, to: original)
            }
            if fileManager.fileExists(atPath: destination.path),
               try ManifestSecurity.sha256(of: destination) == ManifestSecurity.sha256(of: source) { continue }
            let temporary = system32.appendingPathComponent(".indie-\(UUID().uuidString)-\(name)")
            try fileManager.copyItem(at: source, to: temporary)
            if fileManager.fileExists(atPath: destination.path) {
                _ = try fileManager.replaceItemAt(destination, withItemAt: temporary)
            } else {
                try fileManager.moveItem(at: temporary, to: destination)
            }
        }
    }
}
