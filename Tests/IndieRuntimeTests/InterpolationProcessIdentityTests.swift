import XCTest
@testable import IndieRuntime

final class InterpolationProcessIdentityTests: XCTestCase {
    func testPIDStartTimeAndPathsWithSpaces() {
        let processes = GameProcessProbe.parseProcesses(" 123 Mon Sep  7 02:10:11 2026 C:\\Games\\Grim Dawn\\grim dawn.exe -dx11\ninvalid\n 0 Mon Sep 7 02:10:11 2026 ignored")
        XCTAssertEqual(processes.count, 1)
        XCTAssertEqual(processes[0].pid, 123)
        XCTAssertEqual(processes[0].identity, "123:Mon Sep 7 02:10:11 2026")
        XCTAssertTrue(GameProcessProbe.matches(command: processes[0].command, windowsPath: "C:\\Games\\Grim Dawn\\grim dawn.exe"))
        XCTAssertFalse(GameProcessProbe.matches(command: processes[0].command, windowsPath: "C:\\Games\\Grim Dawn\\grim dawn.exe.bak"))
    }
}
