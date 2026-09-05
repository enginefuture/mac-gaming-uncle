import CryptoKit
import Foundation
import IndieCore

public struct ImportedD3DMetal: Codable, Sendable, Equatable {
    public let version: String
    public let root: URL
    public let framework: URL
    public let sharedLibrary: URL?
    public let rendererRoot: URL?
    public let runtimeRoot: URL?
    public let sourceSHA256: String?
    public let importedAt: Date
}

public actor GPTKImporter {
    private let paths: IndiePaths

    public init(paths: IndiePaths) { self.paths = paths }

    public func importFromAppleImage(_ source: URL) throws -> ImportedD3DMetal {
        try paths.createDirectories()
        var mounted: [URL] = []
        defer {
            for volume in mounted.reversed() {
                _ = try? Self.runSync("/usr/bin/hdiutil", ["detach", volume.path, "-quiet"])
            }
        }

        var searchRoot = source
        if source.pathExtension.lowercased() == "dmg" {
            _ = try Self.runSync("/usr/bin/hdiutil", ["verify", source.path])
            searchRoot = try Self.mount(source)
            mounted.append(searchRoot)
        }

        var framework = Self.find(named: "D3DMetal.framework", under: searchRoot)
        if framework == nil, let inner = Self.findEvaluationImage(under: searchRoot) {
            let innerRoot = try Self.mount(inner)
            mounted.append(innerRoot)
            searchRoot = innerRoot
            framework = Self.find(named: "D3DMetal.framework", under: searchRoot)
        }
        guard let framework else {
            throw IndieError.notFound(L("选择的 Apple GPTK 镜像中没有 D3DMetal.framework"))
        }
        try Self.verifyAppleSignature(framework)
        let sourceRenderer = Self.findRendererRoot(containing: framework)
        let sourceRuntime = Self.findRuntimeRoot(containing: framework, under: searchRoot)

        let version = Self.bundleVersion(framework) ?? "unknown"
        let safeVersion = version.replacingOccurrences(of: "/", with: "-")
        let destination = paths.importedComponents
            .appendingPathComponent("D3DMetal", isDirectory: true)
            .appendingPathComponent(safeVersion, isDirectory: true)
        let existingFramework = destination.appendingPathComponent("D3DMetal.framework", isDirectory: true)
        if FileManager.default.fileExists(atPath: existingFramework.path) {
            let destinationRuntime = destination.appendingPathComponent("runtime", isDirectory: true)
            let destinationRenderer = destination.appendingPathComponent("renderer", isDirectory: true)
            if !Self.hasRendererPayload(destinationRenderer), let sourceRenderer {
                let stagedRenderer = paths.importedComponents.appendingPathComponent(".gptk-renderer-\(UUID().uuidString)", isDirectory: true)
                defer { try? FileManager.default.removeItem(at: stagedRenderer) }
                try FileManager.default.copyItem(at: sourceRenderer, to: stagedRenderer)
                try FileManager.default.moveItem(at: stagedRenderer, to: destinationRenderer)
            }
            if !Self.hasWineRuntime(destinationRuntime), let sourceRuntime {
                let stagedRuntime = paths.importedComponents.appendingPathComponent(".gptk-runtime-\(UUID().uuidString)", isDirectory: true)
                defer { try? FileManager.default.removeItem(at: stagedRuntime) }
                try FileManager.default.copyItem(at: sourceRuntime, to: stagedRuntime)
                try FileManager.default.moveItem(at: stagedRuntime, to: destinationRuntime)
            }
            let imported = ImportedD3DMetal(
                version: version,
                root: destination,
                framework: existingFramework,
                sharedLibrary: Self.find(named: "libd3dshared.dylib", under: destination),
                rendererRoot: Self.hasRendererPayload(destinationRenderer) ? destinationRenderer : nil,
                runtimeRoot: Self.hasWineRuntime(destinationRuntime) ? destinationRuntime : nil,
                sourceSHA256: source.isFileURL && source.pathExtension == "dmg" ? try? ManifestSecurity.sha256(of: source) : nil,
                importedAt: Date()
            )
            try IndieJSON.encoder(pretty: true).encode(imported)
                .write(to: destination.appendingPathComponent("import.json"), options: .atomic)
            return imported
        }

        let staging = paths.importedComponents.appendingPathComponent(".d3dmetal-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        do {
            let stagedFramework = staging.appendingPathComponent("D3DMetal.framework", isDirectory: true)
            try FileManager.default.copyItem(at: framework, to: stagedFramework)
            var stagedShared: URL?
            if let shared = Self.find(named: "libd3dshared.dylib", under: searchRoot) {
                try Self.verifyAppleSignature(shared)
                let target = staging.appendingPathComponent("libd3dshared.dylib")
                try FileManager.default.copyItem(at: shared, to: target)
                stagedShared = target
            }
            let stagedRuntime: URL?
            if let sourceRuntime {
                let target = staging.appendingPathComponent("runtime", isDirectory: true)
                try FileManager.default.copyItem(at: sourceRuntime, to: target)
                stagedRuntime = target
            } else {
                stagedRuntime = nil
            }
            let stagedRenderer: URL?
            if let sourceRenderer {
                let target = staging.appendingPathComponent("renderer", isDirectory: true)
                try FileManager.default.copyItem(at: sourceRenderer, to: target)
                stagedRenderer = target
            } else {
                stagedRenderer = nil
            }
            let imported = ImportedD3DMetal(
                version: version,
                root: destination,
                framework: destination.appendingPathComponent("D3DMetal.framework"),
                sharedLibrary: stagedShared.map { _ in destination.appendingPathComponent("libd3dshared.dylib") },
                rendererRoot: stagedRenderer.map { _ in destination.appendingPathComponent("renderer", isDirectory: true) },
                runtimeRoot: stagedRuntime.map { _ in destination.appendingPathComponent("runtime", isDirectory: true) },
                sourceSHA256: source.pathExtension.lowercased() == "dmg" ? try? ManifestSecurity.sha256(of: source) : nil,
                importedAt: Date()
            )
            try IndieJSON.encoder(pretty: true).encode(imported).write(to: staging.appendingPathComponent("import.json"), options: .atomic)
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: staging, to: destination)
            return imported
        } catch {
            try? FileManager.default.removeItem(at: staging)
            throw error
        }
    }

    public func installedComponents() throws -> [ImportedD3DMetal] {
        let base = paths.importedComponents.appendingPathComponent("D3DMetal", isDirectory: true)
        guard let directories = try? FileManager.default.contentsOfDirectory(at: base, includingPropertiesForKeys: nil) else { return [] }
        return directories.compactMap { directory in
            let metadata = directory.appendingPathComponent("import.json")
            guard let data = try? Data(contentsOf: metadata) else { return nil }
            return try? IndieJSON.decoder().decode(ImportedD3DMetal.self, from: data)
        }.sorted { $0.version > $1.version }
    }

    private static func mount(_ image: URL) throws -> URL {
        let result = try runSync("/usr/bin/hdiutil", ["attach", image.path, "-readonly", "-nobrowse", "-plist"])
        guard let data = result.data(using: .utf8),
              let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let entities = plist["system-entities"] as? [[String: Any]],
              let point = entities.compactMap({ $0["mount-point"] as? String }).last else {
            throw IndieError.invalidData(L("无法读取 GPTK 镜像挂载点"))
        }
        return URL(fileURLWithPath: point, isDirectory: true)
    }

    private static func findEvaluationImage(under root: URL) -> URL? {
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else { return nil }
        for case let url as URL in enumerator {
            let name = url.lastPathComponent.lowercased()
            if url.pathExtension.lowercased() == "dmg" && (name.contains("evaluation") || name.contains("windows")) { return url }
        }
        return nil
    }

    private static func find(named name: String, under root: URL) -> URL? {
        if root.lastPathComponent.caseInsensitiveCompare(name) == .orderedSame { return root }
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return nil }
        for case let url as URL in enumerator {
            if url.lastPathComponent.caseInsensitiveCompare(name) == .orderedSame {
                if url.pathExtension == "framework" { enumerator.skipDescendants() }
                return url
            }
        }
        return nil
    }

    private static func findRuntimeRoot(containing framework: URL, under searchRoot: URL) -> URL? {
        var candidate = framework.deletingLastPathComponent()
        let boundary = searchRoot.standardizedFileURL.path
        while candidate.standardizedFileURL.path.hasPrefix(boundary) {
            if hasWineRuntime(candidate) { return candidate }
            let parent = candidate.deletingLastPathComponent()
            if parent == candidate { break }
            candidate = parent
        }
        guard let enumerator = FileManager.default.enumerator(at: searchRoot, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return nil }
        for case let url as URL in enumerator where url.lastPathComponent == "wine64" && url.deletingLastPathComponent().lastPathComponent == "bin" {
            let root = url.deletingLastPathComponent().deletingLastPathComponent()
            if hasWineRuntime(root) { return root }
        }
        return nil
    }

    private static func findRendererRoot(containing framework: URL) -> URL? {
        let external = framework.deletingLastPathComponent()
        guard external.lastPathComponent == "external" else { return nil }
        let root = external.deletingLastPathComponent()
        return hasRendererPayload(root) ? root : nil
    }

    private static func hasRendererPayload(_ root: URL) -> Bool {
        let required = [
            "external/D3DMetal.framework",
            "external/libd3dshared.dylib",
            "wine/x86_64-windows/dxgi.dll",
            "wine/x86_64-windows/d3d11.dll",
            "wine/x86_64-windows/d3d12.dll",
            "wine/x86_64-unix/dxgi.so",
            "wine/x86_64-unix/d3d11.so",
            "wine/x86_64-unix/d3d12.so",
        ]
        return required.allSatisfy { FileManager.default.fileExists(atPath: root.appendingPathComponent($0).path) }
    }

    private static func hasWineRuntime(_ root: URL) -> Bool {
        FileManager.default.isExecutableFile(atPath: root.appendingPathComponent("bin/wine64").path)
            && FileManager.default.fileExists(atPath: root.appendingPathComponent("lib/wine", isDirectory: true).path)
    }

    private static func verifyAppleSignature(_ url: URL) throws {
        _ = try runSync("/usr/bin/codesign", ["--verify", "--deep", "--strict", url.path])
        let details = try runSync("/usr/bin/codesign", ["-d", "--verbose=4", url.path], includeStandardError: true).lowercased()
        let isD3DMetal = url.lastPathComponent == "libd3dshared.dylib" || details.contains("identifier=com.apple.d3dmetal") || details.contains("identifier=d3dmetal")
        let appleChain = details.contains("authority=apple") || details.contains("apple code signing certification authority")
        guard isD3DMetal, appleChain else {
            throw IndieError.securityViolation(L("D3DMetal 组件不是可验证的 Apple 签名产物"))
        }
    }

    private static func bundleVersion(_ framework: URL) -> String? {
        let candidates = [framework.appendingPathComponent("Resources/Info.plist"), framework.appendingPathComponent("Versions/A/Resources/Info.plist")]
        for plistURL in candidates {
            guard let data = try? Data(contentsOf: plistURL),
                  let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { continue }
            if let version = plist["CFBundleShortVersionString"] as? String ?? plist["CFBundleVersion"] as? String { return version }
        }
        return nil
    }

    @discardableResult
    private static func runSync(_ executable: String, _ arguments: [String], includeStandardError: Bool = false) throws -> String {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        let output = stdout.fileHandleForReading.readDataToEndOfFile()
        let error = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let errorText = String(decoding: error, as: UTF8.self)
        guard process.terminationStatus == 0 else {
            throw IndieError.processFailed(executable: executable, status: process.terminationStatus, stderr: errorText)
        }
        return String(decoding: output, as: UTF8.self) + (includeStandardError ? errorText : "")
    }
}
