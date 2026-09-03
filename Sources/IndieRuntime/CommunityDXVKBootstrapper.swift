import Foundation
import IndieCore

public struct DXVKBootstrapRelease: Sendable, Equatable {
    public let version: String
    public let downloadSize: Int64
    public let assetName: String
    public let sha256: String
}

/// Installs the last macOS-specific DXVK release. Upstream DXVK builds require
/// Vulkan features that MoltenVK does not expose, so they are not interchangeable
/// with this fork. The release asset predates GitHub's digest field; Indie pins
/// the reviewed asset by exact size and SHA-256 instead.
public actor CommunityDXVKBootstrapper {
    public static let release = DXVKBootstrapRelease(
        version: "1.10.3",
        downloadSize: 2_793_443,
        assetName: "dxvk-macOS-async-v1.10.3-20230507-repack.tar.gz",
        sha256: "acd1520ad105d8ef124a09c8e11a259a5dc8bdc565ad18e0e52693f9807b2477"
    )

    private static let downloadURL = URL(
        string: "https://github.com/Gcenx/DXVK-macOS/releases/download/v1.10.3-20230507-repack/dxvk-macOS-async-v1.10.3-20230507-repack.tar.gz"
    )!

    private let paths: IndiePaths
    private let subprocess: Subprocess
    private let session: URLSession

    public init(paths: IndiePaths, subprocess: Subprocess = Subprocess(), session: URLSession = .shared) {
        self.paths = paths
        self.subprocess = subprocess
        self.session = session
    }

    public func latest() -> DXVKBootstrapRelease { Self.release }

    public func installLatest() async throws -> RendererOverlay {
        if let existing = await RendererOverlayImporter(paths: paths).installed().first(where: {
            $0.kind == .dxvk && $0.version == Self.release.version
        }) { return existing }

        try paths.createDirectories()
        let (download, response) = try await session.download(from: Self.downloadURL)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw IndieError.invalidData("DXVK-macOS 下载失败")
        }
        let size = Int64(try download.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
        guard size == Self.release.downloadSize else {
            throw IndieError.securityViolation("DXVK-macOS 制品尺寸不匹配")
        }
        guard try ManifestSecurity.sha256(of: download) == Self.release.sha256 else {
            throw IndieError.securityViolation("DXVK-macOS 制品 SHA-256 不匹配")
        }

        let staging = paths.downloads.appendingPathComponent("dxvk-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: staging) }
        try await validateArchive(download)
        try await subprocess.run(
            URL(fileURLWithPath: "/usr/bin/tar"),
            arguments: ["-xzf", download.path, "-C", staging.path],
            timeout: .seconds(120)
        )
        guard let source = Self.findPayload(in: staging) else {
            throw IndieError.invalidData("DXVK-macOS 压缩包缺少 x64/x32 D3D11 DLL")
        }
        return try await RendererOverlayImporter(paths: paths).importOverlay(.dxvk, from: source)
    }

    private func validateArchive(_ archive: URL) async throws {
        let listing = try await subprocess.run(
            URL(fileURLWithPath: "/usr/bin/tar"),
            arguments: ["-tf", archive.path], timeout: .seconds(30)
        )
        for entry in listing.stdout.split(whereSeparator: \.isNewline).map(String.init) {
            let path = entry.replacingOccurrences(of: "\\", with: "/")
            if path.hasPrefix("/") || path.split(separator: "/", omittingEmptySubsequences: false).contains("..") {
                throw IndieError.securityViolation("DXVK-macOS 压缩包包含越界路径：\(entry)")
            }
        }
    }

    private static func findPayload(in root: URL) -> URL? {
        let manager = FileManager.default
        guard let enumerator = manager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }
        for case let directory as URL in enumerator {
            guard (try? directory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            let required = [
                directory.appendingPathComponent("x64/d3d11.dll"),
                directory.appendingPathComponent("x64/d3d10core.dll"),
                directory.appendingPathComponent("x32/d3d11.dll"),
                directory.appendingPathComponent("x32/d3d10core.dll"),
            ]
            if required.allSatisfy({ manager.fileExists(atPath: $0.path) }) { return directory }
        }
        return nil
    }
}
