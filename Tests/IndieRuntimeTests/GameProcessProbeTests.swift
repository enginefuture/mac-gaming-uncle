import XCTest
@testable import IndieRuntime

final class GameProcessProbeTests: XCTestCase {
    func testMatchesExactWindowsExecutableWithArgumentsAndQuotes() {
        let path = #"C:\Program Files (x86)\Steam\steamapps\common\dota 2 beta\game\bin\win64\dota2.exe"#
        XCTAssertTrue(GameProcessProbe.matches(command: path + " -dx11", windowsPath: path))
        XCTAssertTrue(GameProcessProbe.matches(command: "\"" + path + "\" -dx11", windowsPath: path))
        XCTAssertTrue(GameProcessProbe.matches(command: path.uppercased(), windowsPath: path))
        XCTAssertFalse(GameProcessProbe.matches(command: path + ".backup", windowsPath: path))
        XCTAssertFalse(GameProcessProbe.matches(command: "grep " + path, windowsPath: path))
        XCTAssertFalse(GameProcessProbe.matches(command: "steam.exe -applaunch 570", windowsPath: path))
        XCTAssertFalse(GameProcessProbe.matches(command: "anything", windowsPath: ""))
    }
}
