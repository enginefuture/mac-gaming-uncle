import Foundation
import XCTest

final class PrivacyMetadataTests: XCTestCase {
    func testMicrophonePurposeAndLocalizationsArePackagedInputs() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        for relative in ["Config/Info.plist", "Config/en.lproj/InfoPlist.strings", "Config/zh-Hans.lproj/InfoPlist.strings"] {
            let data = try Data(contentsOf: root.appendingPathComponent(relative))
            let values = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
            let purpose = try XCTUnwrap(values["NSMicrophoneUsageDescription"] as? String)
            XCTAssertFalse(purpose.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, relative)
        }
    }
}
