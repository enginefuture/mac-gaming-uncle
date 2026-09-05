import Foundation
import IndieCore

/// Unmodified, separately downloaded Apple evaluation image. The image retains
/// its original license and notices; the importer verifies Apple's signature.
public actor GPTKDownloadService {
    public static let version = "4.0b2"
    public static let filename = "Evaluation_environment_for_Windows_games_4.0_beta_2.dmg"
    public static let size: Int64 = 26_480_358
    public static let sha256 = "6248a0edc61553790753e5e9c060b8e53c940ed197f11409dcc34a35e05becc1"
    public static let downloadURL = URL(string:
        "https://download.pingclaws.com/mac-gaming-uncle/gptk/4.0b2/" + sha256 + "/" + filename
    )!

    private let paths: IndiePaths
    private let session: URLSession

    public init(paths: IndiePaths, session: URLSession = .shared) {
        self.paths = paths
        self.session = session
    }

    public func download() async throws -> URL {
        try paths.createDirectories()
        let directory = paths.downloads.appendingPathComponent("gptk-" + Self.sha256, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let cached = directory.appendingPathComponent(Self.filename)
        if FileManager.default.fileExists(atPath: cached.path), (try? Self.validate(cached)) != nil {
            return cached
        }
        var request = URLRequest(url: Self.downloadURL)
        request.timeoutInterval = 600
        request.cachePolicy = .reloadIgnoringLocalCacheData
        for attempt in 0..<3 {
            do {
                try Task.checkCancellation()
                let (temporary, response) = try await session.download(for: request)
                defer { try? FileManager.default.removeItem(at: temporary) }
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    throw IndieError.invalidData(L("GPTK 下载失败，请检查网络后重试"))
                }
                try Self.validate(temporary)
                try Task.checkCancellation()
                if FileManager.default.fileExists(atPath: cached.path) {
                    _ = try FileManager.default.replaceItemAt(cached, withItemAt: temporary)
                } else {
                    try FileManager.default.moveItem(at: temporary, to: cached)
                }
                return cached
            } catch {
                try Task.checkCancellation()
                if attempt == 2 { throw error }
                try await Task.sleep(for: .seconds(attempt + 1))
            }
        }
        throw IndieError.invalidData(L("GPTK 下载未完成"))
    }

    public static func validate(_ file: URL) throws {
        let actualSize = Int64(try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
        guard actualSize == size else { throw IndieError.securityViolation(L("GPTK 安装包大小校验失败")) }
        guard try ManifestSecurity.sha256(of: file) == sha256 else {
            throw IndieError.securityViolation(L("GPTK 安装包 SHA-256 校验失败"))
        }
    }
}
