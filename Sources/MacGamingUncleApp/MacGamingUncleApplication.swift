import SwiftUI

@main
struct MacGamingUncleApplication: App {
    @NSApplicationDelegateAdaptor(UncleApplicationDelegate.self) private var appDelegate
    @StateObject private var model = MacGamingUncleAppModel()

    var body: some Scene {
        Window("Mac Gaming Uncle", id: "steam-shell-main") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 1100, minHeight: 720)
                .onOpenURL { model.handleDeepLink($0) }
                .onAppear { appDelegate.model = model }
        }
        .defaultSize(width: 1440, height: 920)
        .defaultPosition(.center)
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact(showsTitle: false))

        Settings {
            SettingsView()
                .environmentObject(model)
                .frame(width: 560, height: 360)
        }
    }
}

@MainActor
final class UncleApplicationDelegate: NSObject, NSApplicationDelegate {
    weak var model: MacGamingUncleAppModel?
    private var shutdownTask: Task<Void, Never>?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model else { return .terminateNow }
        if shutdownTask == nil {
            shutdownTask = Task { @MainActor in
                await model.shutdownManagedSteam()
                sender.reply(toApplicationShouldTerminate: true)
            }
        }
        return .terminateLater
    }
}
