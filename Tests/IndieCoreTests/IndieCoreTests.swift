import Foundation
import XCTest
@testable import IndieCore

final class IndieCoreTests: XCTestCase {
    func testSemanticVersionOrdering() throws {
        XCTAssertLessThan(try SemanticVersion("11.0-rc1"), try SemanticVersion("11.0"))
        XCTAssertLessThan(try SemanticVersion("10.9.4"), try SemanticVersion("11.0"))
        XCTAssertEqual(try SemanticVersion("15.2"), SemanticVersion(major: 15, minor: 2, patch: 0))
    }

    func testModelRoundTrip() throws {
        let analysis = GameAnalysis(
            identity: GameIdentity(steamAppID: 42, executableSHA256: String(repeating: "a", count: 64), executableName: "Game.exe"),
            architecture: .x86_64,
            directX: .d3d12,
            antiCheat: .none,
            importedLibraries: ["d3d12.dll"]
        )
        let data = try IndieJSON.encoder().encode(analysis)
        XCTAssertEqual(try IndieJSON.decoder().decode(GameAnalysis.self, from: data), analysis)
    }

    func testStateStorePersistsBottle() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("indie-state-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = StateStore(databaseURL: root.appendingPathComponent("state.sqlite"))
        try await store.open()
        let bottle = BottleRecord(name: "Test", root: root.appendingPathComponent("Bottle"), runtimeID: "wine-11")
        try await store.saveBottle(bottle)
        let saved = try await store.bottles()
        XCTAssertEqual(saved.map(\.id), [bottle.id])
        XCTAssertEqual(saved.first?.name, bottle.name)
    }

    func testSetupFlowAdvancesInOrder() {
        XCTAssertEqual(SetupFlow.stage(environmentReady: false, steamInstalled: false, installedGameCount: 0), .environment)
        XCTAssertEqual(SetupFlow.stage(environmentReady: true, steamInstalled: false, installedGameCount: 0), .steam)
        XCTAssertEqual(SetupFlow.stage(environmentReady: true, steamInstalled: true, installedGameCount: 0), .game)
        XCTAssertEqual(SetupFlow.stage(environmentReady: true, steamInstalled: true, installedGameCount: 1), .ready)
    }
}
