import Foundation
import IndieCore

public struct StagedWindowsInstaller: Sendable, Equatable {
    public let fileURL: URL
    public let windowsPath: String
}

public actor SteamInstaller {
    public static let officialURL = URL(string: "https://cdn.fastly.steamstatic.com/client/installer/SteamSetup.exe")!

    private let paths: IndiePaths
    private let session: URLSession

    public init(paths: IndiePaths, session: URLSession = .shared) {
        self.paths = paths
        self.session = session
    }

    public func download() async throws -> URL {
        try paths.createDirectories()
        let destination = paths.downloads.appendingPathComponent("SteamSetup.exe")
        let (temporary, response) = try await session.download(from: Self.officialURL)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              http.url?.host?.lowercased() == "cdn.fastly.steamstatic.com" else {
            throw IndieError.securityViolation("Steam 安装器没有来自 Valve 官方 CDN")
        }
        let size = (try temporary.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size > 1_000_000 else { throw IndieError.invalidData("Steam 安装器尺寸异常") }
        let staging = paths.downloads.appendingPathComponent(".SteamSetup-\(UUID().uuidString).exe")
        try FileManager.default.moveItem(at: temporary, to: staging)
        if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
        try FileManager.default.moveItem(at: staging, to: destination)
        return destination
    }

    public func stageForLaunch(_ installer: URL, in bottle: BottleRecord) throws -> StagedWindowsInstaller {
        let hash = try ManifestSecurity.sha256(of: installer)
        let directory = bottle.root.appendingPathComponent("drive_c/users/Public/Downloads/Mac Gaming Uncle", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent("SteamSetup-\(hash.prefix(12)).exe")
        if !FileManager.default.fileExists(atPath: destination.path) {
            let staging = directory.appendingPathComponent(".SteamSetup-\(UUID().uuidString).exe")
            do {
                try FileManager.default.copyItem(at: installer, to: staging)
                try FileManager.default.moveItem(at: staging, to: destination)
            } catch {
                try? FileManager.default.removeItem(at: staging)
                throw error
            }
        }
        return StagedWindowsInstaller(
            fileURL: destination,
            windowsPath: try WinePath.windowsPath(for: destination, in: bottle)
        )
    }
}
