import Foundation
import IndieCore

public actor RuntimeInstaller {
    private let paths: IndiePaths
    private let subprocess: Subprocess
    private let session: URLSession

    public init(paths: IndiePaths, subprocess: Subprocess = Subprocess(), session: URLSession = .shared) {
        self.paths = paths
        self.subprocess = subprocess
        self.session = session
    }

    public func install(
        manifest: RuntimeManifest,
        publicKeyBase64: String?,
        allowUnsignedDevelopmentManifest: Bool = false
    ) async throws -> URL {
        try paths.createDirectories()
        if let publicKeyBase64 {
            try ManifestSecurity.verify(manifest, publicKeyBase64: publicKeyBase64)
        } else if !allowUnsignedDevelopmentManifest {
            throw IndieError.securityViolation(L("正式安装拒绝未签名运行时清单"))
        }
        try validateHost(manifest)

        let destination = paths.runtimes
            .appendingPathComponent(manifest.id, isDirectory: true)
            .appendingPathComponent(manifest.version.description, isDirectory: true)
        if FileManager.default.fileExists(atPath: destination.path) { return destination }

        let staging = paths.downloads.appendingPathComponent("runtime-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        do {
            for artifact in manifest.artifacts {
                try await installArtifact(artifact, into: staging)
            }
            try IndieJSON.encoder(pretty: true).encode(manifest).write(to: staging.appendingPathComponent("manifest.json"), options: .atomic)
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: staging, to: destination)
            return destination
        } catch {
            try? FileManager.default.removeItem(at: staging)
            throw error
        }
    }

    private func validateHost(_ manifest: RuntimeManifest) throws {
        guard manifest.hostArchitecture == .x86_64 || manifest.hostArchitecture == .arm64 else {
            throw IndieError.unsupported(L("不支持的运行时主机架构：\(manifest.hostArchitecture.rawValue)"))
        }
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let current = SemanticVersion(major: os.majorVersion, minor: os.minorVersion, patch: os.patchVersion)
        guard current >= manifest.minimumMacOS else {
            throw IndieError.unsupported(L("运行时要求 macOS \(manifest.minimumMacOS) 或更高版本"))
        }
        guard manifest.artifacts.allSatisfy({ $0.size >= 0 && $0.sha256.count == 64 }) else {
            throw IndieError.invalidData(L("运行时制品元数据无效"))
        }
    }

    private func installArtifact(_ artifact: ArtifactDescriptor, into staging: URL) async throws {
        guard artifact.url.scheme?.lowercased() == "https" else {
            throw IndieError.securityViolation(L("正式运行时制品必须使用 HTTPS"))
        }
        let (temporaryURL, response) = try await session.download(from: artifact.url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw IndieError.invalidData(L("运行时下载失败：\(artifact.url.absoluteString)"))
        }
        let values = try temporaryURL.resourceValues(forKeys: [.fileSizeKey])
        if artifact.size > 0, Int64(values.fileSize ?? 0) != artifact.size {
            throw IndieError.securityViolation(L("运行时制品尺寸不匹配"))
        }
        guard try ManifestSecurity.sha256(of: temporaryURL) == artifact.sha256 else {
            throw IndieError.securityViolation(L("运行时制品 SHA-256 不匹配"))
        }

        let name = artifact.url.lastPathComponent.lowercased()
        if name.hasSuffix(".zip") {
            try await validateArchive(temporaryURL, kind: .zip)
            try await subprocess.run(URL(fileURLWithPath: "/usr/bin/ditto"), arguments: ["-x", "-k", temporaryURL.path, staging.path], timeout: .seconds(600))
        } else if name.hasSuffix(".tar.xz") || name.hasSuffix(".tar.gz") || name.hasSuffix(".tgz") || name.hasSuffix(".tar") {
            try await validateArchive(temporaryURL, kind: .tar)
            try await subprocess.run(URL(fileURLWithPath: "/usr/bin/tar"), arguments: ["-xf", temporaryURL.path, "-C", staging.path], timeout: .seconds(1_200))
        } else {
            try FileManager.default.copyItem(at: temporaryURL, to: staging.appendingPathComponent(artifact.url.lastPathComponent))
        }
        if let archiveRoot = artifact.archiveRoot {
            try promoteArchiveRoot(archiveRoot, in: staging)
        }
    }

    private func promoteArchiveRoot(_ relativePath: String, in staging: URL) throws {
        let normalized = relativePath.replacingOccurrences(of: "\\", with: "/")
        let components = normalized.split(separator: "/", omittingEmptySubsequences: false)
        guard !normalized.isEmpty, !normalized.hasPrefix("/"), !components.contains("..") else {
            throw IndieError.securityViolation(L("运行时 archiveRoot 非法：\(relativePath)"))
        }
        let payload = staging.appendingPathComponent(normalized, isDirectory: true).standardizedFileURL
        guard payload.path.hasPrefix(staging.standardizedFileURL.path + "/"),
              FileManager.default.fileExists(atPath: payload.path) else {
            throw IndieError.invalidData(L("运行时压缩包缺少 archiveRoot：\(relativePath)"))
        }
        for item in try FileManager.default.contentsOfDirectory(at: payload, includingPropertiesForKeys: nil) {
            let destination = staging.appendingPathComponent(item.lastPathComponent)
            guard !FileManager.default.fileExists(atPath: destination.path) else {
                throw IndieError.invalidData(L("多个运行时制品包含同名路径：\(item.lastPathComponent)"))
            }
            try FileManager.default.moveItem(at: item, to: destination)
        }
        try FileManager.default.removeItem(at: payload)
    }

    private enum ArchiveKind { case zip, tar }

    private func validateArchive(_ archive: URL, kind: ArchiveKind) async throws {
        let result: ProcessResult
        switch kind {
        case .zip:
            result = try await subprocess.run(URL(fileURLWithPath: "/usr/bin/unzip"), arguments: ["-Z1", archive.path], timeout: .seconds(120))
        case .tar:
            result = try await subprocess.run(URL(fileURLWithPath: "/usr/bin/tar"), arguments: ["-tf", archive.path], timeout: .seconds(120))
        }
        for entry in result.stdout.split(whereSeparator: \.isNewline).map(String.init) {
            let path = entry.replacingOccurrences(of: "\\", with: "/")
            let components = path.split(separator: "/", omittingEmptySubsequences: false)
            if path.hasPrefix("/") || components.contains("..") {
                throw IndieError.securityViolation(L("运行时压缩包包含越界路径：\(entry)"))
            }
        }
    }
}
