import Foundation
import XCTest
@testable import IndieCore
@testable import IndieRuntime

final class GPTKDownloadServiceTests: XCTestCase {
    func testRejectsTruncatedImage() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        try Data("not a DMG".utf8).write(to: file)
        XCTAssertThrowsError(try GPTKDownloadService.validate(file))
    }

    func testRejectsSameSizeTamperedImage() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        try Data(repeating: 0, count: Int(GPTKDownloadService.size)).write(to: file)
        XCTAssertThrowsError(try GPTKDownloadService.validate(file))
    }

    func testLiveR2DownloadCacheAndAppleImport() async throws {
        guard ProcessInfo.processInfo.environment["INDIE_TEST_R2"] == "1" else {
            throw XCTSkip("Opt-in network and Apple signature integration test")
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("gptk-r2-test-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = IndiePaths(root: root)
        let downloader = GPTKDownloadService(paths: paths)
        let image = try await downloader.download()
        try GPTKDownloadService.validate(image)
        let modification = try image.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        let cached = try await downloader.download()
        XCTAssertEqual(cached, image)
        XCTAssertEqual(try cached.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate, modification)
        let component = try await GPTKImporter(paths: paths).importFromAppleImage(image)
        XCTAssertEqual(component.version, "4.0b2")
        XCTAssertEqual(component.sourceSHA256, GPTKDownloadService.sha256)
        XCTAssertNotNil(component.rendererRoot)
    }
}
