import XCTest
@testable import IndieRuntime

final class FrameInterpolationMultiplierTests: XCTestCase {
    func testSDKDepthIsNotOutputCount() {
        XCTAssertEqual(FrameInterpolationMultiplier.double.configurationDepth, 1)
        XCTAssertEqual(FrameInterpolationMultiplier.double.phases, [0.5])
        XCTAssertEqual(FrameInterpolationMultiplier.quadruple.configurationDepth, 2)
        XCTAssertEqual(FrameInterpolationMultiplier.quadruple.phases, [0.25, 0.5, 0.75])
    }
    func testNoUnsupportedSixTimesSetting() {
        XCTAssertNil(FrameInterpolationMultiplier(rawValue: 6))
        for multiplier in FrameInterpolationMultiplier.allCases {
            XCTAssertEqual(multiplier.phases.count, multiplier.rawValue - 1)
            XCTAssertTrue(multiplier.phases.allSatisfy { $0 > 0 && $0 < 1 })
        }
    }
}
