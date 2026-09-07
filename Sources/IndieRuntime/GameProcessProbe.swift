import Foundation

public enum GameProcessProbe {
    public struct Process: Sendable, Equatable {
        public let pid: Int32
        public let started: String
        public let command: String
        public var identity: String { "\(pid):\(started)" }
    }

    public static func processes() async throws -> [Process] {
        let result = try await Subprocess().run(URL(fileURLWithPath: "/bin/ps"),
            arguments: ["-axo", "pid=,lstart=,command="], timeout: .seconds(5))
        return parseProcesses(result.stdout)
    }

    public static func parseProcesses(_ text: String) -> [Process] {
        text.split(whereSeparator: \.isNewline).compactMap { line in
            let fields = line.split(maxSplits: 6, whereSeparator: \.isWhitespace)
            guard fields.count == 7, let pid = Int32(fields[0]), pid > 0 else { return nil }
            return Process(pid: pid, started: fields[1...5].joined(separator: " "), command: String(fields[6]))
        }
    }

    public static func isRunning(windowsPath: String) async throws -> Bool {
        let result = try await Subprocess().run(
            URL(fileURLWithPath: "/bin/ps"), arguments: ["-axo", "command="], timeout: .seconds(5)
        )
        return result.stdout.split(separator: "\n").contains {
            matches(command: String($0), windowsPath: windowsPath)
        }
    }

    public static func matches(command: String, windowsPath: String) -> Bool {
        let command = command.trimmingCharacters(in: .whitespaces).lowercased()
        let path = windowsPath.lowercased()
        guard !path.isEmpty else { return false }
        return command == path || command.hasPrefix(path + " ") ||
            command == "\"" + path + "\"" || command.hasPrefix("\"" + path + "\" ")
    }
}
