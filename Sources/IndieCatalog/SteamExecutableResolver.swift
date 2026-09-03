import Foundation
import IndieCore

public enum SteamExecutableResolver {
    public static func shippingExecutable(for game: SteamGame, fileManager: FileManager = .default) throws -> URL {
        guard let enumerator = fileManager.enumerator(
            at: game.installDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { throw IndieError.notFound("无法读取 \(game.name) 的安装目录") }
        let matches = enumerator.compactMap { item -> URL? in
            guard let url = item as? URL else { return nil }
            return url.lastPathComponent.lowercased().hasSuffix("-win64-shipping.exe") ? url : nil
        }
        if let shipping = matches.min(by: { $0.path.count < $1.path.count }) { return shipping }
        return try preferredExecutable(for: game, fileManager: fileManager)
    }

    public static func preferredExecutable(for game: SteamGame, fileManager: FileManager = .default) throws -> URL {
        guard let enumerator = fileManager.enumerator(
            at: game.installDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { throw IndieError.notFound("无法读取 \(game.name) 的安装目录") }

        var candidates: [(url: URL, score: Int)] = []
        for case let url as URL in enumerator where url.pathExtension.lowercased() == "exe" {
            let relative = url.path.replacingOccurrences(of: game.installDirectory.path, with: "")
            let lower = relative.lowercased()
            if ["crashreport", "ue4prereq", "unins", "setup", "installer", "redist"].contains(where: lower.contains) {
                continue
            }
            let depth = relative.split(separator: "/").count
            let gameName = normalized(game.name)
            let executableName = normalized(url.deletingPathExtension().lastPathComponent)
            var score = 100 - depth * 10
            if executableName == gameName { score += 100 }
            if lower.contains("shipping") { score += 30 }
            if depth == 1 { score += 50 }
            candidates.append((url, score))
        }
        guard let result = candidates.max(by: { lhs, rhs in
            lhs.score == rhs.score ? lhs.url.path.count > rhs.url.path.count : lhs.score < rhs.score
        }) else { throw IndieError.notFound("未找到 \(game.name) 的 Windows 启动程序") }
        return result.url
    }

    private static func normalized(_ value: String) -> String {
        value.lowercased().unicodeScalars.filter(CharacterSet.alphanumerics.contains).map(String.init).joined()
    }
}
