import IndieCore
import SwiftUI
import IndieCore

@main
struct MacGamingUncleApplication: App {
    @NSApplicationDelegateAdaptor(UncleApplicationDelegate.self) private var appDelegate
    @StateObject private var model = MacGamingUncleAppModel()

    var body: some Scene {
        Window("Mac Gaming Uncle", id: "steam-shell-main") {
            ContentView()
                .environmentObject(model)
                .environment(\.locale, AppLanguage.locale)
                .frame(minWidth: 1100, minHeight: 720)
                .onOpenURL { model.handleDeepLink($0) }
                .onAppear {
                    appDelegate.model = model
                    if #available(macOS 26, *) { AutomaticFrameInterpolation.shared.bind(model: model) }
                }
        }
        .defaultSize(width: 1440, height: 920)
        .defaultPosition(.center)
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact(showsTitle: false))

        Settings {
            SettingsView()
                .environmentObject(model)
                .environment(\.locale, AppLanguage.locale)
                .frame(width: 560, height: 360)
        }
        WindowGroup(L("通用插帧（实验）"), id: "frame-interpolation", for: String.self) { id in
            if #available(macOS 26, *) {
                FrameInterpolationView(gameID: id.wrappedValue ?? "manual")
                    .environmentObject(model)
                    .environment(\.locale, AppLanguage.locale)
            } else {
                Text(L("通用插帧需要 macOS 26 或更新版本")).padding(32)
            }
        }
        .defaultSize(width: 620, height: 440)
        .commands {
            CommandMenu(L("通用插帧（实验）")) {
                Button(L("停止插帧")) {
                    if #available(macOS 26, *) { GameFrameInterpolation.shared.stop() }
                }
            }
        }
    }
}

@MainActor
final class UncleApplicationDelegate: NSObject, NSApplicationDelegate {
    weak var model: MacGamingUncleAppModel?
    private var shutdownTask: Task<Void, Never>?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if #available(macOS 26, *) { AutomaticFrameInterpolation.shared.shutdown() }
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
