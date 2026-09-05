import Foundation
import IndieCore

public struct LocalWineRuntime: Codable, Sendable, Identifiable, Equatable {
    public var id: String { "\(manifest.id)@\(manifest.version)" }
    public let manifest: RuntimeManifest
    public let root: URL
    public let importedAt: Date
}

public actor LocalWineImporter {
    private let paths: IndiePaths
    private let subprocess: Subprocess

    public init(paths: IndiePaths, subprocess: Subprocess = Subprocess()) {
        self.paths = paths
        self.subprocess = subprocess
    }

    public func importRuntime(from source: URL) async throws -> LocalWineRuntime {
        try paths.createDirectories()
        guard let sourceWine = Self.findWine(in: source) else {
            throw IndieError.notFound(L("所选目录中没有 Wine 可执行文件"))
        }
        let versionOutput = try await subprocess.run(sourceWine, arguments: ["--version"], timeout: .seconds(20))
        let version = try Self.parseVersion(versionOutput.stdout + versionOutput.stderr)
        let lipo = try? await subprocess.run(
            URL(fileURLWithPath: "/usr/bin/lipo"), arguments: ["-archs", sourceWine.path],
            timeout: .seconds(10), requireSuccess: false
        )
        let file = try await subprocess.run(
            URL(fileURLWithPath: "/usr/bin/file"), arguments: [sourceWine.path], timeout: .seconds(10)
        )
        let architectures = ((lipo?.stdout ?? "") + file.stdout).lowercased()
        guard architectures.contains("x86_64") else {
            throw IndieError.unsupported(L("首版只接受包含 x86_64 的 macOS Wine 运行时"))
        }

        let runtimeID = "org.indie.wine.local"
        let destination = paths.runtimes
            .appendingPathComponent(runtimeID, isDirectory: true)
            .appendingPathComponent(version.description, isDirectory: true)
        let metadataURL = destination.appendingPathComponent("local-runtime.json")
        if let data = try? Data(contentsOf: metadataURL),
           let existing = try? IndieJSON.decoder().decode(LocalWineRuntime.self, from: data) { return existing }

        let manifest = RuntimeManifest(
            id: runtimeID,
            displayName: "Local Wine \(version)",
            version: version,
            channel: .experimental,
            hostArchitecture: .x86_64,
            minimumMacOS: SemanticVersion(major: 15, minor: 0),
            capabilities: RuntimeCapabilities(
                architectures: [.i386, .x86_64], renderers: [.wineD3D],
                supportsWoW64: version.major >= 9, supportsMSync: true
            ),
            artifacts: [],
            licenses: [LicenseDescriptor(
                identifier: "LGPL-2.1-or-later", name: "Wine GNU LGPL",
                sourceURL: URL(string: "https://gitlab.winehq.org/wine/wine")!,
                correspondingSourceURL: nil
            )],
            publishedAt: Date(),
            signature: nil
        )
        let staging = paths.runtimes.appendingPathComponent(".wine-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
            let payload = staging.appendingPathComponent("payload", isDirectory: true)
            try FileManager.default.copyItem(at: source, to: payload)
            guard Self.findWine(in: payload) != nil else { throw IndieError.invalidData(L("复制后的 Wine 运行时不完整")) }
            let imported = LocalWineRuntime(manifest: manifest, root: staging, importedAt: Date())
            try IndieJSON.encoder(pretty: true).encode(imported).write(to: staging.appendingPathComponent("local-runtime.json"), options: .atomic)
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: staging, to: destination)
            return LocalWineRuntime(manifest: manifest, root: destination, importedAt: imported.importedAt)
        } catch {
            try? FileManager.default.removeItem(at: staging)
            throw error
        }
    }

    public func installed() -> [LocalWineRuntime] {
        let runtimeIDs = (try? FileManager.default.contentsOfDirectory(at: paths.runtimes, includingPropertiesForKeys: nil)) ?? []
        return runtimeIDs.flatMap { runtimeID -> [LocalWineRuntime] in
            let versions = (try? FileManager.default.contentsOfDirectory(at: runtimeID, includingPropertiesForKeys: nil)) ?? []
            return versions.compactMap { url in
                let metadata = url.appendingPathComponent("local-runtime.json")
                guard let data = try? Data(contentsOf: metadata),
                      let value = try? IndieJSON.decoder().decode(LocalWineRuntime.self, from: data) else { return nil }
                return LocalWineRuntime(manifest: value.manifest, root: url, importedAt: value.importedAt)
            }
        }.sorted { $0.manifest.version > $1.manifest.version }
    }

    public static func findWine(in root: URL) -> URL? {
        let directCandidates = [
            root.appendingPathComponent("bin/wine64"), root.appendingPathComponent("bin/wine"),
            root.appendingPathComponent("Contents/Resources/wine/bin/wine64"), root.appendingPathComponent("Contents/Resources/wine/bin/wine"),
            root.appendingPathComponent("Wine.app/Contents/Resources/wine/bin/wine64"), root.appendingPathComponent("Wine.app/Contents/Resources/wine/bin/wine"),
            root.appendingPathComponent("Wine Staging.app/Contents/Resources/wine/bin/wine64"), root.appendingPathComponent("Wine Staging.app/Contents/Resources/wine/bin/wine"),
            root.appendingPathComponent("Wine Devel.app/Contents/Resources/wine/bin/wine64"), root.appendingPathComponent("Wine Devel.app/Contents/Resources/wine/bin/wine"),
            root.appendingPathComponent("payload/Contents/Resources/wine/bin/wine64"), root.appendingPathComponent("payload/Contents/Resources/wine/bin/wine"),
            root.appendingPathComponent("payload/bin/wine64"), root.appendingPathComponent("payload/bin/wine"),
            root.appendingPathComponent("wswine.bundle/bin/wine"),
        ]
        return directCandidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    private static func parseVersion(_ output: String) throws -> SemanticVersion {
        let pattern = #"([0-9]+\.[0-9]+(?:\.[0-9]+)?(?:-[A-Za-z0-9.]+)?)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)),
              let range = Range(match.range(at: 1), in: output) else {
            throw IndieError.invalidData("无法识别 Wine 版本：\(output)")
        }
        return try SemanticVersion(String(output[range]))
    }
}
