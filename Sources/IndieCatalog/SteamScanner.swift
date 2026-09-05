import Foundation
import IndieCore

public struct SteamGame: Codable, Identifiable, Sendable, Equatable {
    public var id: UInt64 { appID }
    public let appID: UInt64
    public let name: String
    public let installDirectory: URL
    public let buildID: String?
    public let manifestURL: URL
}

public enum SteamScanner {
    public static func scan(steamApps root: URL) throws -> [SteamGame] {
        var libraries: Set<URL> = [root.standardizedFileURL]
        let foldersURL = root.appendingPathComponent("libraryfolders.vdf")
        if FileManager.default.fileExists(atPath: foldersURL.path),
           let libraryFolders = try? VDFParser.parse(url: foldersURL),
           let rootNode = value(caseInsensitive: "libraryfolders", in: libraryFolders)?.object {
            for (_, entry) in rootNode {
                guard let path = entry.object.flatMap({ value(caseInsensitive: "path", in: $0)?.string }) else { continue }
                if let resolved = resolveLibraryPath(path, relativeTo: root) {
                    libraries.insert(resolved.appendingPathComponent("steamapps", isDirectory: true).standardizedFileURL)
                }
            }
        }

        var games: [UInt64: SteamGame] = [:]
        for library in libraries {
            let manifests = (try? FileManager.default.contentsOfDirectory(at: library, includingPropertiesForKeys: nil)) ?? []
            for manifest in manifests where manifest.lastPathComponent.hasPrefix("appmanifest_") && manifest.pathExtension == "acf" {
                guard let game = try? parseManifest(manifest, steamApps: library) else { continue }
                games[game.appID] = game
            }
        }
        return games.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private static func parseManifest(_ url: URL, steamApps: URL) throws -> SteamGame {
        let parsed = try VDFParser.parse(url: url)
        guard let appState = value(caseInsensitive: "appstate", in: parsed)?.object,
              let idText = value(caseInsensitive: "appid", in: appState)?.string,
              let appID = UInt64(idText),
              let name = value(caseInsensitive: "name", in: appState)?.string,
              let installDir = value(caseInsensitive: "installdir", in: appState)?.string else {
            throw IndieError.invalidData(L("Steam AppManifest 缺少必填字段：\(url.lastPathComponent)"))
        }
        return SteamGame(
            appID: appID,
            name: name,
            installDirectory: steamApps.appendingPathComponent("common", isDirectory: true).appendingPathComponent(installDir, isDirectory: true),
            buildID: value(caseInsensitive: "buildid", in: appState)?.string,
            manifestURL: url
        )
    }

    private static func value(caseInsensitive key: String, in object: [String: VDFValue]) -> VDFValue? {
        object.first { $0.key.caseInsensitiveCompare(key) == .orderedSame }?.value
    }

    private static func resolveLibraryPath(_ value: String, relativeTo currentSteamApps: URL) -> URL? {
        let normalized = value.replacingOccurrences(of: "\\\\", with: "\\")
        guard normalized.count >= 3,
              normalized[normalized.index(after: normalized.startIndex)] == ":" else {
            return URL(fileURLWithPath: normalized, isDirectory: true)
        }
        let drive = String(normalized.prefix(1)).lowercased()
        let components = normalized.dropFirst(2).split(separator: "\\").map(String.init)
        let pathComponents = currentSteamApps.standardizedFileURL.pathComponents
        guard let driveCIndex = pathComponents.lastIndex(of: "drive_c") else { return nil }
        let prefixPath = NSString.path(withComponents: Array(pathComponents.prefix(driveCIndex)))
        let prefix = URL(fileURLWithPath: prefixPath, isDirectory: true)
        let base: URL
        if drive == "c" {
            base = prefix.appendingPathComponent("drive_c", isDirectory: true)
        } else {
            let link = prefix.appendingPathComponent("dosdevices/\(drive):")
            base = link.resolvingSymlinksInPath()
        }
        return components.reduce(base) { $0.appendingPathComponent($1, isDirectory: true) }
    }
}
