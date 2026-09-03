import SwiftUI

@main
struct IndieApplication: App {
    @StateObject private var model = IndieAppModel()

    var body: some Scene {
        Window("Indie", id: "main") {
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
