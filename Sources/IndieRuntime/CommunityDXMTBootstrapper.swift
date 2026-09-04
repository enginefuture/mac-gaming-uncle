import Foundation
import IndieCore

public struct DXMTBootstrapRelease: Sendable, Equatable {
    public let version: String
    public let downloadSize: Int64
    public let sha256: String
}

/// Downloads the audited upstream DXMT builtin overlay. DXMT is kept outside
/// the Wine runtime so it can be selected per game and upgraded independently.
public actor CommunityDXMTBootstrapper {
    public static let release = DXMTBootstrapRelease(
        version: "0.80",
        downloadSize: 18_681_669,
        sha256: "8f260e36b5739e68f3bad613381441385c4dc7b85b78ba8de653d5a6a264529d"
    )

    private static let downloadURL = URL(
        string: "https://github.com/3Shain/dxmt/releases/download/v0.80/dxmt-v0.80-builtin.tar.gz"
    )!

    private let paths: IndiePaths
    private let subprocess: Subprocess
    private let session: URLSession

    public init(paths: IndiePaths, subprocess: Subprocess = Subprocess(), session: URLSession = .shared) {
        self.paths = paths
        self.subprocess = subprocess
        self.session = session
    }

    public func installLatest() async throws -> RendererOverlay {
        if let existing = await RendererOverlayImporter(paths: paths).installed().first(where: {
            $0.kind == .dxmt && $0.version == Self.release.version
        }) { return existing }

        try paths.createDirectories()
        let (download, response) = try await session.download(from: Self.downloadURL)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw IndieError.invalidData("DXMT 下载失败")
        }
        let size = Int64(try download.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
        guard size == Self.release.downloadSize else {
            throw IndieError.securityViolation("DXMT 制品尺寸不匹配")
        }
        guard try ManifestSecurity.sha256(of: download) == Self.release.sha256 else {
            throw IndieError.securityViolation("DXMT 制品 SHA-256 不匹配")
        }

        let staging = paths.downloads.appendingPathComponent("dxmt-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: staging) }
        try await validateArchive(download)
        try await subprocess.run(
            URL(fileURLWithPath: "/usr/bin/tar"),
            arguments: ["-xzf", download.path, "-C", staging.path], timeout: .seconds(120)
        )
        guard let source = Self.findPayload(in: staging) else {
            throw IndieError.invalidData("DXMT 压缩包缺少 Wine builtin Bridge")
        }
        return try await RendererOverlayImporter(paths: paths).importOverlay(.dxmt, from: source)
    }

    private func validateArchive(_ archive: URL) async throws {
        let listing = try await subprocess.run(
            URL(fileURLWithPath: "/usr/bin/tar"), arguments: ["-tf", archive.path], timeout: .seconds(30)
        )
        for entry in listing.stdout.split(whereSeparator: \.isNewline).map(String.init) {
            let path = entry.replacingOccurrences(of: "\\", with: "/")
            if path.hasPrefix("/") || path.split(separator: "/", omittingEmptySubsequences: false).contains("..") {
                throw IndieError.securityViolation("DXMT 压缩包包含越界路径：\(entry)")
            }
        }
    }

    private static func findPayload(in root: URL) -> URL? {
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
        ) else { return nil }
        for case let directory as URL in enumerator {
            guard (try? directory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            let required = [
                "x86_64-windows/dxgi.dll", "x86_64-windows/d3d11.dll",
                "x86_64-windows/d3d10core.dll", "x86_64-unix/winemetal.so",
            ].map(directory.appendingPathComponent)
            if required.allSatisfy({ FileManager.default.fileExists(atPath: $0.path) }) { return directory }
        }
        return nil
    }
}
