import XCTest
@testable import IndieCatalog

final class Dota2CompatibilityTests: XCTestCase {
    func testOnlyCurrentAccountIsChangedAndBackupIsRetained() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: root) }
        let config = root.appendingPathComponent("config")
        let video = root.appendingPathComponent("userdata/109656806/570/local/cfg/video.txt")
        let other = root.appendingPathComponent("userdata/1/570/local/cfg/video.txt")
        for directory in [config, video.deletingLastPathComponent(), other.deletingLastPathComponent()] {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let login = #""users" { "76561198069922534" { "MostRecent" "1" } "76561197960265729" { "MostRecent" "0" } }"#
        try Data(login.utf8).write(to: config.appendingPathComponent("loginusers.vdf"))
        let original = Data("\"video.cfg\" {\n\"setting.coop_fullscreen\" \"0\"\n}\n".utf8)
        try original.write(to: video)
        try original.write(to: other)
        XCTAssertTrue(try Dota2Compatibility.prepare(steamRoot: root))
        XCTAssertFalse(try Dota2Compatibility.prepare(steamRoot: root))
        XCTAssertEqual(try Data(contentsOf: other), original)
        XCTAssertEqual(try Data(contentsOf: video.appendingPathExtension("indie-before-desktop-fullscreen")), original)
        let single = #""users" { "76561198069922534" { "Timestamp" "123" } }"#
        try Data(single.utf8).write(to: config.appendingPathComponent("loginusers.vdf"))
        try original.write(to: video)
        XCTAssertTrue(try Dota2Compatibility.prepare(steamRoot: root))
        let ambiguous = #""users" { "76561198069922534" { } "76561197960265729" { } }"#
        try Data(ambiguous.utf8).write(to: config.appendingPathComponent("loginusers.vdf"))
        try original.write(to: video)
        XCTAssertFalse(try Dota2Compatibility.prepare(steamRoot: root))
        XCTAssertEqual(try Data(contentsOf: video), original)
    }

    func testDesktopFullscreenPreservesOtherSettingsAndIsIdempotent() throws {
        let input = Data("\"video.cfg\"\r\n{\r\n\t\"setting.coop_fullscreen\" \"0\"\r\n\t\"setting.gpu_level\" \"3\"\r\n}\r\n".utf8)
        let output = try Dota2Compatibility.desktopFullscreenConfiguration(input)
        let values = try XCTUnwrap(VDFParser.parse(data: output)["video.cfg"]?.object)
        XCTAssertEqual(values["setting.coop_fullscreen"]?.string, "1")
        XCTAssertEqual(values["setting.defaultres"]?.string, "1920")
        XCTAssertEqual(values["setting.defaultresheight"]?.string, "1080")
        XCTAssertEqual(values["setting.gpu_level"]?.string, "3")
        XCTAssertEqual(output, try Dota2Compatibility.desktopFullscreenConfiguration(output))
    }

    func testMalformedAndDuplicateInputRejected() {
        XCTAssertThrowsError(try Dota2Compatibility.desktopFullscreenConfiguration(Data("broken".utf8)))
        let duplicate = "\"video.cfg\" {\n\"setting.fullscreen\" \"0\"\n\"setting.fullscreen\" \"1\"\n}"
        XCTAssertThrowsError(try Dota2Compatibility.desktopFullscreenConfiguration(Data(duplicate.utf8)))
    }
}
