import Foundation
import XCTest
@testable import IndieCatalog

final class SteamInstallationStateTests: XCTestCase {
    func testDownloadThenStagingThenCompletion() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("common/Test"), withIntermediateDirectories: true)
        let manifest = root.appendingPathComponent("appmanifest_42.acf")
        func write(flags: String, downloaded: UInt64, staged: UInt64) throws {
            try """
            "AppState" {
              "appid" "42" "name" "Test" "installdir" "Test" "buildid" "123"
              "StateFlags" "\(flags)" "BytesToDownload" "100" "BytesDownloaded" "\(downloaded)"
              "BytesToStage" "200" "BytesStaged" "\(staged)"
            }
            """.write(to: manifest, atomically: true, encoding: .utf8)
        }
        try write(flags: "1026", downloaded: 40, staged: 0)
        let downloading = try XCTUnwrap(SteamScanner.scan(steamApps: root).first)
        XCTAssertFalse(downloading.isReadyToPlay)
        XCTAssertEqual(downloading.downloadProgress, 0.4)
        XCTAssertFalse(try SteamAccountLibraryScanner.scan(steamRoot: root, installed: [downloading])[0].isInstalled)

        try write(flags: "131074", downloaded: 100, staged: 90)
        let staging = try SteamScanner.refreshed(downloading)
        XCTAssertFalse(staging.isReadyToPlay)
        XCTAssertTrue(staging.stagingIncomplete)
        XCTAssertEqual(staging.downloadProgress, 1)

        // Even complete counters do not replace Steam's final state commit.
        try write(flags: "131074", downloaded: 100, staged: 200)
        XCTAssertFalse(try SteamScanner.refreshed(downloading).isReadyToPlay)
        try write(flags: "4", downloaded: 100, staged: 200)
        let complete = try SteamScanner.refreshed(downloading)
        XCTAssertTrue(complete.isReadyToPlay)
        XCTAssertTrue(try SteamAccountLibraryScanner.scan(steamRoot: root, installed: [complete])[0].isInstalled)

        // A later update invalidates an old ready-to-play UI snapshot.
        try write(flags: "6", downloaded: 10, staged: 0)
        XCTAssertFalse(try SteamScanner.refreshed(complete).isReadyToPlay)
    }

    func testConservativeReadinessChecks() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        func game(flags: UInt64?, build: String? = "123", remaining: Bool = false) -> SteamGame {
            SteamGame(appID: 42, name: "Test", installDirectory: directory, buildID: build,
                      manifestURL: directory.appendingPathComponent("appmanifest_42.acf"), stateFlags: flags,
                      bytesToDownload: remaining ? 100 : nil, bytesDownloaded: remaining ? 90 : nil)
        }
        XCTAssertFalse(game(flags: nil).isReadyToPlay)
        XCTAssertFalse(game(flags: 0).isReadyToPlay)
        XCTAssertFalse(game(flags: 4, build: "0").isReadyToPlay)
        XCTAssertFalse(game(flags: 4, build: nil).isReadyToPlay)
        XCTAssertFalse(game(flags: 4, remaining: true).isReadyToPlay)
        XCTAssertTrue(game(flags: 4).isReadyToPlay)
        let missing = SteamGame(appID: 42, name: "Test", installDirectory: directory.appendingPathComponent("missing"),
                                buildID: "123", manifestURL: directory, stateFlags: 4)
        XCTAssertFalse(missing.isReadyToPlay)
    }
}
