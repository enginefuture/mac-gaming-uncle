import Foundation

/// One game's run-scoped policy. Process identity includes PID AND start time.
public struct AutomaticInterpolationState: Sendable {
    public enum Decision: Equatable, Sendable { case wait, pause, start }
    public private(set) var run: String?
    public private(set) var isSuppressed = false
    private var pendingWindow: String?
    private var stableObservations = 0
    private var failedWindows = Set<String>()

    public init() {}
    public mutating func observe(run newRun: String?, window: String?, foreground: Bool) -> Decision {
        if newRun != run {
            run = newRun; isSuppressed = false; failedWindows.removeAll()
            pendingWindow = nil; stableObservations = 0
        }
        guard run != nil, foreground, let window else {
            pendingWindow = nil; stableObservations = 0
            return .pause
        }
        guard !isSuppressed, !failedWindows.contains(window) else { return .wait }
        if pendingWindow != window { pendingWindow = window; stableObservations = 1; return .pause }
        stableObservations += 1
        return stableObservations >= 2 ? .start : .wait
    }
    public mutating func suppressCurrentRun() { if run != nil { isSuppressed = true } }
    public mutating func failed(window: String) { failedWindows.insert(window) }
    public func hasFailed(window: String) -> Bool { failedWindows.contains(window) }
    public mutating func rearm() {
        isSuppressed = false; failedWindows.removeAll(); pendingWindow = nil; stableObservations = 0
    }
}
