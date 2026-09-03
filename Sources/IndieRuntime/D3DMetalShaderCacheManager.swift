import Darwin
import Foundation
import IndieCore

public struct D3DMetalShaderProfile: Codable, Equatable, Sendable {
    public let rendererVersion: String
    public let rendererSHA256: String?
    public let metalFX: Bool
    public let dxr: Bool
    public let metal4: Bool
    public let launchArguments: [String]
    public let operatingSystem: String

    public init(
        rendererVersion: String,
        rendererSHA256: String?,
        metalFX: Bool,
        dxr: Bool,
        metal4: Bool,
        launchArguments: [String] = [],
        operatingSystem: String = ProcessInfo.processInfo.operatingSystemVersionString
    ) {
        self.rendererVersion = rendererVersion
        self.rendererSHA256 = rendererSHA256
        self.metalFX = metalFX
        self.dxr = dxr
        self.metal4 = metal4
        self.launchArguments = launchArguments.sorted()
        self.operatingSystem = operatingSystem
    }
}

public struct D3DMetalShaderCachePreparation: Sendable, Equatable {
    public let cache: URL
    public let backup: URL?
    public let profileChanged: Bool
    public let cacheWasMissing: Bool

    public var needsWarmupProtection: Bool { profileChanged || cacheWasMissing }
}

public enum D3DMetalShaderCacheManager {
    public static func cacheRoot(executableName: String) throws -> URL {
        let length = confstr(_CS_DARWIN_USER_CACHE_DIR, nil, 0)
        guard length > 0 else { throw IndieError.notFound("无法定位 macOS 用户缓存目录") }
        var buffer = [CChar](repeating: 0, count: length)
        guard confstr(_CS_DARWIN_USER_CACHE_DIR, &buffer, length) > 0 else {
            throw IndieError.notFound("无法读取 macOS 用户缓存目录")
        }
        let pathBytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        let base = URL(fileURLWithPath: String(decoding: pathBytes, as: UTF8.self), isDirectory: true)
        return base.appendingPathComponent("d3dm", isDirectory: true)
            .appendingPathComponent(safeName(executableName), isDirectory: true)
    }

    public static func prepare(
        executableName: String,
        profile: D3DMetalShaderProfile,
        backupRoot: URL,
        d3dmRoot: URL? = nil,
        now: Date = Date(),
        fileManager: FileManager = .default
    ) throws -> D3DMetalShaderCachePreparation {
        let root = try d3dmRoot ?? cacheRoot(executableName: executableName)
        let cache = root.appendingPathComponent("shaders.cache", isDirectory: true)
        let metadata = root.appendingPathComponent("indie-renderer-profile.json")
        let previous = try? IndieJSON.decoder().decode(D3DMetalShaderProfile.self, from: Data(contentsOf: metadata))
        let cacheExists = fileManager.fileExists(atPath: cache.path)
        let profileChanged = previous != profile
        var backup: URL?

        if cacheExists && profileChanged {
            try fileManager.createDirectory(at: backupRoot, withIntermediateDirectories: true)
            let formatter = ISO8601DateFormatter()
            let stamp = formatter.string(from: now).replacingOccurrences(of: ":", with: "-")
            let destination = backupRoot.appendingPathComponent(
                "\(safeName(executableName))-\(stamp)-\(UUID().uuidString.prefix(8))",
                isDirectory: true
            )
            try fileManager.moveItem(at: cache, to: destination)
            backup = destination
        }

        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        try IndieJSON.encoder(pretty: true).encode(profile).write(to: metadata, options: .atomic)
        return D3DMetalShaderCachePreparation(
            cache: cache,
            backup: backup,
            profileChanged: profileChanged,
            cacheWasMissing: !cacheExists
        )
    }

    private static func safeName(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let sanitized = value.unicodeScalars.map { allowed.contains($0) ? Character(String($0)) : "_" }
        return String(sanitized)
    }
}
