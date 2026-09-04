import Foundation

public enum GrimDawnCompatibility {
    public struct Result: Sendable, Equatable {
        public let changedFiles: [URL]
        public var changed: Bool { !changedFiles.isEmpty }
    }

    /// Grim Dawn 1.3 replaced its in-game HUD. The new HUD currently loses its
    /// 2D pass on some D3D translation paths while menus and the 3D scene keep
    /// rendering. Selecting the built-in classic HUD avoids that failure.
    ///
    /// The user's original file is retained once beside the settings file, so
    /// this compatibility change is transparent and reversible.
    public static func enableClassicHUD(
        bottleRoot: URL,
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
            let pattern = #"(?m)^standardHUD\s*=\s*false\s*$"#
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  regex.firstMatch(in: contents, range: NSRange(contents.startIndex..., in: contents)) != nil else {
                continue
            }
            let backup = options.deletingLastPathComponent()
                .appendingPathComponent("options.txt.indie-before-classic-hud")
            if !fileManager.fileExists(atPath: backup.path) {
                try fileManager.copyItem(at: options, to: backup)
            }
            contents = regex.stringByReplacingMatches(
                in: contents,
                range: NSRange(contents.startIndex..., in: contents),
                withTemplate: "standardHUD               = true"
            )
            try contents.write(to: options, atomically: true, encoding: .utf8)
            changed.append(options)
        }
        return Result(changedFiles: changed)
    }
}
