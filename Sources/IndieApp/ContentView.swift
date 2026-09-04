import AppKit
import IndieCore
import IndieRuntime
import SwiftUI
import UniformTypeIdentifiers

private enum MainDestination: String {
    case start
    case library
}

private enum IndiePalette {
    static let canvas = Color(red: 0.035, green: 0.043, blue: 0.070)
    static let sidebar = Color(red: 0.045, green: 0.052, blue: 0.082)
    static let surface = Color.white.opacity(0.055)
    static let surfaceStrong = Color.white.opacity(0.085)
    static let border = Color.white.opacity(0.10)
    static let primary = Color(red: 0.49, green: 0.34, blue: 1.0)
    static let blue = Color(red: 0.16, green: 0.51, blue: 1.0)
    static let green = Color(red: 0.20, green: 0.86, blue: 0.52)
    static let secondaryText = Color.white.opacity(0.58)
}

struct ContentView: View {
    @EnvironmentObject private var model: IndieAppModel
    @State private var destination: MainDestination = .start
    @State private var showAdvanced = false

    var body: some View {
        NavigationSplitView {
            IndieSidebar(destination: $destination, showAdvanced: $showAdvanced)
                .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 250)
        } detail: {
            ZStack {
                IndieBackground()
                switch destination {
                case .start:
                    SetupHomeView(openLibrary: { destination = .library }, showAdvanced: { showAdvanced = true })
                case .library:
                    LibraryView(returnToStart: { destination = .start })
                }
            }
        }
        .preferredColorScheme(.dark)
        .alert("无法完成操作", isPresented: Binding(
            get: { model.lastError != nil },
            set: { if !$0 { model.lastError = nil } }
        )) {
            Button("知道了") { model.lastError = nil }
            Button("打开高级设置") { model.lastError = nil; showAdvanced = true }
        } message: {
            Text(model.lastError ?? "")
        }
        .sheet(isPresented: $showAdvanced) {
            AdvancedSettingsView()
                .environmentObject(model)
                .frame(minWidth: 760, minHeight: 620)
        }
    }
}

private struct IndieSidebar: View {
    @Binding var destination: MainDestination
    @Binding var showAdvanced: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9)
                        .fill(LinearGradient(colors: [IndiePalette.primary, IndiePalette.blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                    Image(systemName: "play.fill").font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                }
                .frame(width: 32, height: 32)
                .shadow(color: IndiePalette.primary.opacity(0.42), radius: 12)
                Text("Indie").font(.system(size: 21, weight: .semibold, design: .rounded))
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 30)

            SidebarButton(title: "开始", icon: "house", selected: destination == .start) { destination = .start }
            SidebarButton(title: "游戏库", icon: "gamecontroller", selected: destination == .library) { destination = .library }

            Spacer()

            Button { showAdvanced = true } label: {
                Label("高级设置", systemImage: "gearshape")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(IndiePalette.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
            .background(IndiePalette.surface, in: RoundedRectangle(cornerRadius: 11))
            .padding(14)
            .accessibilityHint("管理 Wine、D3DMetal 和诊断信息")
        }
        .background(.ultraThinMaterial)
        .background(IndiePalette.sidebar.opacity(0.84))
        .overlay(alignment: .trailing) { Rectangle().fill(IndiePalette.border).frame(width: 1) }
    }
}

private struct SidebarButton: View {
    let title: String
    let icon: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 15, weight: selected ? .semibold : .medium))
                .foregroundStyle(selected ? Color.white : IndiePalette.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
        .background(selected ? IndiePalette.surfaceStrong : .clear, in: RoundedRectangle(cornerRadius: 11))
        .overlay {
            if selected { RoundedRectangle(cornerRadius: 11).stroke(IndiePalette.border, lineWidth: 1) }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 6)
    }
}

private struct IndieBackground: View {
    var body: some View {
        ZStack {
            IndiePalette.canvas
            RadialGradient(colors: [IndiePalette.primary.opacity(0.18), .clear], center: UnitPoint(x: 0.64, y: 0.34), startRadius: 20, endRadius: 520)
            RadialGradient(colors: [IndiePalette.blue.opacity(0.12), .clear], center: UnitPoint(x: 0.88, y: 0.72), startRadius: 30, endRadius: 470)
        }
        .ignoresSafeArea()
    }
}

private struct SetupHomeView: View {
    @EnvironmentObject private var model: IndieAppModel
    let openLibrary: () -> Void
    let showAdvanced: () -> Void

    private var stage: SetupStage { model.setupStage }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                SetupProgressHeader(stage: stage).padding(.top, 26)
                Spacer(minLength: 50)

                VStack(spacing: 20) {
                    Text("让 Windows 游戏在 Mac 上运行")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .tracking(-0.6)
                        .multilineTextAlignment(.center)

                    Image(systemName: stageIcon)
                        .font(.system(size: 31, weight: .medium))
                        .foregroundStyle(LinearGradient(colors: [Color.white, Color(red: 0.66, green: 0.53, blue: 1)], startPoint: .top, endPoint: .bottom))
                        .frame(width: 66, height: 66)
                        .background(IndiePalette.primary.opacity(0.12), in: RoundedRectangle(cornerRadius: 20))
                        .overlay(RoundedRectangle(cornerRadius: 20).stroke(IndiePalette.primary.opacity(0.30)))
                        .shadow(color: IndiePalette.primary.opacity(0.26), radius: 22)
                        .padding(.top, 12)

                    Text(stageTitle).font(.system(size: 25, weight: .semibold, design: .rounded))

                    Text(stageDescription)
                        .font(.system(size: 15.5))
                        .foregroundStyle(IndiePalette.secondaryText)
                        .multilineTextAlignment(.center)
                        .lineSpacing(5)
                        .frame(maxWidth: 610)

                    readinessPill.padding(.top, 4)

                    Button(action: primaryAction) {
                        HStack(spacing: 12) {
                            if model.isWorking { ProgressView().controlSize(.small).tint(.white) }
                            else { Image(systemName: primaryIcon).font(.system(size: 16, weight: .bold)) }
                            Text(primaryTitle).font(.system(size: 17, weight: .semibold))
                            Spacer(minLength: 8)
                            Image(systemName: "arrow.right").font(.system(size: 15, weight: .bold))
                        }
                        .padding(.horizontal, 22)
                        .frame(width: 360, height: 58)
                    }
                    .buttonStyle(IndiePrimaryButtonStyle())
                    .disabled(model.isWorking || systemBlocked)
                    .accessibilityHint(primaryHint)
                    .padding(.top, 12)

                    HStack(spacing: 6) {
                        Image(systemName: model.isWorking ? "arrow.down.circle" : "clock")
                        Text(model.isWorking ? model.status : durationText)
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(IndiePalette.secondaryText)
                    .frame(minHeight: 20)
                }

                Spacer(minLength: 54)
                NextStepStrip(stage: stage, showAdvanced: showAdvanced).padding(.bottom, 28)
            }
            .frame(maxWidth: 1040, minHeight: 690)
            .padding(.horizontal, 36)
            .frame(maxWidth: .infinity)
        }
    }

    private var readinessPill: some View {
        HStack(spacing: 9) {
            Image(systemName: systemBlocked ? "xmark.circle.fill" : "checkmark.circle.fill")
                .foregroundStyle(systemBlocked ? .orange : IndiePalette.green)
            Text(readinessText)
        }
        .font(.system(size: 13.5, weight: .medium))
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(IndiePalette.surface, in: Capsule())
        .overlay(Capsule().stroke(IndiePalette.border))
    }

    private var systemBlocked: Bool { model.systemReport.map { !$0.isSupported } ?? false }
    private var readinessText: String {
        if systemBlocked { return "环境检查未通过，请查看高级设置" }
        return "已检测到 \(model.systemReport?.chip ?? "Apple Silicon") · Rosetta 2 已就绪"
    }
    private var stageIcon: String {
        switch stage { case .environment: "shield.checkered"; case .steam: "arrow.down.app"; case .game: "gamecontroller"; case .ready: "checkmark.seal" }
    }
    private var stageTitle: String {
        switch stage { case .environment: "准备游戏环境"; case .steam: "安装 Windows 版 Steam"; case .game: "从 Steam 安装第一个游戏"; case .ready: "你的游戏已经准备好" }
    }
    private var stageDescription: String {
        switch stage {
        case .environment: "Indie 会自动下载并验证运行游戏所需的开源兼容组件。\n不会安装 Windows，也不会修改系统安全设置。"
        case .steam: "环境已经准备完成。接下来 Indie 会从 Valve 官方地址下载并打开 Steam 安装程序，你只需完成安装。"
        case .game: "打开 Steam，登录你的账户，在“游戏库”中选择一款 Windows 游戏并点击“安装”。安装完成后回到 Indie 扫描游戏。"
        case .ready: "已发现 \(model.steamGames.count) 个 Steam 游戏。你可以从游戏库直接启动，Indie 会自动选择合适的图形兼容方案。"
        }
    }
    private var primaryTitle: String {
        switch stage { case .environment: "一键准备环境"; case .steam: "安装 Steam"; case .game: "打开 Steam 安装游戏"; case .ready: "前往游戏库" }
    }
    private var primaryIcon: String {
        switch stage { case .environment: "sparkles"; case .steam: "arrow.down.app.fill"; case .game: "play.rectangle.fill"; case .ready: "gamecontroller.fill" }
    }
    private var primaryHint: String {
        switch stage {
        case .environment: "下载并验证 Wine 游戏运行环境"
        case .steam: "从 Valve 官方地址下载并打开 Steam 安装程序"
        case .game: "打开 Windows 版 Steam，以便登录并安装游戏"
        case .ready: "查看已经安装的 Steam 和本地游戏"
        }
    }
    private var durationText: String {
        switch stage {
        case .environment: "首次下载约 190 MB · 大约 3–8 分钟"
        case .steam: "下载后会出现 Steam 安装窗口"
        case .game: "游戏安装由 Steam 完成"
        case .ready: "环境、Steam 与游戏均已就绪"
        }
    }
    private func primaryAction() {
        switch stage {
        case .environment: Task { await model.prepareEnvironment() }
        case .steam: Task { await model.installSteam() }
        case .game: Task { await model.launchSteam() }
        case .ready: openLibrary()
        }
    }
}

private struct SetupProgressHeader: View {
    let stage: SetupStage
    var body: some View {
        HStack(spacing: 14) {
            progressItem(number: 1, title: "准备环境")
            connector(after: 1)
            progressItem(number: 2, title: "安装 Steam")
            connector(after: 2)
            progressItem(number: 3, title: "选择游戏")
        }
        .frame(maxWidth: 700)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("设置进度，第 \(min(stage.rawValue, 3)) 步，共 3 步")
    }
    private func progressItem(number: Int, title: String) -> some View {
        let current = stage.rawValue == number
        let complete = stage.rawValue > number
        return HStack(spacing: 10) {
            ZStack {
                Circle().fill(current ? IndiePalette.primary : complete ? IndiePalette.green.opacity(0.15) : IndiePalette.surface)
                Circle().stroke(current ? Color.white.opacity(0.55) : complete ? IndiePalette.green.opacity(0.55) : IndiePalette.border, lineWidth: 1.2)
                if complete { Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(IndiePalette.green) }
                else { Text("\(number)").font(.system(size: 13, weight: .semibold)).foregroundStyle(current ? .white : IndiePalette.secondaryText) }
            }
            .frame(width: 36, height: 36)
            .shadow(color: current ? IndiePalette.primary.opacity(0.55) : .clear, radius: 12)
            Text(title).font(.system(size: 14, weight: current ? .semibold : .medium)).foregroundStyle(current || complete ? Color.white : IndiePalette.secondaryText)
        }
    }
    private func connector(after number: Int) -> some View {
        Rectangle().fill(stage.rawValue > number ? IndiePalette.primary.opacity(0.75) : IndiePalette.border).frame(maxWidth: 86, maxHeight: 1)
    }
}

private struct NextStepStrip: View {
    let stage: SetupStage
    let showAdvanced: () -> Void
    var body: some View {
        HStack(spacing: 18) {
            Group {
                if stage == .ready {
                    Image(systemName: "play.circle")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(LinearGradient(colors: [Color.white, IndiePalette.blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                } else {
                    SteamLogoAsset()
                }
            }
            .frame(width: 104, height: 58)
            .background(Color.black.opacity(0.20), in: RoundedRectangle(cornerRadius: 13))
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.system(size: 16, weight: .semibold))
                Text(detail).font(.system(size: 13.5)).foregroundStyle(IndiePalette.secondaryText)
            }
            Spacer()
            Button("了解详情") { showAdvanced() }.buttonStyle(.bordered)
            Button("高级设置", systemImage: "chevron.right") { showAdvanced() }.buttonStyle(.plain).foregroundStyle(IndiePalette.secondaryText)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .background(IndiePalette.surface, in: RoundedRectangle(cornerRadius: 17))
        .overlay(RoundedRectangle(cornerRadius: 17).stroke(IndiePalette.border))
    }
    private var title: String {
        switch stage { case .environment: "接下来：安装并登录 Steam"; case .steam: "安装完成后：登录 Steam"; case .game: "在 Steam 中选择并安装游戏"; case .ready: "现在可以开始游戏" }
    }
    private var detail: String {
        switch stage {
        case .environment: "环境准备完成后，Indie 将为你打开官方 Steam 安装程序。"
        case .steam: "Indie 不会读取或保存你的 Steam 账户和密码。"
        case .game: "安装完成后返回 Indie，游戏会自动出现在游戏库。"
        case .ready: "需要更换图形兼容方案时，可在高级设置中调整。"
        }
    }
}

private struct SteamLogoAsset: View {
    var body: some View {
        if let url = Bundle.module.url(forResource: "steam-logo", withExtension: "svg"),
           let image = NSImage(contentsOf: url) {
            Image(nsImage: image).resizable().scaledToFit().padding(.horizontal, 16).accessibilityLabel("Steam")
        } else {
            Image(systemName: "arrow.down.app").foregroundStyle(IndiePalette.blue).accessibilityLabel("Steam")
        }
    }
}

private struct IndiePrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .background(
                LinearGradient(
                    colors: configuration.isPressed ? [IndiePalette.primary.opacity(0.78), IndiePalette.blue.opacity(0.78)] : [Color(red: 0.56, green: 0.29, blue: 1.0), Color(red: 0.10, green: 0.54, blue: 1.0)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ), in: RoundedRectangle(cornerRadius: 16)
            )
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.38), lineWidth: 1))
            .shadow(color: IndiePalette.primary.opacity(configuration.isPressed ? 0.22 : 0.44), radius: configuration.isPressed ? 12 : 22, y: 7)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

struct LibraryView: View {
    @EnvironmentObject private var model: IndieAppModel
    let returnToStart: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("游戏库").font(.system(size: 34, weight: .bold, design: .rounded))
                    Text("从 Steam 安装游戏，或直接导入本地 Windows 程序。").foregroundStyle(IndiePalette.secondaryText)
                }
                Spacer()
                Button("扫描 Steam", systemImage: "arrow.clockwise") { model.rescanSteam() }.disabled(model.steamExecutable == nil || model.isWorking)
                Button("导入本地游戏", systemImage: "plus") { chooseExecutable() }.buttonStyle(.borderedProminent)
            }
            if model.isWorking {
                HStack(spacing: 10) { ProgressView().controlSize(.small); Text(model.status) }.font(.system(size: 13.5)).foregroundStyle(IndiePalette.secondaryText)
            }
            if model.games.isEmpty && model.steamGames.isEmpty { emptyState }
            else {
                ScrollView {
                    VStack(spacing: 20) {
                        if !model.steamGames.isEmpty { steamSection }
                        if !model.games.isEmpty { localSection }
                    }
                }
            }
        }
        .padding(34)
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "gamecontroller").font(.system(size: 42, weight: .light)).foregroundStyle(IndiePalette.primary)
            Text("还没有安装游戏").font(.system(size: 22, weight: .semibold))
            Text(emptyDescription).multilineTextAlignment(.center).foregroundStyle(IndiePalette.secondaryText)
            Button(emptyButtonTitle, systemImage: emptyButtonIcon) { emptyAction() }.buttonStyle(.borderedProminent).controlSize(.large)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var steamSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Steam 游戏").font(.system(size: 16, weight: .semibold)).padding(18)
            Divider().overlay(IndiePalette.border)
            ForEach(model.steamGames) { game in
                HStack(spacing: 14) {
                    Image(systemName: "gamecontroller.fill").foregroundStyle(IndiePalette.primary).frame(width: 42, height: 42).background(IndiePalette.surface, in: RoundedRectangle(cornerRadius: 11))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(game.name).font(.system(size: 15, weight: .semibold))
                        Text("Steam 游戏 · 版本 \(game.buildID ?? "未知") · \(model.d3dMetalRuntimeAvailable ? "GPTK 4 / D3DMetal" : "需要 GPTK 4")").font(.system(size: 12.5)).foregroundStyle(IndiePalette.secondaryText)
                    }
                    Spacer()
                    if model.d3dMetalRuntimeAvailable {
                        Button("智能启动", systemImage: "play.fill") { Task { await model.launchSteamGame(game) } }
                            .disabled(model.isWorking)
                    } else {
                        Button("升级 GPTK 4", systemImage: "arrow.down.circle") {
                            model.startGPTKSetup()
                        }
                    }
                    Menu {
                        Button("通过 Steam 启动", systemImage: "gamecontroller") {
                            Task { await model.launchSteam(appID: game.appID) }
                        }
                    } label: { Image(systemName: "ellipsis") }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .disabled(model.isWorking)
                }
                .padding(.horizontal, 18).padding(.vertical, 13)
                if game.id != model.steamGames.last?.id { Divider().overlay(IndiePalette.border).padding(.leading, 72) }
            }
        }
        .background(IndiePalette.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(IndiePalette.border))
    }

    private var localSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("本地游戏").font(.system(size: 16, weight: .semibold)).padding(18)
            Divider().overlay(IndiePalette.border)
            ForEach(model.games) { game in
                HStack(spacing: 14) {
                    Image(systemName: "app.dashed").foregroundStyle(IndiePalette.blue).frame(width: 42, height: 42).background(IndiePalette.surface, in: RoundedRectangle(cornerRadius: 11))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(game.displayName).font(.system(size: 15, weight: .semibold))
                        Text("\(architectureName(game.analysis.architecture)) · \(directXName(game.analysis.directX))").font(.system(size: 12.5)).foregroundStyle(IndiePalette.secondaryText)
                    }
                    Spacer()
                    if game.analysis.antiCheat == .kernel { Label("反作弊不兼容", systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange) }
                    else { Button("运行", systemImage: "play.fill") { Task { await model.play(game) } }.disabled(model.isWorking) }
                }
                .padding(.horizontal, 18).padding(.vertical, 13)
            }
        }
        .background(IndiePalette.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(IndiePalette.border))
    }

    private var emptyDescription: String {
        if !model.environmentReady { return "请先回到“开始”页面，一键准备游戏环境。" }
        if model.steamExecutable == nil { return "环境已经就绪，下一步安装 Windows 版 Steam。" }
        return "打开 Steam 登录后，选择游戏并点击安装。完成后回到这里扫描游戏库。"
    }
    private var emptyButtonTitle: String {
        if !model.environmentReady { return "返回开始" }
        if model.steamExecutable == nil { return "安装 Steam" }
        return "打开 Steam 安装游戏"
    }
    private var emptyButtonIcon: String {
        if !model.environmentReady { return "arrow.left" }
        if model.steamExecutable == nil { return "arrow.down.app" }
        return "play.rectangle"
    }
    private func emptyAction() {
        if !model.environmentReady { returnToStart() }
        else if model.steamExecutable == nil { Task { await model.installSteam() } }
        else { Task { await model.launchSteam() } }
    }
    private func chooseExecutable() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.exe, .item]; panel.allowsMultipleSelection = false; panel.prompt = "导入"
        if panel.runModal() == .OK, let url = panel.url { Task { await model.importExecutable(url) } }
    }
    private func architectureName(_ architecture: CPUArchitecture) -> String {
        switch architecture { case .i386: "32 位 Intel"; case .x86_64: "64 位 Intel"; case .arm64: "64 位 ARM"; case .arm64ec: "ARM64EC"; case .unknown: "未知架构" }
    }
    private func directXName(_ version: DirectXVersion) -> String { version == .none ? "未检测到 DirectX" : version.rawValue.uppercased() }
}

struct AdvancedSettingsView: View {
    @EnvironmentObject private var model: IndieAppModel
    @Environment(\.dismiss) private var dismiss
    @State private var section = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("高级设置").font(.system(size: 24, weight: .bold, design: .rounded))
                    Text("管理兼容组件与查看诊断信息").font(.system(size: 13)).foregroundStyle(.secondary)
                }
                Spacer()
                Button("完成") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(24)
            Picker("", selection: $section) {
                Text("运行环境").tag(0); Text("环境诊断").tag(1); Text("偏好设置").tag(2)
            }
            .pickerStyle(.segmented).padding(.horizontal, 24).padding(.bottom, 18)
            Divider()
            Group {
                if section == 0 { RuntimeSettingsContent() }
                else if section == 1 { DiagnosticsContent() }
                else { PreferencesContent() }
            }
        }
        .preferredColorScheme(.dark)
        .background(IndiePalette.canvas)
    }
}

private struct RuntimeSettingsContent: View {
    @EnvironmentObject private var model: IndieAppModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                advancedSection(title: "Wine 运行环境", detail: "Indie 自行从 LGPL 源码构建 Wine 11 新 WoW64 运行时；不封装或分发 CrossOver 应用。") {
                    ForEach(model.wineRuntimes) { runtime in componentRow(name: runtime.manifest.displayName, status: "已安装") }
                    HStack {
                        Button("自动安装最新版本") { Task { await model.prepareEnvironment() } }.buttonStyle(.borderedProminent)
                        Button("导入本地 Wine") { chooseWine() }
                    }
                }
                advancedSection(title: "Apple D3DMetal", detail: "Apple 官方 GPTK 中的 DirectX 11/12 图形转换组件，适合现代 DX12 游戏。") {
                    ForEach(model.d3dMetal, id: \.root) { component in componentRow(name: "D3DMetal \(component.version)", status: "Apple 签名已验证") }
                    if let version = model.gptkRuntimeVersion {
                        componentRow(name: "完整 GPTK 运行时 \(version)", status: model.gptkNeedsUpdate ? "需要升级到 GPTK 4" : "可用于游戏")
                    }
                    HStack {
                        if model.isGPTKSetupRunning {
                            Button("取消等待", role: .cancel) { model.cancelGPTKSetup() }
                        } else {
                            Button("一键安装 GPTK 4") { model.startGPTKSetup() }.buttonStyle(.borderedProminent)
                        }
                        Button("导入 GPTK 镜像") { chooseGPTK() }.buttonStyle(.borderedProminent)
                    }
                    if model.isGPTKSetupRunning {
                        HStack(spacing: 8) { ProgressView().controlSize(.small); Text(model.status) }
                            .font(.system(size: 12.5)).foregroundStyle(IndiePalette.secondaryText)
                    }
                }
                advancedSection(title: "开源图形组件", detail: "DXMT 用于 DirectX 10/11；DXVK 与 VKD3D 作为兼容回退或实验路径。") {
                    ForEach(model.rendererOverlays) { overlay in componentRow(name: "\(overlay.kind.rawValue.uppercased()) \(overlay.version)", status: "已导入") }
                    HStack {
                        Button("导入 DXMT") { chooseRenderer(.dxmt) }; Button("导入 DXVK") { chooseRenderer(.dxvk) }; Button("导入 VKD3D") { chooseRenderer(.vkd3d) }
                    }
                }
            }
            .padding(24)
        }
    }
    private func advancedSection<Content: View>(title: String, detail: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.system(size: 17, weight: .semibold)); Text(detail).font(.system(size: 13.5)).foregroundStyle(IndiePalette.secondaryText); content()
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(18)
        .background(IndiePalette.surface, in: RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).stroke(IndiePalette.border))
    }
    private func componentRow(name: String, status: String) -> some View {
        HStack { Image(systemName: "checkmark.circle.fill").foregroundStyle(IndiePalette.green); Text(name).font(.system(size: 13.5, weight: .medium)); Spacer(); Text(status).font(.system(size: 12.5)).foregroundStyle(IndiePalette.secondaryText) }
    }
    private func chooseGPTK() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = true; panel.allowsMultipleSelection = false; panel.allowedContentTypes = [.diskImage, .folder]; panel.prompt = "导入"
        if panel.runModal() == .OK, let url = panel.url { Task { await model.importGPTK(url) } }
    }
    private func chooseWine() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false; panel.prompt = "导入"
        if panel.runModal() == .OK, let url = panel.url { Task { await model.importWine(url) } }
    }
    private func chooseRenderer(_ kind: RendererKind) {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false; panel.prompt = "导入"
        if panel.runModal() == .OK, let url = panel.url { Task { await model.importRenderer(kind, from: url) } }
    }
}

private struct DiagnosticsContent: View {
    @EnvironmentObject private var model: IndieAppModel
    var body: some View {
        VStack(spacing: 0) {
            HStack { Text("这台 Mac").font(.system(size: 18, weight: .semibold)); Spacer(); Button("重新检查", systemImage: "arrow.clockwise") { Task { await model.refresh() } } }.padding(24)
            List(model.systemReport?.items ?? []) { item in
                HStack(spacing: 12) {
                    Image(systemName: item.severity == .pass ? "checkmark.circle.fill" : item.severity == .warning ? "exclamationmark.triangle.fill" : "xmark.octagon.fill").foregroundStyle(item.severity == .pass ? IndiePalette.green : item.severity == .warning ? .orange : .red)
                    VStack(alignment: .leading, spacing: 4) { Text(item.title).font(.system(size: 14, weight: .semibold)); Text(item.detail).font(.system(size: 13)).foregroundStyle(IndiePalette.secondaryText) }
                }.padding(.vertical, 5)
            }
            .scrollContentBackground(.hidden)
        }
    }
}

private struct PreferencesContent: View {
    @AppStorage("releaseChannel") private var releaseChannel = ReleaseChannel.stable.rawValue
    @AppStorage("metalHUD") private var metalHUD = false
    @AppStorage("metalFX") private var metalFX = false
    @AppStorage("metal4") private var metal4 = true
    var body: some View {
        Form {
            Picker("更新通道", selection: $releaseChannel) {
                Text("稳定版").tag(ReleaseChannel.stable.rawValue); Text("候选版").tag(ReleaseChannel.candidate.rawValue); Text("实验版").tag(ReleaseChannel.experimental.rawValue)
            }
            Toggle("启动游戏时显示 Apple Metal HUD", isOn: $metalHUD)
            Text("D3DMetal 游戏会在同一个 Indie Wine 11 + Steam 会话中显示 Apple 官方 FPS、GPU 时间、内存和帧间隔；非 D3DMetal 兼容回退不会显示该 HUD。")
                .font(.system(size: 12.5)).foregroundStyle(IndiePalette.secondaryText)
            Toggle("优先使用 Metal 4", isOn: $metal4)
            Text("GPTK 4 会在支持的 Apple GPU 与 macOS 上使用新的 Metal 4 提交路径；遇到个别游戏异常时可关闭并回退。")
                .font(.system(size: 12.5)).foregroundStyle(IndiePalette.secondaryText)
            Toggle("使用 MetalFX 兼容游戏的 DLSS", isOn: $metalFX)
            Text("需要 GPTK 4/D3DMetal，且仍需在游戏画面设置中开启 DLSS。Apple GPU 实际执行的是 MetalFX。")
                .font(.system(size: 12.5)).foregroundStyle(IndiePalette.secondaryText)
            Text("Indie 不收集遥测数据。兼容配方来自可审计的 Git 仓库。").font(.system(size: 12.5)).foregroundStyle(IndiePalette.secondaryText)
        }
        .formStyle(.grouped).padding(12)
    }
}

struct SettingsView: View {
    var body: some View { PreferencesContent().frame(width: 560, height: 380) }
}

private extension UTType {
    static let exe = UTType(filenameExtension: "exe") ?? .data
}
