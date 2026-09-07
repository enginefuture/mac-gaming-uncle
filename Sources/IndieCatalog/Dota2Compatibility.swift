import Foundation
import IndieCore

/// Game-owned desktop fullscreen: avoids an exclusive macOS display mode switch.
/// Does not alter bottle DPI, audio, renderer DLLs, or system display settings.
public enum Dota2Compatibility {
    public static func prepare(steamRoot: URL) throws -> Bool {
        let login = steamRoot.appendingPathComponent("config/loginusers.vdf")
        guard FileManager.default.fileExists(atPath: login.path) else { return false }
        let users = try VDFParser.parse(url: login)["users"]?.object ?? [:]
        let marked = users.filter { $0.value.object?["MostRecent"]?.string == "1" }
        // Recent Steam builds may omit MostRecent for a single saved account.
        // Never guess among multiple accounts when the marker is absent.
        let current = marked.isEmpty && users.count == 1 ? users : marked
        guard current.count == 1, let key = current.first?.key,
              let steamID = UInt64(key), steamID > 76561197960265728 else { return false }
        let accountID = steamID & 0xffffffff
        let video = steamRoot.appendingPathComponent("userdata/\(accountID)/570/local/cfg/video.txt")
        guard FileManager.default.fileExists(atPath: video.path) else { return false }
        let data = try Data(contentsOf: video)
        let replacement = try desktopFullscreenConfiguration(data)
        guard replacement != data else { return false }
        let backup = video.appendingPathExtension("indie-before-desktop-fullscreen")
        if !FileManager.default.fileExists(atPath: backup.path) {
            try FileManager.default.copyItem(at: video, to: backup)
        }
        try replacement.write(to: video, options: .atomic)
        return true
    }

    public static func desktopFullscreenConfiguration(_ data: Data) throws -> Data {
        guard data.count <= 1_048_576,
              var text = String(data: data, encoding: .utf8),
              try VDFParser.parse(data: data)["video.cfg"]?.object != nil else {
            throw IndieError.invalidData("Invalid Dota 2 video configuration")
        }
        let settings = [
            "setting.defaultres": "1920", "setting.defaultresheight": "1080",
            "setting.fullscreen": "1", "setting.coop_fullscreen": "1",
            "setting.nowindowborder": "1", "setting.fullscreen_min_on_focus_loss": "0",
            "setting.mat_vsync": "0", "setting.mat_viewportscale": "1.000000",
        ]
        let newline = text.contains("\r\n") ? "\r\n" : "\n"
        for key in settings.keys.sorted() {
            let value = settings[key]!
            let regex = try NSRegularExpression(
                pattern: #"(?m)^([\t ]*""# + NSRegularExpression.escapedPattern(for: key) + #""[\t ]*")[^"]*(")"#)
            let range = NSRange(text.startIndex..., in: text)
            let matches = regex.matches(in: text, range: range)
            guard matches.count <= 1 else { throw IndieError.invalidData("Duplicate Dota 2 video setting") }
            if let match = matches.first, let target = Range(match.range, in: text) {
                let prefix = String(text[Range(match.range(at: 1), in: text)!])
                text.replaceSubrange(target, with: prefix + value + "\"")
            } else {
                guard let end = text.lastIndex(of: "}") else { throw IndieError.invalidData("Invalid Dota 2 video configuration") }
                text.insert(contentsOf: "\t\"\(key)\"\t\t\"\(value)\"\(newline)", at: end)
            }
        }
        _ = try VDFParser.parse(data: Data(text.utf8))
        return Data(text.utf8)
    }
}
