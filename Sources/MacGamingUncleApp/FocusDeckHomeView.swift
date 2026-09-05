import IndieCatalog
import IndieCore
import SwiftUI

struct FocusDeckHomeView: View {
    @EnvironmentObject private var model: MacGamingUncleAppModel
    let openStore: (UInt64) -> Void
    @State private var selection: UInt64?
    @State private var settingsTarget: GameSettingsTarget?

    private var games: [SteamAccountGame] {
        Array(model.steamAccountGames.prefix(24))
    }

    var body: some View {
        GeometryReader { geometry in
            if let game = selectedGame ?? games.first {
                ScrollView {
                    VStack(spacing: 0) {
                        hero(game, height: max(480, min(590, geometry.size.height * 0.61)))
                        detailPanels(game)
                            .padding(.horizontal, 28).padding(.top, 18).padding(.bottom, 14)
                    }
                    .frame(minHeight: geometry.size.height)
                }
                .scrollIndicators(.hidden)
                .safeAreaInset(edge: .bottom, spacing: 0) { controllerHintBar }
            } else {
                emptyState
            }
        }
        .sheet(item: $settingsTarget) { target in
            GameSettingsView(target: target).environmentObject(model)
        }
        .onAppear { chooseInitialGame() }
        .onChange(of: model.steamAccountGames.map(\.appID)) { _, _ in chooseInitialGame() }
    }

    private func hero(_ game: SteamAccountGame, height: CGFloat) -> some View {
        ZStack(alignment: .bottom) {
            heroArtwork(game)
            .frame(maxWidth: .infinity, minHeight: height, maxHeight: height).clipped()

            LinearGradient(
                stops: [
                    .init(color: IndiePalette.canvas.opacity(0.94), location: 0),
                    .init(color: IndiePalette.canvas.opacity(0.36), location: 0.34),
                    .init(color: .clear, location: 0.68),
                ],
                startPoint: .leading, endPoint: .trailing
            )
            LinearGradient(colors: [.clear, IndiePalette.canvas.opacity(0.12), IndiePalette.canvas], startPoint: .top, endPoint: .bottom)

            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 14) {
                    Text("最近游玩")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.white.opacity(0.72))
                    Text(game.name)
                        .font(.system(size: 46, weight: .bold, design: .rounded))
                        .tracking(-0.8).lineLimit(1)
                    HStack(spacing: 20) {
                        Label(playtime(game.playtimeMinutes), systemImage: "clock")
                        if let date = game.lastPlayed {
                            Text("最近游玩：\(date.formatted(date: .abbreviated, time: .omitted))")
                        }
                    }
                    .font(.system(size: 14, weight: .medium)).foregroundStyle(Color.white.opacity(0.67))
                    HStack(spacing: 24) {
                        Label("兼容性优秀", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(IndiePalette.green)
                        Label(
                            model.steamSessionManager.state == .running ? "云存档已同步" : "Steam 待连接",
                            systemImage: model.steamSessionManager.state == .running ? "cloud.fill" : "cloud"
                        )
                        .foregroundStyle(Color.white.opacity(0.72))
                    }
                    .font(.system(size: 13, weight: .semibold))
                    HStack(spacing: 12) {
                        primaryAction(game)
                        Button("游戏设置", systemImage: "gearshape") { showSettings(game) }
                            .buttonStyle(FocusSecondaryButtonStyle())
                        Menu {
                            Button("商店页面", systemImage: "bag") { openStore(game.appID) }
                            Button("刷新游戏库", systemImage: "arrow.clockwise") { model.rescanSteam() }
                        } label: {
                            Image(systemName: "ellipsis").frame(width: 42)
                        }
                        .buttonStyle(FocusSecondaryButtonStyle())
                    }
                    .padding(.top, 2)
                }
                .padding(.leading, 58).padding(.top, 46)
                .frame(maxWidth: 650, alignment: .leading)

                Spacer(minLength: 28)
                gameCarousel
                    .padding(.horizontal, 58).padding(.bottom, 14)
            }
            .frame(height: height)
        }
        .frame(height: height)
    }

    private var gameCarousel: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 14) {
                ForEach(games) { game in
                    Button { withAnimation(.easeOut(duration: 0.2)) { selection = game.appID } } label: {
                        ZStack(alignment: .bottomLeading) {
                            AsyncImage(url: game.coverImageURL) { phase in
                                if case .success(let image) = phase {
                                    image.resizable().scaledToFill()
                                } else {
                                    AsyncImage(url: game.headerImageURL) { image in
                                        image.resizable().scaledToFill()
                                    } placeholder: {
                                        IndiePalette.surfaceStrong.overlay(
                                            Image(systemName: "gamecontroller.fill")
                                                .font(.system(size: 24)).foregroundStyle(IndiePalette.secondaryText)
                                        )
                                    }
                                }
                            }
                            .frame(width: 132, height: 186).clipped()
                            LinearGradient(colors: [.clear, Color.black.opacity(0.76)], startPoint: .center, endPoint: .bottom)
                            Text(game.name).font(.system(size: 11.5, weight: .semibold)).lineLimit(2)
                                .padding(9)
                        }
                        .frame(width: 132, height: 186)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(
                            selection == game.appID ? IndiePalette.blue : Color.white.opacity(0.14),
                            lineWidth: selection == game.appID ? 2 : 1
                        ))
                        .shadow(color: selection == game.appID ? IndiePalette.blue.opacity(0.34) : .clear, radius: 12)
                        .scaleEffect(selection == game.appID ? 1.035 : 1)
                    }
                    .buttonStyle(.plain).accessibilityLabel(game.name)
                }
            }
            .padding(.vertical, 10)
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder
    private func primaryAction(_ game: SteamAccountGame) -> some View {
        if let installed = model.steamGames.first(where: { $0.appID == game.appID }) {
            Button { Task { await model.launchSteamGame(installed) } } label: {
                HStack(spacing: 8) { UncleAppleMark(size: 24); Text("开始游戏") }
            }
            .buttonStyle(FocusPrimaryButtonStyle()).disabled(model.isWorking)
        } else {
            Button("安装游戏", systemImage: "arrow.down.circle.fill") {
                Task { await model.installSteamGame(appID: game.appID) }
            }
            .buttonStyle(FocusPrimaryButtonStyle()).disabled(model.isWorking)
        }
    }

    private func detailPanels(_ game: SteamAccountGame) -> some View {
        HStack(alignment: .top, spacing: 14) {
            FocusPanel(title: "最近活动", icon: "clock.arrow.circlepath") {
                activityRow("上次运行", value: game.lastPlayed?.formatted(date: .abbreviated, time: .shortened) ?? "尚未运行")
                if let activity = model.steamActivities[game.appID] {
                    ForEach(Array(activity.recentAchievements.prefix(2))) { achievement in
                        achievementActivityRow(achievement)
                    }
                }
                Button("查看商店动态", systemImage: "newspaper") { openStore(game.appID) }
                    .buttonStyle(.borderless).foregroundStyle(Color.white.opacity(0.76))
            }

            FocusPanel(title: "成就", icon: "trophy") {
                if let activity = model.steamActivities[game.appID], activity.total > 0 {
                    HStack {
                        Text("\(activity.achieved) / \(activity.total) 已解锁")
                        Spacer()
                        Text("\(Int(activity.progress * 100))%")
                    }.font(.caption).foregroundStyle(IndiePalette.secondaryText)
                    ProgressView(value: activity.progress).tint(IndiePalette.blue)
                    HStack(spacing: 7) {
                        ForEach(activity.recentAchievements.prefix(6)) { achievement in
                            AsyncImage(url: achievement.imageURL) { image in image.resizable().scaledToFill() }
                            placeholder: { IndiePalette.surfaceStrong }
                                .frame(width: 42, height: 42).clipShape(RoundedRectangle(cornerRadius: 7))
                                .help(achievement.name)
                        }
                    }
                } else {
                    Text("运行游戏后，Steam 成就进度会显示在这里。")
                        .font(.system(size: 13)).foregroundStyle(IndiePalette.secondaryText)
                }
                Text("成就数据来自本机 Steam 缓存")
                    .font(.caption2).foregroundStyle(IndiePalette.secondaryText)
            }

            FocusPanel(title: "兼容性与设置", icon: "switch.2") {
                let configuration = model.configuration(appID: game.appID)
                activityRow("兼容层", value: rendererName(configuration.preferredRenderer))
                activityRow("分辨率", value: configuration.virtualDesktop?.label ?? "自动（推荐）")
                activityRow("Metal HUD", value: overrideName(configuration.metalHUD))
                activityRow("手柄", value: configuration.controllerMode == .enhanced ? "增强兼容" : "自动")
                Button("管理游戏设置", systemImage: "slider.horizontal.3") { showSettings(game) }
                    .buttonStyle(.bordered).controlSize(.small).frame(maxWidth: .infinity)
            }
        }
        .frame(height: 220)
    }

    private var controllerHintBar: some View {
        HStack {
            Label("菜单", systemImage: "circle.circle")
            Spacer()
            if !model.controllerManager.devices.isEmpty {
                Text("A 选择").fontWeight(.semibold)
                Text("B 返回").fontWeight(.semibold)
            } else {
                Text(model.status.isEmpty ? "Mac Gaming Uncle 已就绪" : model.status)
            }
        }
        .font(.system(size: 12.5)).foregroundStyle(Color.white.opacity(0.65))
        .padding(.horizontal, 30).frame(height: 42)
        .background(IndiePalette.topBar)
        .overlay(alignment: .top) { Rectangle().fill(IndiePalette.border).frame(height: 1) }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("等待 Steam 游戏库", systemImage: "gamecontroller")
        } description: {
            Text("登录 Windows Steam 后，最近游戏会出现在主页。")
        } actions: {
            Button("打开 Steam") { Task { await model.launchSteam() } }.buttonStyle(.borderedProminent)
        }
    }

    private var selectedGame: SteamAccountGame? {
        selection.flatMap { id in model.steamAccountGames.first(where: { $0.appID == id }) }
    }

    @ViewBuilder
    private func heroArtwork(_ game: SteamAccountGame) -> some View {
        AsyncImage(url: game.pageBackgroundURL) { phase in
            if case .success(let image) = phase {
                image.resizable().scaledToFill()
            } else {
                AsyncImage(url: game.heroImageURL) { image in
                    image.resizable().scaledToFill()
                } placeholder: { IndiePalette.canvas }
            }
        }
    }

    private func chooseInitialGame() {
        guard selection == nil || !model.steamAccountGames.contains(where: { $0.appID == selection }) else { return }
        selection = model.steamAccountGames.first(where: \.isInstalled)?.appID ?? model.steamAccountGames.first?.appID
    }

    private func showSettings(_ game: SteamAccountGame) {
        let configuration = model.configuration(appID: game.appID)
        settingsTarget = .init(
            id: configuration.id,
            name: game.name,
            detail: "Steam AppID \(game.appID)",
            configuration: configuration
        )
    }

    private func activityRow(_ title: String, value: String) -> some View {
        HStack { Text(title).foregroundStyle(IndiePalette.secondaryText); Spacer(); Text(value) }
            .font(.system(size: 12.5, weight: .medium))
    }

    private func achievementActivityRow(_ achievement: SteamAchievement) -> some View {
        HStack(spacing: 9) {
            AsyncImage(url: achievement.imageURL) { image in image.resizable().scaledToFill() }
            placeholder: { IndiePalette.surfaceStrong }
                .frame(width: 30, height: 30).clipShape(RoundedRectangle(cornerRadius: 5))
            VStack(alignment: .leading, spacing: 2) {
                Text(achievement.name).font(.system(size: 11.5, weight: .semibold)).lineLimit(1)
                Text(achievement.unlockedAt?.formatted(date: .abbreviated, time: .omitted) ?? "最近解锁")
                    .font(.caption2).foregroundStyle(IndiePalette.secondaryText)
            }
        }
    }

    private func rendererName(_ renderer: RendererKind?) -> String {
        renderer?.rawValue.uppercased() ?? (model.d3dMetalRuntimeAvailable ? "D3DMetal 4" : "自动")
    }

    private func overrideName(_ value: GameSettingOverride) -> String {
        switch value { case .inherit: "跟随全局"; case .enabled: "已开启"; case .disabled: "已关闭" }
    }

    private func playtime(_ minutes: Int) -> String {
        if minutes <= 0 { return "尚未游玩" }
        if minutes < 60 { return "\(minutes) 分钟" }
        return String(format: "%.1f 小时", Double(minutes) / 60)
    }
}

private struct FocusPanel<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content

    init(title: String, icon: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            Label(title, systemImage: icon).font(.system(size: 14, weight: .semibold))
            Divider().overlay(IndiePalette.border)
            content
        }
        .padding(16).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(IndiePalette.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(IndiePalette.border))
    }
}

private struct FocusPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
            .padding(.horizontal, 24).frame(height: 46)
            .background(IndiePalette.blue.opacity(configuration.isPressed ? 0.76 : 1), in: RoundedRectangle(cornerRadius: 10))
            .shadow(color: IndiePalette.blue.opacity(0.25), radius: 14, y: 5)
    }
}

private struct FocusSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.white.opacity(0.86))
            .padding(.horizontal, 16).frame(height: 46)
            .background(IndiePalette.surfaceStrong.opacity(configuration.isPressed ? 0.7 : 1), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(IndiePalette.border))
    }
}
