import IndieCore
import IndieCatalog
import SwiftUI

private enum NativeStoreSection: String, CaseIterable {
    case featured, topSellers, specials, newReleases
}

struct NativeSteamStoreView: View {
    @EnvironmentObject private var model: MacGamingUncleAppModel
    @State private var selection: NativeStoreSection = .featured
    @State private var selectedItem: SteamStoreItem?
    @State private var search = ""
    @State private var securePage: SecurePageTarget?

    private var catalog: SteamStoreCatalog? { model.steamStoreCatalog }
    private var displayItems: [SteamStoreItem] {
        if !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return model.steamStoreSearchResults
        }
        guard let catalog else { return [] }
        return switch selection {
        case .featured: Array((catalog.topSellers + catalog.specials).uniqued(by: \.id).prefix(24))
        case .topSellers: catalog.topSellers
        case .specials: catalog.specials
        case .newReleases: catalog.newReleases
        }
    }
    private var heroItem: SteamStoreItem? { selectedItem ?? displayItems.first }

    var body: some View {
        VStack(spacing: 0) {
            storeToolbar
            Divider().overlay(IndiePalette.border)
            if let heroItem {
                ScrollView {
                    VStack(alignment: .leading, spacing: 26) {
                        storeHero(heroItem)
                        storeSection(title: sectionTitle, items: displayItems)
                        if search.isEmpty, let catalog {
                            storeSection(title: L("特别优惠"), items: catalog.specials)
                            storeSection(title: L("新品推荐"), items: catalog.newReleases)
                        }
                    }
                    .padding(.bottom, 32)
                }
                .scrollIndicators(.hidden)
            } else if model.isSteamStoreLoading {
                VStack(spacing: 14) { ProgressView(); Text(L("正在载入 Steam 商店…")) }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView {
                    Label(L("商店暂时不可用"), systemImage: "wifi.exclamationmark")
                } description: {
                    Text(model.steamStoreError ?? L("无法取得 Steam 商店内容"))
                } actions: {
                    Button(L("重试")) { Task { await model.loadNativeSteamStore(force: true) } }
                }
            }
        }
        .background(IndiePalette.canvas)
        .task { await model.loadNativeSteamStore() }
        .onAppear { selectRequestedItem() }
        .onChange(of: model.steamStoreSelectedAppID) { _, _ in selectRequestedItem() }
        .onChange(of: displayItems.map(\.id)) { _, ids in
            if selectedItem.map({ ids.contains($0.id) }) != true {
                selectedItem = displayItems.first
            }
        }
        .sheet(item: $securePage) { target in
            SecureSteamPage(url: target.url).environmentObject(model)
        }
    }

    private var storeToolbar: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 3) {
                Text(L("商店")).font(.system(size: 26, weight: .bold, design: .rounded))
                Text(L("由 Steam 官方商店数据提供")).font(.caption).foregroundStyle(IndiePalette.secondaryText)
            }
            Picker("", selection: $selection) {
                Text(L("精选")).tag(NativeStoreSection.featured)
                Text(L("畅销")).tag(NativeStoreSection.topSellers)
                Text(L("优惠")).tag(NativeStoreSection.specials)
                Text(L("新品")).tag(NativeStoreSection.newReleases)
            }
            .pickerStyle(.segmented).frame(width: 300)
            Spacer()
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(IndiePalette.secondaryText)
                TextField(L("搜索 Steam 商店"), text: $search)
                    .textFieldStyle(.plain).onSubmit { Task { await model.searchNativeSteamStore(search) } }
                if !search.isEmpty {
                    Button { search = ""; model.steamStoreSearchResults = [] } label: {
                        Image(systemName: "xmark.circle.fill")
                    }.buttonStyle(.plain).foregroundStyle(IndiePalette.secondaryText)
                }
            }
            .padding(.horizontal, 12).frame(width: 280, height: 36)
            .background(IndiePalette.surface, in: RoundedRectangle(cornerRadius: 9))
            Button(L("搜索")) { Task { await model.searchNativeSteamStore(search) } }
                .buttonStyle(.borderedProminent).disabled(search.count < 2)
            Button { Task { await model.loadNativeSteamStore(force: true) } } label: {
                Image(systemName: "arrow.clockwise")
            }.buttonStyle(.plain).help(L("刷新商店"))
        }
        .padding(.horizontal, 28).frame(height: 76).background(IndiePalette.topBar.opacity(0.86))
    }

    private func storeHero(_ item: SteamStoreItem) -> some View {
        ZStack(alignment: .bottomLeading) {
            AsyncImage(url: URL(string: "https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/\(item.id)/page_bg_raw.jpg")) { phase in
                if case .success(let image) = phase {
                    image.resizable().scaledToFill()
                } else {
                    AsyncImage(url: item.imageURL) { image in image.resizable().scaledToFill() }
                    placeholder: { IndiePalette.surfaceStrong }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 350, maxHeight: 350).clipped()
            LinearGradient(
                stops: [
                    .init(color: IndiePalette.canvas.opacity(0.96), location: 0),
                    .init(color: IndiePalette.canvas.opacity(0.38), location: 0.46),
                    .init(color: IndiePalette.canvas.opacity(0.08), location: 1),
                ],
                startPoint: .leading, endPoint: .trailing
            )
            LinearGradient(colors: [.clear, IndiePalette.canvas.opacity(0.92)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 12) {
                Text(L("STEAM 精选")).font(.system(size: 12, weight: .bold)).foregroundStyle(IndiePalette.blue)
                Text(item.name).font(.system(size: 36, weight: .bold, design: .rounded)).lineLimit(2)
                priceView(item)
                HStack(spacing: 11) {
                    if let installed = model.steamGames.first(where: { $0.appID == item.id }) {
                        Button { Task { await model.launchSteamGame(installed) } } label: {
                            HStack(spacing: 8) { UncleAppleMark(size: 24); Text(L("开始游戏")) }
                        }
                            .buttonStyle(.borderedProminent).controlSize(.large)
                    } else {
                        Button(L("添加并安装"), systemImage: "arrow.down.circle.fill") {
                            Task { await model.installSteamGame(appID: item.id) }
                        }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                    }
                    Button(L("查看详情"), systemImage: "info.circle") { openSecurePage(item.id) }
                        .buttonStyle(.bordered).controlSize(.large)
                }
            }
            .padding(34).frame(maxWidth: 580, alignment: .leading)
        }
        .frame(height: 350).clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(IndiePalette.border))
        .padding(.horizontal, 28).padding(.top, 24)
    }

    private func storeSection(title: String, items: [SteamStoreItem]) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack { Text(title).font(.system(size: 19, weight: .semibold)); Spacer(); Text(L("\(items.count) 款")).font(.caption).foregroundStyle(IndiePalette.secondaryText) }
            ScrollView(.horizontal) {
                HStack(spacing: 14) {
                    ForEach(items.prefix(20)) { item in storeCard(item) }
                }.padding(.vertical, 3)
            }.scrollIndicators(.hidden)
        }.padding(.horizontal, 28)
    }

    private func storeCard(_ item: SteamStoreItem) -> some View {
        Button { selectedItem = item } label: {
            VStack(alignment: .leading, spacing: 8) {
                AsyncImage(url: item.imageURL) { image in image.resizable().scaledToFill() }
                placeholder: { IndiePalette.surfaceStrong }
                    .frame(width: 238, height: 112).clipped()
                Text(item.name).font(.system(size: 13.5, weight: .semibold)).lineLimit(1)
                HStack { priceView(item); Spacer(); if item.discountPercent > 0 { Text("-\(item.discountPercent)%").foregroundStyle(IndiePalette.green) } }
                    .font(.caption)
            }
            .padding(10).frame(width: 258, alignment: .leading)
            .background(selectedItem?.id == item.id ? IndiePalette.surfaceStrong : IndiePalette.surface, in: RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).stroke(selectedItem?.id == item.id ? IndiePalette.blue : IndiePalette.border))
        }.buttonStyle(.plain)
    }

    @ViewBuilder
    private func priceView(_ item: SteamStoreItem) -> some View {
        if let price = item.finalPrice {
            HStack(spacing: 7) {
                if let original = item.originalPrice, original > price {
                    Text(currency(original, code: item.currency)).strikethrough().foregroundStyle(IndiePalette.secondaryText)
                }
                Text(price == 0 ? L("免费游玩") : currency(price, code: item.currency)).fontWeight(.semibold)
            }
        } else { Text(L("查看价格")).foregroundStyle(IndiePalette.secondaryText) }
    }

    private var sectionTitle: String {
        if !search.isEmpty { return L("搜索结果") }
        return switch selection {
        case .featured: L("为你推荐")
        case .topSellers: L("热销商品")
        case .specials: L("特别优惠")
        case .newReleases: L("新品推荐")
        }
    }

    private func currency(_ cents: Int, code: String?) -> String {
        let value = Double(cents) / 100
        if code == "CNY" { return String(format: "¥%.0f", value) }
        return String(format: "%@ %.2f", code ?? "", value)
    }

    private func openSecurePage(_ appID: UInt64) {
        guard let url = URL(string: "https://store.steampowered.com/app/\(appID)/?l=\(AppLanguage.steamLanguage)") else { return }
        securePage = SecurePageTarget(url: url)
    }

    private func selectRequestedItem() {
        guard let appID = model.steamStoreSelectedAppID else { return }
        selectedItem = displayItems.first(where: { $0.id == appID })
    }
}

private struct SecureSteamPage: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var session: SteamWebSession

    init(url: URL) { _session = StateObject(wrappedValue: SteamWebSession(homeURL: url)) }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Label(L("Steam 安全页面"), systemImage: "lock.shield.fill").font(.system(size: 16, weight: .semibold))
                    Text(L("登录、愿望单和购买直接由 store.steampowered.com 处理"))
                        .font(.caption).foregroundStyle(IndiePalette.secondaryText)
                }
                Spacer(); Button(L("完成")) { dismiss() }.keyboardShortcut(.defaultAction)
            }.padding(.horizontal, 20).frame(height: 62).background(IndiePalette.topBar)
            Divider().overlay(IndiePalette.border)
            SteamBrowserView(session: session)
        }
        .frame(minWidth: 1040, minHeight: 720).preferredColorScheme(.dark)
    }
}

private struct SecurePageTarget: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

private extension Array {
    func uniqued<Key: Hashable>(by keyPath: KeyPath<Element, Key>) -> [Element] {
        var seen = Set<Key>()
        return filter { seen.insert($0[keyPath: keyPath]).inserted }
    }
}
