import XCTest
@testable import IndieCatalog

final class GrimDawnDisplayRepairTests: XCTestCase {
    func testFullscreenUsesCompleteMonitorDimensions() throws {
        XCTAssertEqual(GrimDawnCompatibility.logicalDisplayResolution(width: 2560, height: 1440), "2560 1440")
        // Integration guard: avoid reintroducing work-area/title-bar subtraction
        // in the only app call site that selects the Grim Dawn display size.
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("Sources/MacGamingUncleApp/MacGamingUncleAppModel.swift"), encoding: .utf8)
        XCTAssertTrue(source.contains("let screen = NSScreen.screens.first?.frame.size"))
        XCTAssertFalse(source.contains("Double($0.height) - 32"))
    }

    func testRepairsMixedNewlinesAndDuplicatesWithoutChangingOtherOptions() throws {
        for ending in ["\n", "\r\n", "\r"] {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: root) }
            let settings = root.appendingPathComponent("drive_c/users/player/Documents/My Games/Grim Dawn/Settings")
            try FileManager.default.createDirectory(at: settings, withIntermediateDirectories: true)
            let file = settings.appendingPathComponent("options.txt")
            let original = ["resolution = 1512 982", "screenMode = 2", "uiScale = 0.5", "custom = keep"].joined(separator: ending)
                + ending + "resolution = 2560 1440\nscreenMode = 0\n"
            try original.write(to: file, atomically: true, encoding: .utf8)
            XCTAssertTrue(try GrimDawnCompatibility.prepare(bottleRoot: root, safeResolution: "1920 1080").changed)
            let fixed = try String(contentsOf: file, encoding: .utf8)
            let lines = fixed.components(separatedBy: .newlines)
            for key in ["resolution", "screenMode", "gamepadSupport", "standardHUD", "syncToRefresh"] {
                XCTAssertEqual(lines.filter { $0.split(separator: "=").first?.trimmingCharacters(in: .whitespaces) == key }.count, 1)
            }
            XCTAssertTrue(fixed.contains("uiScale = 0.5"))
            XCTAssertTrue(fixed.contains("custom = keep"))
            XCTAssertFalse(fixed.contains("1512 982"))
            XCTAssertFalse(fixed.contains("2560 1440"))
            XCTAssertFalse(try GrimDawnCompatibility.prepare(bottleRoot: root, safeResolution: "1920 1080").changed)
            XCTAssertEqual(try String(contentsOf: file.appendingPathExtension("indie-before-display-repair"), encoding: .utf8), original)
        }
    }
}
