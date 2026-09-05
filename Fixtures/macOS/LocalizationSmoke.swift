import Foundation
import IndieCore

@main
struct LocalizationSmoke {
    static func main() {
        // Run from a relocated app with only its packaged resource bundle.
        precondition(Bundle.main.bundleURL.pathExtension == "app")
        precondition(AppLanguage.text("游戏库", language: "en") == "Library")
        precondition(AppLanguage.text("游戏库", language: "zh-Hans") == "游戏库")
        let count = 12
        precondition(AppLanguage.text("已同步 \(count) 款账户游戏", language: "en") == "Synced 12 account games")
        print("Packaged English and Chinese localization: OK")
    }
}
