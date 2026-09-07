import XCTest
@testable import IndieCore

final class FrameInterpolationTests: XCTestCase {
    func testTimingRejectsDuplicateReverseAndStalledFrames() {
        XCTAssertEqual(FrameInterpolationTiming.midpoint(previous: 1, current: 1.02), 1.01)
        XCTAssertNil(FrameInterpolationTiming.midpoint(previous: 1, current: 1))
        XCTAssertNil(FrameInterpolationTiming.midpoint(previous: 1, current: 0.9))
        XCTAssertNil(FrameInterpolationTiming.midpoint(previous: 1, current: 1.2))
        XCTAssertNil(FrameInterpolationTiming.midpoint(previous: .nan, current: 2))
        XCTAssertTrue(FrameInterpolationTiming.isLate(presentation: 1, now: 1.01))
        XCTAssertFalse(FrameInterpolationTiming.isLate(presentation: 1.01, now: 1))
    }
    func testContentCutAndRepeatDetection() {
        let a = FrameContentSignature(luma: [20, 30, 40, 50])
        XCTAssertEqual(a, FrameContentSignature(luma: [20, 30, 40, 50]))
        XCTAssertFalse(FrameContentSignature(luma: [25, 35, 45, 55]).isSceneCut(from: a))
        XCTAssertTrue(FrameContentSignature(luma: [240, 240, 240, 240]).isSceneCut(from: a))
    }
    func testOldConfigurationsDefaultOffAndPreferencesRoundTrip() throws {
        let original = GameConfiguration.steam(appID: 570)
        let encoded = try IndieJSON.encoder().encode(original)
        let decoded = try IndieJSON.decoder().decode(GameConfiguration.self, from: encoded)
        XCTAssertNil(decoded.frameInterpolation)
        XCTAssertFalse(decoded.isCustomized)
        var enabled = original
        enabled.frameInterpolation = true
        XCTAssertTrue(enabled.isCustomized)
        XCTAssertEqual(try IndieJSON.decoder().decode(GameConfiguration.self, from: IndieJSON.encoder().encode(enabled)).frameInterpolation, true)
        XCTAssertNil(GameConfiguration.steam(appID: 219990).frameInterpolation)
    }
}
