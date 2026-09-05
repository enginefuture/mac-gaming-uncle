import Foundation
import IndieCore

public struct ProcessResult: Sendable, Equatable {
    public let status: Int32
    public let stdout: String
    public let stderr: String

    public init(status: Int32, stdout: String, stderr: String) {
        self.status = status
        self.stdout = stdout
        self.stderr = stderr
    }
}

public actor Subprocess {
    public init() {}

    @discardableResult
    public func run(
        _ executable: URL,
        arguments: [String] = [],
        environment: [String: String] = [:],
        workingDirectory: URL? = nil,
        onStart: (@Sendable (Int32) -> Void)? = nil,
        timeout: Duration? = nil,
        requireSuccess: Bool = true
    ) async throws -> ProcessResult {
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw IndieError.notFound(L("不可执行文件：\(executable.path)"))
        }

        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("indie-process-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }

        let stdoutURL = scratch.appendingPathComponent("stdout.log")
        let stderrURL = scratch.appendingPathComponent("stderr.log")
        FileManager.default.createFile(atPath: stdoutURL.path, contents: nil)
        FileManager.default.createFile(atPath: stderrURL.path, contents: nil)
        let stdoutHandle = try FileHandle(forWritingTo: stdoutURL)
        let stderrHandle = try FileHandle(forWritingTo: stderrURL)
        defer {
            try? stdoutHandle.close()
            try? stderrHandle.close()
        }

        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = workingDirectory
        process.standardOutput = stdoutHandle
        process.standardError = stderrHandle
        process.environment = Self.sanitizedEnvironment(overrides: environment)
        try process.run()
        onStart?(process.processIdentifier)

        let started = ContinuousClock.now
        var didTimeOut = false
        while process.isRunning {
            do {
                try Task.checkCancellation()
            } catch {
                process.terminate()
                try? await Task.sleep(for: .milliseconds(250))
                if process.isRunning { process.interrupt() }
                throw error
            }
            if let timeout, started.duration(to: .now) >= timeout {
                didTimeOut = true
                process.terminate()
                try await Task.sleep(for: .milliseconds(250))
                if process.isRunning { process.interrupt() }
                break
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        // On macOS 26, calling waitUntilExit() after isRunning has already
        // observed and reaped a short-lived child can block indefinitely.
        // The polling loop normally exits only after termination, so wait
        // again solely for the timeout/cancellation race where it is needed.
        if process.isRunning {
            process.waitUntilExit()
        }
        try stdoutHandle.synchronize()
        try stderrHandle.synchronize()
        let stdout = String(decoding: (try? Data(contentsOf: stdoutURL)) ?? Data(), as: UTF8.self)
        let stderr = String(decoding: (try? Data(contentsOf: stderrURL)) ?? Data(), as: UTF8.self)

        if didTimeOut { throw IndieError.timedOut(executable.lastPathComponent) }
        let result = ProcessResult(status: process.terminationStatus, stdout: stdout, stderr: stderr)
        if requireSuccess, result.status != 0 {
            throw IndieError.processFailed(executable: executable.path, status: result.status, stderr: stderr)
        }
        return result
    }

    public func launchDetached(
        _ executable: URL,
        arguments: [String] = [],
        environment: [String: String] = [:],
        workingDirectory: URL? = nil,
        logURL: URL
    ) throws -> Int32 {
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw IndieError.notFound(L("不可执行文件：\(executable.path)"))
        }
        try FileManager.default.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: logURL.path) {
            FileManager.default.createFile(atPath: logURL.path, contents: nil)
        }
        let log = try FileHandle(forWritingTo: logURL)
        try log.seekToEnd()
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = workingDirectory
        process.standardOutput = log
        process.standardError = log
        process.environment = Self.sanitizedEnvironment(overrides: environment)
        try process.run()
        try log.close()
        return process.processIdentifier
    }

    static func sanitizedEnvironment(
        inherited: [String: String] = ProcessInfo.processInfo.environment,
        overrides: [String: String]
    ) -> [String: String] {
        let allowed = [
            "PATH", "HOME", "TMPDIR", "USER", "LOGNAME", "SHELL",
            "LANG", "LC_ALL", "LC_CTYPE", "DISPLAY", "COMMAND_MODE",
            "SECURITYSESSIONID", "__CF_USER_TEXT_ENCODING", "MallocNanoZone",
        ]
        var result = Dictionary(uniqueKeysWithValues: allowed.compactMap { key in
            inherited[key].map { (key, $0) }
        })
        result.merge(overrides) { _, explicit in explicit }
        return result
    }
}
