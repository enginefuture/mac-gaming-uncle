import XCTest
@testable import IndieCore

final class AutomaticInterpolationStateTests: XCTestCase {
    func testStableWindowAndFocusReturn() {
        var state = AutomaticInterpolationState()
        XCTAssertEqual(state.observe(run: "1:startA", window: nil, foreground: false), .pause)
        XCTAssertEqual(state.observe(run: "1:startA", window: "windowA", foreground: true), .pause)
        XCTAssertEqual(state.observe(run: "1:startA", window: "windowA", foreground: true), .start)
        XCTAssertEqual(state.observe(run: "1:startA", window: "windowA", foreground: false), .pause)
        XCTAssertEqual(state.observe(run: "1:startA", window: "windowA", foreground: true), .pause)
        XCTAssertEqual(state.observe(run: "1:startA", window: "windowA", foreground: true), .start)
    }
    func testManualStopSurvivesFocusAndWindowChangesUntilNewRun() {
        var state = AutomaticInterpolationState()
        _ = state.observe(run: "1:A", window: "windowA", foreground: true)
        state.suppressCurrentRun()
        _ = state.observe(run: "1:A", window: nil, foreground: false)
        XCTAssertEqual(state.observe(run: "1:A", window: "windowB", foreground: true), .wait)
        XCTAssertTrue(state.isSuppressed)
        // Same PID, different start time is a new run.
        XCTAssertEqual(state.observe(run: "1:B", window: "windowB", foreground: true), .pause)
        XCTAssertEqual(state.observe(run: "1:B", window: "windowB", foreground: true), .start)
        XCTAssertFalse(state.isSuppressed)
    }
    func testFailuresDoNotRetryForeverAndExplicitRearmWorks() {
        var state = AutomaticInterpolationState()
        _ = state.observe(run: "1:A", window: "1080p", foreground: true)
        state.failed(window: "1080p")
        XCTAssertEqual(state.observe(run: "1:A", window: "1080p", foreground: true), .wait)
        XCTAssertEqual(state.observe(run: "1:A", window: "720p", foreground: true), .pause)
        XCTAssertEqual(state.observe(run: "1:A", window: "720p", foreground: true), .start)
        state.suppressCurrentRun()
        state.rearm()
        XCTAssertEqual(state.observe(run: "1:A", window: "1080p", foreground: true), .pause)
        XCTAssertEqual(state.observe(run: "1:A", window: "1080p", foreground: true), .start)
    }
}
