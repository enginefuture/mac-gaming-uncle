import Foundation
import IndieCore

public enum WinePath {
    public static func windowsPath(for file: URL, in bottle: BottleRecord) throws -> String {
        let driveC = bottle.root.appendingPathComponent("drive_c", isDirectory: true).standardizedFileURL
        let candidate = file.standardizedFileURL
        let prefix = driveC.path.hasSuffix("/") ? driveC.path : driveC.path + "/"
        guard candidate.path.hasPrefix(prefix) else {
            throw IndieError.invalidArgument(L("文件不在 Bottle 的 C: 盘中"))
        }
        let relative = String(candidate.path.dropFirst(prefix.count))
        return "C:\\" + relative.replacingOccurrences(of: "/", with: "\\")
    }
}
