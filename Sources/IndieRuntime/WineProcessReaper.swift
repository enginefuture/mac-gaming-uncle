import Darwin
import Foundation

public enum WineProcessReaper {
    /// Terminates processes whose real host executable belongs to Indie's
    /// private Wine runtime. This is a fallback for orphaned Wine clients that
    /// no longer respond to `wineserver -k` after the parent app has exited.
    @discardableResult
    public static func terminate(runtimeRoot: URL, grace: Duration = .seconds(2)) async -> [Int32] {
        let candidates = processes(runtimeRoot: runtimeRoot)
        guard !candidates.isEmpty else { return [] }

        // Clients first, wineserver last, so Wine gets an opportunity to
        // flush normal process shutdown before its coordinator disappears.
        let ordered = candidates.sorted { lhs, rhs in
            let lhsServer = lhs.path.lastPathComponent == "wineserver"
            let rhsServer = rhs.path.lastPathComponent == "wineserver"
            return lhsServer == rhsServer ? lhs.pid < rhs.pid : !lhsServer
        }
        for process in ordered { _ = kill(process.pid, SIGTERM) }

        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: grace)
        while clock.now < deadline, ordered.contains(where: { isRunning($0.pid) }) {
            try? await Task.sleep(for: .milliseconds(100))
        }
        for process in ordered where isRunning(process.pid) {
            _ = kill(process.pid, SIGKILL)
        }
        return ordered.map(\.pid)
    }

    static func processes(runtimeRoot: URL) -> [(pid: Int32, path: URL)] {
        var pids = [Int32](repeating: 0, count: 8192)
        let byteCount = proc_listpids(
            UInt32(PROC_ALL_PIDS), 0, &pids,
            Int32(pids.count * MemoryLayout<Int32>.size)
        )
        guard byteCount > 0 else { return [] }
        let count = min(Int(byteCount) / MemoryLayout<Int32>.size, pids.count)
        let prefix = runtimeRoot.standardizedFileURL.path + "/"
        var result: [(Int32, URL)] = []
        for pid in pids.prefix(count) where pid > 1 && pid != getpid() {
            var pathBuffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
            guard proc_pidpath(pid, &pathBuffer, UInt32(pathBuffer.count)) > 0 else { continue }
            let bytes = pathBuffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
            let path = String(decoding: bytes, as: UTF8.self)
            guard path.hasPrefix(prefix) else { continue }
            result.append((pid, URL(fileURLWithPath: path)))
        }
        return result
    }

    private static func isRunning(_ pid: Int32) -> Bool {
        if kill(pid, 0) == 0 { return true }
        return errno == EPERM
    }
}
