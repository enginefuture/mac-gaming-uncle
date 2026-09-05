import Foundation
import XCTest
@testable import IndieCore

final class PackagedResourcesTests: XCTestCase {
    func testRelocatedAppLoadsResourcesWithoutDevelopmentFallback() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let app = root.appendingPathComponent("Relocated.app")
        let resources = app.appendingPathComponent("Contents/Resources/Test.bundle")
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        let plist: [String: String] = ["CFBundleIdentifier": "test.relocated", "CFBundlePackageType": "APPL"]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: app.appendingPathComponent("Contents/Info.plist"))
        try Data("payload".utf8).write(to: resources.appendingPathComponent("example.txt"))
        let main = try XCTUnwrap(Bundle(url: app))
        func unexpectedFallback() -> Bundle {
            XCTFail("Installed apps must not access the development build directory")
            return .main
        }
        let bundle = try XCTUnwrap(PackagedResources.bundle(named: "Test", main: main, development: unexpectedFallback()))
        let url = try XCTUnwrap(bundle.url(forResource: "example", withExtension: "txt"))
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "payload")
        XCTAssertNil(PackagedResources.bundle(named: "Missing", main: main, development: unexpectedFallback()))
    }
}
