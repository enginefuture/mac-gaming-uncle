import Foundation
import IndieCore

public struct SteamCompatibilityResult: Codable, Sendable, Equatable {
    public let wrapperInstalled: Bool
    public let upstreamWebHelper: URL
    public let backupDirectory: URL?
}

public enum SteamCompatibilityManager {
    public static func bundledWrapperURL(bundle: Bundle = .main) -> URL? {
        let candidates = [
            bundle.resourceURL?.appendingPathComponent("RuntimeSupport/steamwebhelper-wrapper.exe"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent(".build/runtime-support/steamwebhelper-wrapper.exe"),
        ].compactMap { $0 }
        return candidates.first { FileManager.default.isReadableFile(atPath: $0.path) }
    }

    public static func launchArguments(
        appID: UInt64? = nil,
        gameArguments: [String] = [],
        launchOption: Int? = nil,
        silent: Bool = false
    ) -> [String] {
        var arguments = ["-noverifyfiles", "-no-cef-sandbox"]
        if silent { arguments.append("-silent") }
        if let appID {
            if launchOption != nil {
                // Steam's -applaunch always selects the first entry for games
                // with multiple play options. The launch-dialog contract reads
                // DefaultLaunchOption and automatically uses the saved choice.
                arguments.append("steam://launch/\(appID)/dialog")
            } else {
                arguments.append(contentsOf: ["-applaunch", String(appID)])
                arguments.append(contentsOf: gameArguments)
            }
        }
        return arguments
    }

    /// Updates an existing per-machine Steam play-option selection. Steam
    /// creates the opaque machine key after the launch dialog is shown once;
    /// Mac Gaming Uncle preserves that key and changes only its numeric value.
    @discardableResult
    public static func setDefaultLaunchOption(
        appID: UInt64,
        option: Int,
        in bottle: BottleRecord,
        fileManager: FileManager = .default
    ) throws -> Bool {
        guard option >= 0 else { throw IndieError.invalidArgument(L("Steam 启动项不能为负数")) }
        let userdata = steamRoot(in: bottle).appendingPathComponent("userdata", isDirectory: true)
        let users = (try? fileManager.contentsOfDirectory(
            at: userdata, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
        )) ?? []
        let escapedAppID = NSRegularExpression.escapedPattern(for: String(appID))
        let pattern = "\\\"\(escapedAppID)\\\"\\s*\\{\\s*\\\"DefaultLaunchOption\\\"\\s*\\{\\s*\\\"[^\\\"]+\\\"\\s*\\\"(\\d+)\\\""
        let regex = try NSRegularExpression(pattern: pattern)
        var changed = false
        for user in users {
            let config = user.appendingPathComponent("config/localconfig.vdf")
            guard fileManager.fileExists(atPath: config.path),
                  let original = try? String(contentsOf: config, encoding: .utf8) else { continue }
            let range = NSRange(original.startIndex..., in: original)
            guard let match = regex.firstMatch(in: original, range: range),
                  let valueRange = Range(match.range(at: 1), in: original) else { continue }
            var updated = original
            updated.replaceSubrange(valueRange, with: String(option))
            guard updated != original else { continue }
            let backup = bottle.root
                .appendingPathComponent(".indie-backups/steam-launch-options", isDirectory: true)
                .appendingPathComponent("\(user.lastPathComponent)-localconfig.vdf")
            try fileManager.createDirectory(at: backup.deletingLastPathComponent(), withIntermediateDirectories: true)
            if !fileManager.fileExists(atPath: backup.path) {
                try fileManager.copyItem(at: config, to: backup)
            }
            try updated.write(to: config, atomically: true, encoding: .utf8)
            changed = true
        }
        return changed
    }

    /// Steam must create recent game processes itself so SteamAPI and launch
    /// contracts are initialized correctly. Relay the selected renderer and
    /// Metal HUD to Steam; its child game then inherits the exact launch plan.
    public static func relayEnvironment(for gameEnvironment: [String: String]) -> [String: String] {
        var environment = gameEnvironment
        // A reused Steam client launches more than one AppID. Steam injects
        // these values into each child itself; pinning either on the client
        // would make later games inherit the first launch's identity.
        environment.removeValue(forKey: "SteamAppId")
        environment.removeValue(forKey: "SteamGameId")
        environment["WINE_WAIT_CHILD_PIPE_IGNORE"] = "steam.exe"
        let compatibility = "mscoree,mshtml=;winedbg.exe=d"
        if let overrides = environment["WINEDLLOVERRIDES"], !overrides.isEmpty {
            environment["WINEDLLOVERRIDES"] = overrides + ";" + compatibility
        } else {
            environment["WINEDLLOVERRIDES"] = compatibility
        }
        return environment
    }

    public static func isLoggedOn(in bottle: BottleRecord, since: Date? = nil) -> Bool {
        let log = steamRoot(in: bottle).appendingPathComponent("logs/connection_log.txt")
        if let since,
           let modified = try? log.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
           modified < since.addingTimeInterval(-2) { return false }
        guard let data = try? Data(contentsOf: log),
              let text = String(data: data.suffix(1_000_000), encoding: .utf8) else { return false }
        let loggedOn = text.range(of: "[Logged On", options: .backwards)?.lowerBound
        let loggedOff = text.range(of: "[Logged Off", options: .backwards)?.lowerBound
        guard let loggedOn else { return false }
        guard let loggedOff else { return true }
        return loggedOn > loggedOff
    }

    public static func prepare(
        bottle: BottleRecord,
        wrapper: URL,
        fileManager: FileManager = .default
    ) throws -> SteamCompatibilityResult {
        guard fileManager.isReadableFile(atPath: wrapper.path) else {
            throw IndieError.notFound(L("Mac Gaming Uncle 缺少 Steam 界面兼容组件，请重新构建应用"))
        }
        let steam = steamRoot(in: bottle)
        let cef = steam.appendingPathComponent("bin/cef/cef.win64", isDirectory: true)
        let webHelper = cef.appendingPathComponent("steamwebhelper.exe")
        let realWebHelper = cef.appendingPathComponent("steamwebhelper_real.exe")
        guard fileManager.fileExists(atPath: webHelper.path) else {
            throw IndieError.notFound(L("Steam 安装不完整：找不到 steamwebhelper.exe"))
        }

        let wrapperHash = try ManifestSecurity.sha256(of: wrapper)
        let currentHash = try ManifestSecurity.sha256(of: webHelper)
        let currentIsWrapper = try isIndieWrapper(webHelper)
        let realIsUsable: Bool
        if fileManager.fileExists(atPath: realWebHelper.path) {
            realIsUsable = try !isIndieWrapper(realWebHelper)
        } else {
            realIsUsable = false
        }
        if currentHash == wrapperHash, currentIsWrapper, realIsUsable {
            return SteamCompatibilityResult(wrapperInstalled: false, upstreamWebHelper: realWebHelper, backupDirectory: nil)
        }

        let backup = bottle.root
            .appendingPathComponent(".indie-backups/steam-webhelper", isDirectory: true)
            .appendingPathComponent(backupName(), isDirectory: true)
        try fileManager.createDirectory(at: backup, withIntermediateDirectories: true)
        try fileManager.copyItem(at: webHelper, to: backup.appendingPathComponent("steamwebhelper-upstream.exe"))
        if fileManager.fileExists(atPath: realWebHelper.path) {
            try fileManager.copyItem(at: realWebHelper, to: backup.appendingPathComponent("steamwebhelper-real-previous.exe"))
        }

        let realCandidate = cef.appendingPathComponent(".steamwebhelper-real-\(UUID().uuidString).exe")
        let wrapperCandidate = cef.appendingPathComponent(".steamwebhelper-wrapper-\(UUID().uuidString).exe")
        do {
            if currentIsWrapper {
                if !realIsUsable {
                    guard let recovery = try recoverableUpstream(in: bottle, fileManager: fileManager) else {
                        throw IndieError.invalidData(L("Steam 原始 WebHelper 被包装器覆盖，且没有可恢复备份；请重新安装 Steam"))
                    }
                    try fileManager.copyItem(at: recovery, to: realCandidate)
                }
            } else {
                try fileManager.copyItem(at: webHelper, to: realCandidate)
            }
            try fileManager.copyItem(at: wrapper, to: wrapperCandidate)
            if fileManager.fileExists(atPath: realCandidate.path) {
                if fileManager.fileExists(atPath: realWebHelper.path) {
                    _ = try fileManager.replaceItemAt(realWebHelper, withItemAt: realCandidate)
                } else {
                    try fileManager.moveItem(at: realCandidate, to: realWebHelper)
                }
            }
            _ = try fileManager.replaceItemAt(webHelper, withItemAt: wrapperCandidate)
            try backupGPUCaches(bottle: bottle, into: backup, fileManager: fileManager)
        } catch {
            try? fileManager.removeItem(at: realCandidate)
            try? fileManager.removeItem(at: wrapperCandidate)
            throw error
        }

        guard try ManifestSecurity.sha256(of: webHelper) == wrapperHash else {
            throw IndieError.securityViolation(L("Steam 界面包装器安装后校验失败"))
        }
        return SteamCompatibilityResult(wrapperInstalled: true, upstreamWebHelper: realWebHelper, backupDirectory: backup)
    }

    public static func steamRoot(in bottle: BottleRecord) -> URL {
        bottle.root.appendingPathComponent("drive_c/Program Files (x86)/Steam", isDirectory: true)
    }

    private static func backupGPUCaches(bottle: BottleRecord, into backup: URL, fileManager: FileManager) throws {
        let cache = bottle.root.appendingPathComponent("drive_c/users", isDirectory: true)
        guard let users = try? fileManager.contentsOfDirectory(at: cache, includingPropertiesForKeys: nil) else { return }
        for user in users where user.lastPathComponent != "Public" {
            let html = user.appendingPathComponent("AppData/Local/Steam/htmlcache", isDirectory: true)
            let entries: [(String, String)] = [
                ("GrShaderCache", "GrShaderCache"),
                ("ShaderCache", "ShaderCache"),
                ("GraphiteDawnCache", "GraphiteDawnCache"),
                ("Default/GPUCache", "Default-GPUCache"),
                ("Default/DawnGraphiteCache", "Default-DawnGraphiteCache"),
                ("Default/DawnWebGPUCache", "Default-DawnWebGPUCache"),
            ]
            for (relative, backupName) in entries {
                let source = html.appendingPathComponent(relative, isDirectory: true)
                guard fileManager.fileExists(atPath: source.path) else { continue }
                try fileManager.moveItem(at: source, to: backup.appendingPathComponent("\(user.lastPathComponent)-\(backupName)", isDirectory: true))
            }
        }
    }

    private static func isIndieWrapper(_ file: URL) throws -> Bool {
        let data = try Data(contentsOf: file, options: .mappedIfSafe)
        if data.range(of: Data("INDIE_STEAM_WEBHELPER_WRAPPER_V1".utf8)) != nil { return true }
        let realName = "steamwebhelper_real.exe".data(using: .utf16LittleEndian)!
        let singleProcess = "--single-process".data(using: .utf16LittleEndian)!
        return data.range(of: realName) != nil && data.range(of: singleProcess) != nil
    }

    private static func recoverableUpstream(in bottle: BottleRecord, fileManager: FileManager) throws -> URL? {
        let backups = bottle.root.appendingPathComponent(".indie-backups/steam-webhelper", isDirectory: true)
        guard let enumerator = fileManager.enumerator(
            at: backups,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }
        var candidates: [(URL, Date)] = []
        for case let file as URL in enumerator where file.pathExtension.lowercased() == "exe" {
            let values = try file.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey])
            guard values.isRegularFile == true, (values.fileSize ?? 0) > 1_000_000,
                  !(try isIndieWrapper(file)) else { continue }
            candidates.append((file, values.contentModificationDate ?? .distantPast))
        }
        return candidates.max { $0.1 < $1.1 }?.0
    }

    private static func backupName() -> String {
        let formatter = ISO8601DateFormatter()
        return formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-") + "-" + UUID().uuidString.prefix(8)
    }
}
