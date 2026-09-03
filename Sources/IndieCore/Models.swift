import Foundation

public enum ReleaseChannel: String, Codable, CaseIterable, Sendable {
    case stable
    case candidate
    case experimental
}

public enum CPUArchitecture: String, Codable, CaseIterable, Sendable {
    case i386
    case x86_64
    case arm64
    case arm64ec
    case unknown
}

public enum DirectXVersion: String, Codable, CaseIterable, Sendable, Comparable {
    case none
    case d3d8
    case d3d9
    case d3d10
    case d3d11
    case d3d12

    private var order: Int {
        switch self {
        case .none: 0
        case .d3d8: 8
        case .d3d9: 9
        case .d3d10: 10
        case .d3d11: 11
        case .d3d12: 12
        }
    }

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.order < rhs.order }
}

public enum RendererKind: String, Codable, CaseIterable, Sendable {
    case d3dMetal = "d3dmetal"
    case dxmt
    case dxvk
    case wineD3D = "wined3d"
    case vkd3d
}

public enum SyncBackend: String, Codable, CaseIterable, Sendable {
    case automatic
    case msync
    case wineserver
}

public enum AntiCheatStatus: String, Codable, CaseIterable, Sendable {
    case none
    case userSpace = "user-space"
    case kernel
    case unknown
}

public enum SetupStage: Int, Codable, CaseIterable, Sendable {
    case environment = 1
    case steam = 2
    case game = 3
    case ready = 4
}

public enum SetupFlow {
    public static func stage(environmentReady: Bool, steamInstalled: Bool, installedGameCount: Int) -> SetupStage {
        if !environmentReady { return .environment }
        if !steamInstalled { return .steam }
        if installedGameCount == 0 { return .game }
        return .ready
    }
}

public struct SemanticVersion: Codable, Hashable, Sendable, Comparable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int
    public let prerelease: String?

    public init(_ value: String) throws {
        let pieces = value.split(separator: "-", maxSplits: 1).map(String.init)
        let numbers = pieces[0].split(separator: ".").compactMap { Int($0) }
        guard numbers.count >= 2 else { throw IndieError.invalidData("无效版本号：\(value)") }
        major = numbers[0]
        minor = numbers[1]
        patch = numbers.count > 2 ? numbers[2] : 0
        prerelease = pieces.count > 1 ? pieces[1] : nil
    }

    public init(major: Int, minor: Int, patch: Int = 0, prerelease: String? = nil) {
        self.major = major
        self.minor = minor
        self.patch = patch
        self.prerelease = prerelease
    }

    public var description: String {
        "\(major).\(minor).\(patch)" + (prerelease.map { "-\($0)" } ?? "")
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        let left = [lhs.major, lhs.minor, lhs.patch]
        let right = [rhs.major, rhs.minor, rhs.patch]
        if left != right { return left.lexicographicallyPrecedes(right) }
        return switch (lhs.prerelease, rhs.prerelease) {
        case (.some, .none): true
        case (.none, .some): false
        case let (.some(a), .some(b)): a < b
        case (.none, .none): false
        }
    }
}

public struct ArtifactDescriptor: Codable, Hashable, Sendable {
    public let url: URL
    public let sha256: String
    public let size: Int64
    public let archiveRoot: String?

    public init(url: URL, sha256: String, size: Int64, archiveRoot: String? = nil) {
        self.url = url
        self.sha256 = sha256.lowercased()
        self.size = size
        self.archiveRoot = archiveRoot
    }
}

public struct LicenseDescriptor: Codable, Hashable, Sendable {
    public let identifier: String
    public let name: String
    public let sourceURL: URL
    public let correspondingSourceURL: URL?

    public init(identifier: String, name: String, sourceURL: URL, correspondingSourceURL: URL? = nil) {
        self.identifier = identifier
        self.name = name
        self.sourceURL = sourceURL
        self.correspondingSourceURL = correspondingSourceURL
    }
}

public struct RuntimeCapabilities: Codable, Hashable, Sendable {
    public var architectures: Set<CPUArchitecture>
    public var renderers: Set<RendererKind>
    public var supportsWoW64: Bool
    public var supportsMSync: Bool

    public init(
        architectures: Set<CPUArchitecture>,
        renderers: Set<RendererKind>,
        supportsWoW64: Bool,
        supportsMSync: Bool
    ) {
        self.architectures = architectures
        self.renderers = renderers
        self.supportsWoW64 = supportsWoW64
        self.supportsMSync = supportsMSync
    }

    private enum CodingKeys: String, CodingKey {
        case architectures, renderers, supportsWoW64, supportsMSync
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        architectures = Set(try container.decode([CPUArchitecture].self, forKey: .architectures))
        renderers = Set(try container.decode([RendererKind].self, forKey: .renderers))
        supportsWoW64 = try container.decode(Bool.self, forKey: .supportsWoW64)
        supportsMSync = try container.decode(Bool.self, forKey: .supportsMSync)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(architectures.sorted { $0.rawValue < $1.rawValue }, forKey: .architectures)
        try container.encode(renderers.sorted { $0.rawValue < $1.rawValue }, forKey: .renderers)
        try container.encode(supportsWoW64, forKey: .supportsWoW64)
        try container.encode(supportsMSync, forKey: .supportsMSync)
    }
}

public struct RuntimeManifest: Codable, Hashable, Sendable, Identifiable {
    public let schemaVersion: Int
    public let id: String
    public let displayName: String
    public let version: SemanticVersion
    public let channel: ReleaseChannel
    public let hostArchitecture: CPUArchitecture
    public let minimumMacOS: SemanticVersion
    public let capabilities: RuntimeCapabilities
    public let artifacts: [ArtifactDescriptor]
    public let licenses: [LicenseDescriptor]
    public let publishedAt: Date
    public let signature: String?

    public init(
        schemaVersion: Int = 1,
        id: String,
        displayName: String,
        version: SemanticVersion,
        channel: ReleaseChannel,
        hostArchitecture: CPUArchitecture,
        minimumMacOS: SemanticVersion,
        capabilities: RuntimeCapabilities,
        artifacts: [ArtifactDescriptor],
        licenses: [LicenseDescriptor],
        publishedAt: Date,
        signature: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.displayName = displayName
        self.version = version
        self.channel = channel
        self.hostArchitecture = hostArchitecture
        self.minimumMacOS = minimumMacOS
        self.capabilities = capabilities
        self.artifacts = artifacts
        self.licenses = licenses
        self.publishedAt = publishedAt
        self.signature = signature
    }
}

public struct BottleRecord: Codable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public var name: String
    public let root: URL
    public let runtimeID: String
    public let createdAt: Date
    public var updatedAt: Date

    public init(id: UUID = UUID(), name: String, root: URL, runtimeID: String, createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.root = root
        self.runtimeID = runtimeID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct GameIdentity: Codable, Hashable, Sendable {
    public let steamAppID: UInt64?
    public let executableSHA256: String?
    public let executableName: String

    public init(steamAppID: UInt64? = nil, executableSHA256: String? = nil, executableName: String) {
        self.steamAppID = steamAppID
        self.executableSHA256 = executableSHA256
        self.executableName = executableName
    }
}

public struct GameAnalysis: Codable, Hashable, Sendable {
    public let identity: GameIdentity
    public let architecture: CPUArchitecture
    public let directX: DirectXVersion
    public let antiCheat: AntiCheatStatus
    public let importedLibraries: Set<String>
    public let warnings: [String]

    public init(identity: GameIdentity, architecture: CPUArchitecture, directX: DirectXVersion, antiCheat: AntiCheatStatus, importedLibraries: Set<String>, warnings: [String] = []) {
        self.identity = identity
        self.architecture = architecture
        self.directX = directX
        self.antiCheat = antiCheat
        self.importedLibraries = importedLibraries
        self.warnings = warnings
    }
}

public enum GameSource: String, Codable, Sendable {
    case local
    case steam
}

public struct GameRecord: Codable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public var displayName: String
    public let source: GameSource
    public let executableURL: URL
    public var analysis: GameAnalysis
    public var bottleID: UUID?
    public let importedAt: Date

    public init(id: UUID = UUID(), displayName: String, source: GameSource, executableURL: URL, analysis: GameAnalysis, bottleID: UUID? = nil, importedAt: Date = Date()) {
        self.id = id
        self.displayName = displayName
        self.source = source
        self.executableURL = executableURL
        self.analysis = analysis
        self.bottleID = bottleID
        self.importedAt = importedAt
    }
}

public struct RendererProfile: Codable, Hashable, Sendable {
    public let renderer: RendererKind
    public let syncBackend: SyncBackend
    public let environment: [String: String]
    public let dllOverrides: [String: String]
    public let arguments: [String]
    public let highResolution: Bool
    public let metalHUD: Bool?

    public init(renderer: RendererKind, syncBackend: SyncBackend = .automatic, environment: [String: String] = [:], dllOverrides: [String: String] = [:], arguments: [String] = [], highResolution: Bool = true, metalHUD: Bool? = nil) {
        self.renderer = renderer
        self.syncBackend = syncBackend
        self.environment = environment
        self.dllOverrides = dllOverrides
        self.arguments = arguments
        self.highResolution = highResolution
        self.metalHUD = metalHUD
    }
}

public struct GameRecipe: Codable, Hashable, Sendable, Identifiable {
    public let schemaVersion: Int
    public let id: String
    public let name: String
    public let steamAppIDs: Set<UInt64>
    public let executableNames: Set<String>
    public let minimumRuntimeVersion: SemanticVersion?
    public let antiCheat: AntiCheatStatus
    public let profiles: [RendererProfile]
    public let knownIssues: [String]
    public let provenance: [URL]

    public init(schemaVersion: Int = 1, id: String, name: String, steamAppIDs: Set<UInt64> = [], executableNames: Set<String> = [], minimumRuntimeVersion: SemanticVersion? = nil, antiCheat: AntiCheatStatus = .unknown, profiles: [RendererProfile], knownIssues: [String] = [], provenance: [URL] = []) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.name = name
        self.steamAppIDs = steamAppIDs
        self.executableNames = Set(executableNames.map { $0.lowercased() })
        self.minimumRuntimeVersion = minimumRuntimeVersion
        self.antiCheat = antiCheat
        self.profiles = profiles
        self.knownIssues = knownIssues
        self.provenance = provenance
    }
}

public struct LaunchProfile: Codable, Hashable, Sendable {
    public let runtimeID: String
    public let preferredRenderer: RendererKind?
    public let syncBackend: SyncBackend
    public let arguments: [String]
    public let environment: [String: String]
    public let metalHUD: Bool

    public init(runtimeID: String, preferredRenderer: RendererKind? = nil, syncBackend: SyncBackend = .automatic, arguments: [String] = [], environment: [String: String] = [:], metalHUD: Bool = false) {
        self.runtimeID = runtimeID
        self.preferredRenderer = preferredRenderer
        self.syncBackend = syncBackend
        self.arguments = arguments
        self.environment = environment
        self.metalHUD = metalHUD
    }
}

public struct LaunchPlan: Codable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public let executable: URL
    public let windowsExecutablePath: String?
    public let bottle: BottleRecord
    public let runtimeID: String
    public let renderer: RendererKind
    public let arguments: [String]
    public let environment: [String: String]
    public let warnings: [String]
    public let generatedAt: Date

    public init(id: UUID = UUID(), executable: URL, windowsExecutablePath: String? = nil, bottle: BottleRecord, runtimeID: String, renderer: RendererKind, arguments: [String], environment: [String: String], warnings: [String] = [], generatedAt: Date = Date()) {
        self.id = id
        self.executable = executable
        self.windowsExecutablePath = windowsExecutablePath
        self.bottle = bottle
        self.runtimeID = runtimeID
        self.renderer = renderer
        self.arguments = arguments
        self.environment = environment
        self.warnings = warnings
        self.generatedAt = generatedAt
    }
}

public enum RunExit: Codable, Hashable, Sendable {
    case exited(Int32)
    case timedOut
    case cancelled
    case launchFailed(String)
}

public struct RunSession: Codable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public let planID: UUID
    public let startedAt: Date
    public let endedAt: Date
    public let result: RunExit
    public let logURL: URL

    public init(id: UUID = UUID(), planID: UUID, startedAt: Date, endedAt: Date, result: RunExit, logURL: URL) {
        self.id = id
        self.planID = planID
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.result = result
        self.logURL = logURL
    }
}
