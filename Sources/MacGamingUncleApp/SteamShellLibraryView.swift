import IndieCatalog
import IndieCore
import SwiftUI

private enum SteamLibraryFilter: String, CaseIterable {
    case all, installed, recent
}

struct SteamShellLibraryView: View {
    @EnvironmentObject private var model: MacGamingUncleAppModel
    let openStore: (UInt64) -> Void
    @State private var search = ""
    @State private var filter: SteamLibraryFilter = .all
    @State private var selection: UInt64?
    @State private var settingsTarget: GameSettingsTarget?

    private var games: [SteamAccountGame] {
        model.steamAccountGames.filter { game in
            let matchesSearch = search.isEmpty || game.name.localizedCaseInsensitiveContains(search)
            let matchesFilter = switch filter {
            case .all: true
            case .installed: game.isInstalled
            case .recent: game.lastPlayed != nil
            }
            return matchesSearch && matchesFilter
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            libraryHeader
            Divider().overlay(IndiePalette.border)
            if model.steamAccountGames.isEmpty {
                emptyState
            } else {
                HStack(spacing: 0) {
                    gameList.frame(width: 285)
                    Divider().overlay(IndiePalette.border)
                    if let game = selectedGame {
                        gameDetail(game)
                    } else {
                        ContentUnavailableView(L("选择一个游戏"), systemImage: "gamecontroller")
                    }
                }
            }
        }
        .sheet(item: $settingsTarget) { target in
            GameSettingsView(target: target).environmentObject(model)
        }
        .onAppear {
            if selection == nil { selection = games.first?.appID }
        }
        .onChange(of: games.map(\.appID)) { _, ids in
            if selection.map(ids.contains) != true { selection = ids.first }
        }
    }

    private var libraryHeader: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(L("游戏库")).font(.system(size: 26, weight: .bold, design: .rounded))
                Text(L("\(model.steamAccountGames.count) 款账户游戏 · \(model.steamGames.filter { $0.appID != 228980 }.count) 款已安装"))
                    .font(.caption).foregroundStyle(IndiePalette.secondaryText)
            }
            SteamSessionIndicator(manager: model.steamSessionManager)
            Spacer()
            Picker("", selection: $filter) {
                Text(L("全部")).tag(SteamLibraryFilter.all)
                Text(L("已安装")).tag(SteamLibraryFilter.installed)
                Text(L("最近玩过")).tag(SteamLibraryFilter.recent)
            }
            .pickerStyle(.segmented).frame(width: 250)
            TextField(L("搜索游戏库"), text: $search).textFieldStyle(.roundedBorder).frame(width: 210)
            Button(L("刷新"), systemImage: "arrow.clockwise") { model.rescanSteam() }
        }
        .padding(.horizontal, 24).frame(height: 78)
        .background(IndiePalette.sidebar.opacity(0.82))
    }

    private var gameList: some View {
        List(games, selection: $selection) { game in
            HStack(spacing: 10) {
                AsyncImage(url: game.headerImageURL) { phase in
                    if case .success(let image) = phase { image.resizable().scaledToFill() }
                    else { Rectangle().fill(IndiePalette.surfaceStrong).overlay(Image(systemName: "gamecontroller")) }
                }
                .frame(width: 54, height: 31).clipShape(RoundedRectangle(cornerRadius: 4))
                VStack(alignment: .leading, spacing: 3) {
                    Text(game.name).lineLimit(1).font(.system(size: 13.5, weight: .medium))
                    Text(model.steamDownloads.first(where: { $0.appID == game.appID })?.installationLabel
                         ?? (game.isInstalled ? L("已安装") : playtime(game.playtimeMinutes)))
                        .font(.caption2).foregroundStyle(game.isInstalled ? IndiePalette.green : IndiePalette.secondaryText)
                }
            }
            .padding(.vertical, 4).tag(game.appID)
        }
        .listStyle(.sidebar).scrollContentBackground(.hidden)
        .background(IndiePalette.sidebar.opacity(0.58))
    }

    private func gameDetail(_ game: SteamAccountGame) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                ZStack(alignment: .bottomLeading) {
                    AsyncImage(url: game.headerImageURL) { phase in
                        if case .success(let image) = phase {
                            image.resizable().scaledToFill()
                        } else {
                            LinearGradient(colors: [IndiePalette.primary.opacity(0.5), IndiePalette.blue.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 300, maxHeight: 360).clipped()
                    LinearGradient(colors: [.clear, IndiePalette.canvas.opacity(0.98)], startPoint: .center, endPoint: .bottom)
                    VStack(alignment: .leading, spacing: 9) {
                        Text(game.name).font(.system(size: 34, weight: .bold, design: .rounded)).shadow(radius: 8)
                        HStack(spacing: 15) {
                            Label(playtime(game.playtimeMinutes), systemImage: "clock")
                            if let date = game.lastPlayed { Label(L("上次游玩 \(AppLanguage.date(date))"), systemImage: "calendar") }
                        }
                        .font(.caption).foregroundStyle(Color.white.opacity(0.72))
                    }
                    .padding(28)
                }
                HStack(spacing: 12) {
                    if let pending = model.steamDownloads.first(where: { $0.appID == game.appID }) {
                        SteamInstallProgress(game: pending)
                    } else if let installed = model.steamGames.first(where: { $0.appID == game.appID }) {
                        Button { Task { await model.launchSteamGame(installed) } } label: {
                            GameLaunchButtonLabel(state: model.gameLaunchStates[game.appID] ?? .idle)
                        }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                        .disabled(model.isWorking || model.gameLaunchStates[game.appID]?.blocksLaunch == true)
                        Button(L("游戏设置"), systemImage: "slider.horizontal.3") { showSettings(installed) }
                    } else {
                        Button(L("安装"), systemImage: "arrow.down.circle.fill") {
                            Task { await model.installSteamGame(appID: game.appID) }
                        }
                        .buttonStyle(.borderedProminent).controlSize(.large).disabled(model.isWorking)
                    }
                    Button(L("商店页面"), systemImage: "bag") { openStore(game.appID) }
                    Spacer()
                    Text("AppID \(game.appID)").font(.caption).foregroundStyle(IndiePalette.secondaryText)
                }
                .padding(.horizontal, 28)
                if let description = game.description, !description.isEmpty {
                    Text(description).font(.system(size: 15)).lineSpacing(5)
                        .foregroundStyle(Color.white.opacity(0.74)).padding(.horizontal, 28)
                }
                if model.isWorking {
                    HStack { ProgressView().controlSize(.small); Text(model.status) }
                        .font(.caption).foregroundStyle(IndiePalette.secondaryText).padding(.horizontal, 28)
                }
            }
        }
        .background(IndiePalette.canvas)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "books.vertical").font(.system(size: 42)).foregroundStyle(IndiePalette.primary)
            Text(L("登录 Steam 后，这里会显示你的游戏库")).font(.system(size: 20, weight: .semibold))
            Text(L("Mac Gaming Uncle 从本机 Steam 缓存读取游戏与游玩记录，不上传账户数据。"))
                .foregroundStyle(IndiePalette.secondaryText)
            Button(L("打开 Steam 登录"), systemImage: "person.crop.circle") { Task { await model.launchSteam() } }
                .buttonStyle(.borderedProminent).controlSize(.large)
            Spacer()
        }.frame(maxWidth: .infinity)
    }

    private var selectedGame: SteamAccountGame? {
        selection.flatMap { id in model.steamAccountGames.first(where: { $0.appID == id }) }
    }

    private func playtime(_ minutes: Int) -> String {
        if minutes <= 0 { return L("尚未游玩") }
        if minutes < 60 { return L("\(minutes) 分钟") }
        return String(format: L("%.1f 小时"), Double(minutes) / 60)
    }

    private func showSettings(_ game: SteamGame) {
        let configuration = model.configuration(for: game)
        settingsTarget = .init(
            id: configuration.id, name: game.name,
            detail: "Steam AppID \(game.appID)", configuration: configuration
        )
    }
}
