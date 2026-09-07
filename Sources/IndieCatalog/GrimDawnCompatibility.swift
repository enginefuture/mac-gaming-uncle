import IndieCore
import Foundation

public enum GrimDawnCompatibility {
    public struct Result: Sendable, Equatable {
        public let changedFiles: [URL]
        public var changed: Bool { !changedFiles.isEmpty }
    }

    /// Under Grim Dawn's Retina-disabled policy, Wine uses logical points,
    /// not Retina backing pixels. Keeping Grim Dawn's render size identical to
    /// that logical surface prevents the image from being stretched while the
    /// hit-test grid remains at the old resolution.
    public static func logicalDisplayResolution(width: Double?, height: Double?) -> String {
        guard let width, let height,
              width.isFinite, height.isFinite,
              width >= 640, height >= 480 else { return "1280 720" }
        return "\(evenPixels(width)) \(evenPixels(height))"
    }

    /// Enables native gamepad input, selects the classic HUD and uses a
    /// display-matched fullscreen swap chain (screenMode=0). Grim
    /// Dawn otherwise rebuilds a 2560x1440 exclusive/borderless surface on a
    /// much smaller logical Mac display when a character starts, which can
    /// detach both the game UI and Metal HUD layers under Wine.
    ///
    /// The user's original file is retained once beside the settings file, so
    /// this compatibility change is transparent and reversible.
    public static func prepare(
        bottleRoot: URL,
        safeResolution: String = "1280 720",
        fileManager: FileManager = .default
    ) throws -> Result {
        let users = bottleRoot.appendingPathComponent("drive_c/users", isDirectory: true)
        let profiles = (try? fileManager.contentsOfDirectory(
            at: users,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        var visited = Set<String>()
        var changed: [URL] = []
        for profile in profiles {
            let options = profile
                .appendingPathComponent("Documents/My Games/Grim Dawn/Settings/options.txt")
                .resolvingSymlinksInPath()
                .standardizedFileURL
            guard visited.insert(options.path).inserted,
                  fileManager.fileExists(atPath: options.path),
                  var contents = try? String(contentsOf: options, encoding: .utf8) else { continue }
            let desired = [
                (key: "gamepadSupport", value: "true"),
                (key: "standardHUD", value: "true"),
                (key: "screenMode", value: "0"),
                (key: "resolution", value: safeResolution),
                (key: "syncToRefresh", value: "false"),
            ]
            let valuesByKey = Dictionary(uniqueKeysWithValues: desired.map { ($0.key, $0.value) })
            let newline = contents.contains("\r\n") ? "\r\n" : "\n"
            let lines = contents.replacingOccurrences(of: "\r\n", with: "\n")
                .replacingOccurrences(of: "\r", with: "\n")
                .components(separatedBy: "\n")
            var output: [String] = []
            var found = Set<String>()
            for line in lines {
                guard let equals = line.firstIndex(of: "=") else { output.append(line); continue }
                let key = line[..<equals].trimmingCharacters(in: .whitespaces)
                guard let value = valuesByKey[key] else { output.append(line); continue }
                // Remove legacy duplicates instead of leaving first/last-wins
                // interpretation to the game. Unrelated options are preserved.
                guard found.insert(key).inserted else { continue }
                let replacement = key.padding(toLength: 27, withPad: " ", startingAt: 0) + "= \(value)"
                output.append(replacement)
            }
            for setting in desired where !found.contains(setting.key) {
                output.append(setting.key.padding(toLength: 27, withPad: " ", startingAt: 0) + "= \(setting.value)")
            }
            let updated = output.joined(separator: newline)
            guard updated != contents else { continue }
            let repairBackup = options.appendingPathExtension("indie-before-display-repair")
            if !fileManager.fileExists(atPath: repairBackup.path) {
                try fileManager.copyItem(at: options, to: repairBackup)
            }
            let backup = options.deletingLastPathComponent()
                .appendingPathComponent("options.txt.indie-before-classic-hud")
            if !fileManager.fileExists(atPath: backup.path) {
                try fileManager.copyItem(at: options, to: backup)
            }
            contents = updated
            try contents.write(to: options, atomically: true, encoding: .utf8)
            changed.append(options)
        }
        return Result(changedFiles: changed)
    }

    private static func evenPixels(_ value: Double) -> Int {
        let pixels = Int(value.rounded())
        return pixels.isMultiple(of: 2) ? pixels : pixels - 1
    }
}
