import Foundation
import IndieCore

public struct SteamAccountGame: Identifiable, Sendable, Equatable {
    public var id: UInt64 { appID }
    public let appID: UInt64
    public var name: String
    public let playtimeMinutes: Int
    public let lastPlayed: Date?
    public let isInstalled: Bool
    public let localArtworkDirectory: URL?
    public var headerImageURL: URL?
    public var description: String?

    public init(
        appID: UInt64,
        name: String,
        playtimeMinutes: Int = 0,
        lastPlayed: Date? = nil,
        isInstalled: Bool = false,
        localArtworkDirectory: URL? = nil,
        headerImageURL: URL? = nil,
        description: String? = nil
    ) {
        self.appID = appID
        self.name = name
        self.playtimeMinutes = playtimeMinutes
        self.lastPlayed = lastPlayed
        self.isInstalled = isInstalled
        self.localArtworkDirectory = localArtworkDirectory
        self.headerImageURL = headerImageURL
        self.description = description
    }

    public var coverImageURL: URL? {
        if let local = localArtworkDirectory?.appendingPathComponent("library_600x900.jpg"),
           FileManager.default.fileExists(atPath: local.path) { return local }
        return URL(string: "https://cdn.akamai.steamstatic.com/steam/apps/\(appID)/library_600x900.jpg")
    }

    public var heroImageURL: URL? {
        if let local = localArtworkDirectory?.appendingPathComponent("library_hero.jpg"),
           FileManager.default.fileExists(atPath: local.path) { return local }
        return URL(string: "https://cdn.akamai.steamstatic.com/steam/apps/\(appID)/library_hero.jpg")
    }

    public var pageBackgroundURL: URL? {
        URL(string: "https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/\(appID)/page_bg_raw.jpg")
    }
}

public struct SteamAchievement: Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let imageURL: URL?
    public let unlockedAt: Date?
}

public struct SteamGameActivity: Sendable, Equatable {
    public let achieved: Int
    public let total: Int
    public let recentAchievements: [SteamAchievement]

    public var progress: Double { total > 0 ? Double(achieved) / Double(total) : 0 }
}

public enum SteamActivityScanner {
    public static func scan(steamRoot: URL) -> [UInt64: SteamGameActivity] {
        let userdata = steamRoot.appendingPathComponent("userdata", isDirectory: true)
        let users = (try? FileManager.default.contentsOfDirectory(
            at: userdata, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        )) ?? []
        var result: [UInt64: SteamGameActivity] = [:]
        for user in users {
            let cache = user.appendingPathComponent("config/librarycache", isDirectory: true)
            let files = (try? FileManager.default.contentsOfDirectory(
                at: cache, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
            )) ?? []
            for file in files where file.pathExtension == "json" {
                guard let appID = UInt64(file.deletingPathExtension().lastPathComponent),
                      let data = try? Data(contentsOf: file),
                      let root = try? JSONSerialization.jsonObject(with: data) as? [[Any]] else { continue }
                for entry in root where entry.count == 2 && entry[0] as? String == "achievements" {
                    guard let container = entry[1] as? [String: Any],
                          let values = container["data"] as? [String: Any] else { continue }
                    let achieved = (values["nAchieved"] as? NSNumber)?.intValue ?? 0
                    let total = (values["nTotal"] as? NSNumber)?.intValue ?? 0
                    let highlights = (values["vecHighlight"] as? [[String: Any]] ?? []).prefix(6).map { item in
                        let identifier = item["strID"] as? String ?? UUID().uuidString
                        let timestamp = (item["rtUnlocked"] as? NSNumber)?.doubleValue ?? 0
                        return SteamAchievement(
                            id: identifier,
                            name: item["strName"] as? String ?? L("Steam 成就"),
                            imageURL: (item["strImage"] as? String).flatMap(URL.init(string:)),
                            unlockedAt: timestamp > 0 ? Date(timeIntervalSince1970: timestamp) : nil
                        )
                    }
                    result[appID] = SteamGameActivity(
                        achieved: achieved, total: total, recentAchievements: highlights
                    )
                    break
                }
            }
        }
        return result
    }
}

public enum SteamAccountLibraryScanner {
    public static func scan(steamRoot: URL, installed: [SteamGame]) throws -> [SteamAccountGame] {
        let installedByID = Dictionary(uniqueKeysWithValues: installed.map { ($0.appID, $0) })
        let artworkRoot = steamRoot.appendingPathComponent("appcache/librarycache", isDirectory: true)
        let userdata = steamRoot.appendingPathComponent("userdata", isDirectory: true)
        let users = (try? FileManager.default.contentsOfDirectory(
            at: userdata, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
        )) ?? []
        var entries: [UInt64: SteamAccountGame] = [:]
        for user in users {
            let config = user.appendingPathComponent("config/localconfig.vdf")
            guard FileManager.default.fileExists(atPath: config.path),
                  let root = try? VDFParser.parse(url: config),
                  let apps = object(at: ["UserLocalConfigStore", "Software", "Valve", "Steam", "apps"], in: root) else {
                continue
            }
            for (key, value) in apps {
                guard let appID = UInt64(key), appID > 0, let fields = value.object else { continue }
                let installedGame = installedByID[appID]
                let playtime = intValue("Playtime", in: fields) ?? 0
                let lastPlayedSeconds = intValue("LastPlayed", in: fields) ?? 0
                let hasLibraryCache = FileManager.default.fileExists(
                    atPath: user.appendingPathComponent("config/librarycache/\(appID).json").path
                )
                guard installedGame != nil || playtime > 0 || lastPlayedSeconds > 0 || hasLibraryCache else { continue }
                // Steam client components are not user-launchable games.
                guard ![7, 760, 228980].contains(appID) else { continue }
                let lastPlayed = lastPlayedSeconds > 0
                    ? Date(timeIntervalSince1970: TimeInterval(lastPlayedSeconds)) : nil
                let candidate = SteamAccountGame(
                    appID: appID,
                    name: installedGame?.name ?? L("Steam 游戏 \(appID)"),
                    playtimeMinutes: playtime,
                    lastPlayed: lastPlayed,
                    isInstalled: installedGame != nil,
                    localArtworkDirectory: artworkRoot.appendingPathComponent(String(appID), isDirectory: true),
                    headerImageURL: localArtworkURL(appID: appID, name: "header.jpg", root: artworkRoot)
                        ?? URL(string: "https://cdn.akamai.steamstatic.com/steam/apps/\(appID)/header.jpg")
                )
                if let existing = entries[appID], existing.playtimeMinutes > candidate.playtimeMinutes { continue }
                entries[appID] = candidate
            }
        }
        for game in installed where ![228980].contains(game.appID) && entries[game.appID] == nil {
            entries[game.appID] = SteamAccountGame(
                appID: game.appID,
                name: game.name,
                isInstalled: true,
                localArtworkDirectory: artworkRoot.appendingPathComponent(String(game.appID), isDirectory: true),
                headerImageURL: localArtworkURL(appID: game.appID, name: "header.jpg", root: artworkRoot)
                    ?? URL(string: "https://cdn.akamai.steamstatic.com/steam/apps/\(game.appID)/header.jpg")
            )
        }
        return entries.values.sorted {
            if $0.isInstalled != $1.isInstalled { return $0.isInstalled }
            if $0.lastPlayed != $1.lastPlayed { return ($0.lastPlayed ?? .distantPast) > ($1.lastPlayed ?? .distantPast) }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private static func object(at path: [String], in root: [String: VDFValue]) -> [String: VDFValue]? {
        var current = root
        for key in path {
            guard let next = current.first(where: { $0.key.caseInsensitiveCompare(key) == .orderedSame })?.value.object else {
                return nil
            }
            current = next
        }
        return current
    }

    private static func intValue(_ key: String, in object: [String: VDFValue]) -> Int? {
        object.first(where: { $0.key.caseInsensitiveCompare(key) == .orderedSame })?.value.string.flatMap(Int.init)
    }

    private static func localArtworkURL(appID: UInt64, name: String, root: URL) -> URL? {
        let url = root.appendingPathComponent(String(appID), isDirectory: true).appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}

public enum SteamStoreMetadataService {
    public struct Metadata: Codable, Sendable, Equatable {
        public let name: String
        public let headerImageURL: URL?
        public let description: String?
    }

    public static func fetch(appID: UInt64, session: URLSession = .shared) async -> Metadata? {
        var components = URLComponents(string: "https://store.steampowered.com/api/appdetails")!
        components.queryItems = [
            .init(name: "appids", value: String(appID)),
            .init(name: "l", value: AppLanguage.steamLanguage),
            .init(name: "cc", value: "cn"),
        ]
        guard let url = components.url,
              let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let envelope = try? IndieJSON.decoder().decode([String: StoreEnvelope].self, from: data),
              let result = envelope[String(appID)], result.success, let details = result.data,
              details.type == "game" else { return nil }
        return Metadata(
            name: details.name,
            headerImageURL: details.headerImage.flatMap(URL.init(string:)),
            description: details.shortDescription
        )
    }

    private struct StoreEnvelope: Decodable {
        let success: Bool
        let data: StoreDetails?
    }

    private struct StoreDetails: Decodable {
        let type: String
        let name: String
        let headerImage: String?
        let shortDescription: String?

        enum CodingKeys: String, CodingKey {
            case type, name
            case headerImage = "header_image"
            case shortDescription = "short_description"
        }
    }
}

public enum SteamStoreMetadataCache {
    public static func load(from url: URL) -> [UInt64: SteamStoreMetadataService.Metadata] {
        guard let data = try? Data(contentsOf: url),
              let cached = try? IndieJSON.decoder().decode([UInt64: SteamStoreMetadataService.Metadata].self, from: data) else {
            return [:]
        }
        return cached
    }

    public static func save(_ metadata: [UInt64: SteamStoreMetadataService.Metadata], to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try IndieJSON.encoder().encode(metadata).write(to: url, options: .atomic)
    }
}
