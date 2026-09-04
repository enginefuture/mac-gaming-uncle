import SwiftUI

@main
struct MacGamingUncleApplication: App {
    @StateObject private var model = MacGamingUncleAppModel()

    var body: some Scene {
        Window("Mac Gaming Uncle", id: "main") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 1100, minHeight: 720)
                .onOpenURL { model.handleDeepLink($0) }
        }
        .defaultSize(width: 1200, height: 850)
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact(showsTitle: false))

        Settings {
            SettingsView()
                .environmentObject(model)
                .frame(width: 560, height: 360)
        }
    }
}
