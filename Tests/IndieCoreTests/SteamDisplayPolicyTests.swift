import XCTest
@testable import IndieCore

final class SteamDisplayPolicyTests: XCTestCase {
    func testPolicyChangesInvalidateReuseAndLegacyDescriptorsDecode() throws {
        let bottle = UUID()
        func descriptor(_ policy: SteamDisplayPolicy?) -> SteamSessionDescriptor {
            SteamSessionDescriptor(bottleID: bottle, runtimeID: "wine", environment: [:], virtualDesktop: nil, displayPolicy: policy)
        }
        let grim = SteamDisplayPolicy(retinaEnabled: false, topology: "display-a:1x")
        var tracker = SteamSessionTracker()
        tracker.didLaunch(descriptor(grim), reused: false)
        XCTAssertTrue(tracker.canReuse(descriptor(grim)))
        XCTAssertFalse(tracker.canReuse(descriptor(.init(retinaEnabled: true, topology: "display-a:1x"))))
        XCTAssertFalse(tracker.canReuse(descriptor(.init(retinaEnabled: false, topology: "display-b:2x"))))
        let legacy = Data("{\"bottleID\":\"\(bottle.uuidString)\",\"runtimeID\":\"wine\",\"environment\":{}}".utf8)
        let restored = try JSONDecoder().decode(SteamSessionDescriptor.self, from: legacy)
        XCTAssertNil(restored.displayPolicy)
        tracker.didLaunch(restored, reused: false)
        XCTAssertFalse(tracker.canReuse(descriptor(grim)))
        XCTAssertEqual(grim.registryArguments.suffix(2), ["N", "/f"])
    }
}
