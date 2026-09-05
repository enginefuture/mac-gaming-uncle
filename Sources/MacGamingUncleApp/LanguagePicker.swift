import IndieCore
import SwiftUI

struct LanguagePicker: View {
    @AppStorage(AppLanguage.preferenceKey) private var language = "system"
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("Language / 语言", selection: $language) {
                Text("System / 跟随系统").tag("system")
                Text("English").tag("en")
                Text("简体中文").tag("zh-Hans")
            }
            Text("Reopen the app to apply. / 重新打开应用后生效。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
