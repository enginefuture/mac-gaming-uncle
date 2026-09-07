import Foundation
import IndieCore

public struct SteamGame: Codable, Identifiable, Sendable, Equatable {
    public var id: UInt64 { appID }
    public let appID: UInt64
    public let name: String
    public let installDirectory: URL
    public let buildID: String?
    public let manifestURL: URL
    public let stateFlags: UInt64?
    public let bytesToDownload: UInt64?
    public let bytesDownloaded: UInt64?
    public let bytesToStage: UInt64?
    public let bytesStaged: UInt64?

    public init(appID: UInt64, name: String, installDirectory: URL, buildID: String?, manifestURL: URL,
                stateFlags: UInt64? = nil, bytesToDownload: UInt64? = nil, bytesDownloaded: UInt64? = nil,
                bytesToStage: UInt64? = nil, bytesStaged: UInt64? = nil) {
        self.appID = appID; self.name = name; self.installDirectory = installDirectory
        self.buildID = buildID; self.manifestURL = manifestURL; self.stateFlags = stateFlags
        self.bytesToDownload = bytesToDownload; self.bytesDownloaded = bytesDownloaded
        self.bytesToStage = bytesToStage; self.bytesStaged = bytesStaged
    }

    /// A manifest exists as soon as installation is requested. Only accept
    /// Steam's completed state, a committed build, and completed byte counters.
    /// Unknown or combined flags fail closed until Steam commits its state.
    public var isReadyToPlay: Bool {
        guard stateFlags == 4, let buildID, let build = UInt64(buildID), build > 0,
              !downloadIncomplete, !stagingIncomplete else { return false }
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: installDirectory.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
    public var downloadIncomplete: Bool { (bytesToDownload ?? 0) > (bytesDownloaded ?? 0) }
    public var stagingIncomplete: Bool { (bytesToStage ?? 0) > (bytesStaged ?? 0) }
    public var downloadProgress: Double? {
        guard let total = bytesToDownload, total > 0 else { return nil }
        return min(1, Double(bytesDownloaded ?? 0) / Double(total))
    }
    public var installationLabel: String {
        if isReadyToPlay { return L("已安装") }
        if downloadIncomplete { return L("下载未完成") }
        if stagingIncomplete { return L("正在安装文件") }
        return L("等待 Steam 完成安装或校验")
    }
}

public enum SteamScanner {
    public static func refreshed(_ game: SteamGame) throws -> SteamGame {
        try parseManifest(game.manifestURL, steamApps: game.manifestURL.deletingLastPathComponent())
    }
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
            manifestURL: url,
            stateFlags: value(caseInsensitive: "StateFlags", in: appState)?.string.flatMap(UInt64.init),
            bytesToDownload: value(caseInsensitive: "BytesToDownload", in: appState)?.string.flatMap(UInt64.init),
            bytesDownloaded: value(caseInsensitive: "BytesDownloaded", in: appState)?.string.flatMap(UInt64.init),
            bytesToStage: value(caseInsensitive: "BytesToStage", in: appState)?.string.flatMap(UInt64.init),
            bytesStaged: value(caseInsensitive: "BytesStaged", in: appState)?.string.flatMap(UInt64.init)
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
