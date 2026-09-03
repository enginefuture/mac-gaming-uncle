import SwiftUI

@main
struct IndieApplication: App {
    @StateObject private var model = IndieAppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 1100, minHeight: 720)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact(showsTitle: false))

        Settings {
            SettingsView()
                .environmentObject(model)
                .frame(width: 560, height: 360)
        }
    }
}
