import Foundation

/// Timing admission is independent of capture callback rate. No inferred game FPS.
public enum FrameInterpolationTiming {
    public static func midpoint(previous: Double, current: Double) -> Double? {
        let gap = current - previous
        guard previous.isFinite, current.isFinite, gap >= 1.0 / 240, gap <= 0.1 else { return nil }
        return previous + gap / 2
    }

    public static func isLate(presentation: Double, now: Double) -> Bool {
        !presentation.isFinite || !now.isFinite || presentation <= now
    }
}
