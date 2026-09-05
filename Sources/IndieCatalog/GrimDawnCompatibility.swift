import Foundation

public enum GrimDawnCompatibility {
    public struct Result: Sendable, Equatable {
        public let changedFiles: [URL]
        public var changed: Bool { !changedFiles.isEmpty }
    }

    /// Wine reports and receives pointer coordinates in macOS logical points,
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
    /// conservative windowed swap chain. Grim
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
            var lines = contents.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            var found = Set<String>()
            var modified = false
            for index in lines.indices {
                guard let equals = lines[index].firstIndex(of: "=") else { continue }
                let key = lines[index][..<equals].trimmingCharacters(in: .whitespaces)
                guard let value = valuesByKey[key] else { continue }
                found.insert(key)
                let replacement = key.padding(toLength: 27, withPad: " ", startingAt: 0) + "= \(value)"
                if lines[index] != replacement {
                    lines[index] = replacement
                    modified = true
                }
            }
            for setting in desired where !found.contains(setting.key) {
                lines.append(setting.key.padding(toLength: 27, withPad: " ", startingAt: 0) + "= \(setting.value)")
                modified = true
            }
            guard modified else { continue }
            let backup = options.deletingLastPathComponent()
                .appendingPathComponent("options.txt.indie-before-classic-hud")
            if !fileManager.fileExists(atPath: backup.path) {
                try fileManager.copyItem(at: options, to: backup)
            }
            contents = lines.joined(separator: "\n")
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
