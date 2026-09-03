import Foundation
import IndieCore

public struct BottleDXVKInstallation: Codable, Sendable, Equatable {
    public let version: String
    public let overlayRoot: URL
    public let backupDirectory: URL
    public let installedFiles: [String: String]
    public let installedAt: Date
}

public enum BottleDXVKInstaller {
    public static let dllOverrides = "d3d11,d3d10core=n,b"

    public static func install(
        overlay: RendererOverlay,
        in bottle: BottleRecord,
        fileManager: FileManager = .default
    ) throws -> BottleDXVKInstallation {
        guard overlay.kind == .dxvk else {
            throw IndieError.invalidArgument("Bottle DXVK 安装器只接受 DXVK Overlay")
        }
        guard let layout = sourceLayout(under: overlay.root, fileManager: fileManager) else {
            throw IndieError.invalidData("DXVK Overlay 缺少 x64/x32 D3D11 DLL")
        }

        let metadataDirectory = bottle.root.appendingPathComponent(".indie", isDirectory: true)
        let metadataURL = metadataDirectory.appendingPathComponent("dxvk.json")
        let backupDirectory = bottle.root.appendingPathComponent(".indie-backups/dxvk/original", isDirectory: true)
        let destinations: [(folder: String, source: URL)] = [
            ("system32", layout.x64),
            ("syswow64", layout.x32),
        ]

        if let existing = try? decode(metadataURL),
           existing.version == overlay.version,
           try installationMatches(existing, bottle: bottle) {
            return existing
        }

        try fileManager.createDirectory(at: metadataDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
        var hashes: [String: String] = [:]
        for destination in destinations {
            let windowsDirectory = bottle.root.appendingPathComponent("drive_c/windows/\(destination.folder)", isDirectory: true)
            let backupSubdirectory = backupDirectory.appendingPathComponent(destination.folder, isDirectory: true)
            try fileManager.createDirectory(at: windowsDirectory, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: backupSubdirectory, withIntermediateDirectories: true)
            for name in ["d3d11.dll", "d3d10core.dll"] {
                let source = destination.source.appendingPathComponent(name)
                let target = windowsDirectory.appendingPathComponent(name)
                let backup = backupSubdirectory.appendingPathComponent(name)
                if fileManager.fileExists(atPath: target.path), !fileManager.fileExists(atPath: backup.path) {
                    try fileManager.copyItem(at: target, to: backup)
                }
                try replace(target, with: source, fileManager: fileManager)
                hashes["\(destination.folder)/\(name)"] = try ManifestSecurity.sha256(of: source)
            }
        }

        let installation = BottleDXVKInstallation(
            version: overlay.version,
            overlayRoot: overlay.root,
            backupDirectory: backupDirectory,
            installedFiles: hashes,
            installedAt: Date()
        )
        try IndieJSON.encoder(pretty: true).encode(installation).write(to: metadataURL, options: .atomic)
        return installation
    }

    private static func sourceLayout(under root: URL, fileManager: FileManager) -> (x64: URL, x32: URL)? {
        for pair in [("x64", "x32"), ("x86_64-windows", "i386-windows")] {
            let x64 = root.appendingPathComponent(pair.0, isDirectory: true)
            let x32 = root.appendingPathComponent(pair.1, isDirectory: true)
            let required = [x64, x32].flatMap { directory in
                [directory.appendingPathComponent("d3d11.dll"), directory.appendingPathComponent("d3d10core.dll")]
            }
            if required.allSatisfy({ fileManager.fileExists(atPath: $0.path) }) { return (x64, x32) }
        }
        return nil
    }

    private static func replace(_ target: URL, with source: URL, fileManager: FileManager) throws {
        let temporary = target.deletingLastPathComponent().appendingPathComponent(".indie-\(UUID().uuidString)-\(target.lastPathComponent)")
        try fileManager.copyItem(at: source, to: temporary)
        do {
            if fileManager.fileExists(atPath: target.path) {
                _ = try fileManager.replaceItemAt(target, withItemAt: temporary)
            } else {
                try fileManager.moveItem(at: temporary, to: target)
            }
        } catch {
            try? fileManager.removeItem(at: temporary)
            throw error
        }
    }

    private static func decode(_ url: URL) throws -> BottleDXVKInstallation {
        try IndieJSON.decoder().decode(BottleDXVKInstallation.self, from: Data(contentsOf: url))
    }

    private static func installationMatches(_ installation: BottleDXVKInstallation, bottle: BottleRecord) throws -> Bool {
        for (relativePath, hash) in installation.installedFiles {
            let file = bottle.root.appendingPathComponent("drive_c/windows/\(relativePath)")
            guard FileManager.default.fileExists(atPath: file.path),
                  try ManifestSecurity.sha256(of: file) == hash else { return false }
        }
        return true
    }
}
