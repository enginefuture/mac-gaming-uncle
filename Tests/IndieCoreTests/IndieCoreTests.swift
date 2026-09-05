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

    func testStateStoreKeepsGameConfigurationsIndependent() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("indie-config-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = StateStore(databaseURL: root.appendingPathComponent("state.sqlite"))
        try await store.open()
        let first = GameConfiguration(
            id: "steam:10", virtualDesktop: .init(width: 1920, height: 1080),
            metalHUD: .enabled, controllerMode: .enhanced,
            updatedAt: Date(timeIntervalSince1970: 1_000_000)
        )
        let second = GameConfiguration(
            id: "steam:20", virtualDesktop: .init(width: 1280, height: 720),
            preferredRenderer: .wineD3D, metalHUD: .disabled,
            updatedAt: Date(timeIntervalSince1970: 2_000_000)
        )
        try await store.saveGameConfiguration(first)
        try await store.saveGameConfiguration(second)

        let saved = try await store.gameConfigurations()
        XCTAssertEqual(Set(saved.map(\.id)), ["steam:10", "steam:20"])
        XCTAssertEqual(saved.first(where: { $0.id == first.id }), first)
        XCTAssertEqual(saved.first(where: { $0.id == second.id }), second)
    }

    func testGameSettingOverrideResolvesGlobalDefault() {
        XCTAssertTrue(GameSettingOverride.inherit.resolve(default: true))
        XCTAssertFalse(GameSettingOverride.inherit.resolve(default: false))
        XCTAssertTrue(GameSettingOverride.enabled.resolve(default: false))
        XCTAssertFalse(GameSettingOverride.disabled.resolve(default: true))
    }

    func testSteamSessionOnlyReusesCompatibleGlobalEnvironment() throws {
        let bottleID = UUID()
        let base = SteamSessionDescriptor(
            bottleID: bottleID,
            runtimeID: "wine-11",
            environment: ["INDIE_RENDERER": "d3dmetal", "MTL_HUD_ENABLED": "1"],
            virtualDesktop: .init(width: 1920, height: 1080)
        )
        var tracker = SteamSessionTracker()
        XCTAssertFalse(tracker.canReuse(base))
        tracker.didLaunch(base, reused: false)
        XCTAssertTrue(tracker.canReuse(base))
        XCTAssertEqual(
            try IndieJSON.decoder().decode(
                SteamSessionDescriptor.self,
                from: IndieJSON.encoder().encode(base)
            ),
            base
        )

        let differentHUD = SteamSessionDescriptor(
            bottleID: bottleID,
            runtimeID: "wine-11",
            environment: ["INDIE_RENDERER": "d3dmetal"],
            virtualDesktop: .init(width: 1920, height: 1080)
        )
        XCTAssertFalse(tracker.canReuse(differentHUD))
        tracker.didLaunch(base, reused: true)
        XCTAssertEqual(tracker.reuseCount, 1)
        tracker.didStop()
        XCTAssertFalse(tracker.canReuse(base))
    }

    func testSetupFlowAdvancesInOrder() {
        XCTAssertEqual(SetupFlow.stage(environmentReady: false, steamInstalled: false, installedGameCount: 0), .environment)
        XCTAssertEqual(SetupFlow.stage(environmentReady: true, steamInstalled: false, installedGameCount: 0), .steam)
        XCTAssertEqual(SetupFlow.stage(environmentReady: true, steamInstalled: true, installedGameCount: 0), .game)
        XCTAssertEqual(SetupFlow.stage(environmentReady: true, steamInstalled: true, installedGameCount: 1), .ready)
    }
}
