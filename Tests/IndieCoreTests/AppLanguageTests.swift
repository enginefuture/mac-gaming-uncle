import Foundation
import XCTest
@testable import IndieCore

final class AppLanguageTests: XCTestCase {
    func testSystemLanguageAndExplicitOverride() {
        XCTAssertEqual(AppLanguage.resolve(nil, preferred: ["en-US"]), "en")
        XCTAssertEqual(AppLanguage.resolve("system", preferred: ["zh-CN"]), "zh-Hans")
        XCTAssertEqual(AppLanguage.resolve(nil, preferred: ["fr-FR"]), "en")
        XCTAssertEqual(AppLanguage.resolve("en", preferred: ["zh-CN"]), "en")
        XCTAssertEqual(AppLanguage.resolve("zh-Hans", preferred: ["en-US"]), "zh-Hans")
    }

    func testBothCatalogsLoadAndInterpolationPreservesUserContent() {
        XCTAssertEqual(AppLanguage.text("游戏库", language: "en"), "Library")
        XCTAssertEqual(AppLanguage.text("游戏库", language: "zh-Hans"), "游戏库")
        let count = 646
        XCTAssertEqual(AppLanguage.text("已同步 \(count) 款账户游戏", language: "en"), "Synced 646 account games")
        XCTAssertEqual(AppLanguage.text("已同步 \(count) 款账户游戏", language: "zh-Hans"), "已同步 646 款账户游戏")
        let name = "中文 game %@ 100%"
        XCTAssertEqual(AppLanguage.text("正在运行 \(name)…", language: "en"), "Running 中文 game %@ 100%…")
        XCTAssertEqual(AppLanguage.text("Unknown key", language: "en"), "Unknown key")
    }
}
