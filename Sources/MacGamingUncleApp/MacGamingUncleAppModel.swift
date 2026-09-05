import AppKit
import Foundation
import IndieCatalog
import IndieCore
import IndieRuntime
import Metal

@MainActor
final class MacGamingUncleAppModel: ObservableObject {
    @Published var systemReport: SystemReport?
    @Published var games: [GameRecord] = []
    @Published var steamGames: [SteamGame] = []
    @Published var steamAccountGames: [SteamAccountGame] = []
    @Published var steamActivities: [UInt64: SteamGameActivity] = [:]
    @Published var steamStoreCatalog: SteamStoreCatalog?
    @Published var steamStoreSearchResults: [SteamStoreItem] = []
    @Published var steamStoreSelectedAppID: UInt64?
    @Published var isSteamStoreLoading = false
    @Published var steamStoreError: String?
    @Published var requestedDestination: String?
    @Published var bottles: [BottleRecord] = []
    @Published var d3dMetal: [ImportedD3DMetal] = []
    @Published var wineRuntimes: [LocalWineRuntime] = []
    @Published var rendererOverlays: [RendererOverlay] = []
    @Published var gameConfigurations: [String: GameConfiguration] = [:]
    @Published var isWorking = false
    @Published var isGPTKSetupRunning = false
    @Published var status = ""
    @Published var lastError: String?
    @Published var onboardingStage = FirstRunStage.checking
    @Published var onboardingBusy = false
    @Published var onboardingError: String?
    @Published var onboardingMessage = L("正在检查这台 Mac 的运行环境…")
    private var onboardingTask: Task<Void, Never>?

    let paths = IndiePaths.userDefault
    let controllerManager: ControllerManager
    let steamSessionManager: SteamSessionManager
    private let store: StateStore
    private let probe = SystemProbe()
    private lazy var importer = GPTKImporter(paths: paths)
    private lazy var wineImporter = LocalWineImporter(paths: paths)
    private lazy var overlayImporter = RendererOverlayImporter(paths: paths)
    private lazy var communityGamingWine = CommunityIndieWineBootstrapper(paths: paths)
    private lazy var communityDXMT = CommunityDXMTBootstrapper(paths: paths)
    private var recipeRepository = RecipeRepository(recipes: [])
    private var gptkSetupTask: Task<Void, Never>?
    private var steamMetadataTask: Task<Void, Never>?
    private var steamMetadataCache: [UInt64: SteamStoreMetadataService.Metadata] = [:]
    private var steamStoreLoadedAt: Date?

    var environmentReady: Bool {
        systemReport?.isSupported == true && gamingWineRuntime != nil
    }

    private var preferredGPTKRuntime: AppleGPTKRuntime? {
        AppleGPTKRuntime.discover(importedComponents: d3dMetal) ?? AppleGPTKRuntime.discover()
    }
    private var preferredD3DMetal: ImportedD3DMetal? {
        d3dMetal.first { $0.rendererRoot != nil }
    }
    private var gamingWineRuntime: LocalWineRuntime? {
        wineRuntimes.first { $0.manifest.id == CommunityIndieWineBootstrapper.runtimeID }
    }
    var gptkRuntimeVersion: String? { preferredD3DMetal?.version ?? preferredGPTKRuntime?.version }
    var d3dMetalRuntimeAvailable: Bool {
        guard let version = gptkRuntimeVersion else { return false }
        return Self.majorVersion(version) >= 4 && preferredD3DMetal?.rendererRoot != nil && gamingWineRuntime != nil
    }
    var gptkNeedsUpdate: Bool {
        guard let version = gptkRuntimeVersion else { return true }
        return Self.majorVersion(version) < 4
    }

    var steamBottle: BottleRecord? { bottles.first { $0.name == "Steam" } }

    var availableRendererKinds: Set<RendererKind> {
        var result: Set<RendererKind> = [.wineD3D]
        if d3dMetalRuntimeAvailable { result.insert(.d3dMetal) }
        result.formUnion(rendererOverlays.map(\.kind))
        return result
    }

    var steamExecutable: URL? {
        guard let bottle = steamBottle else { return nil }
        let candidates = [
            bottle.root.appendingPathComponent("drive_c/Program Files (x86)/Steam/steam.exe"),
            bottle.root.appendingPathComponent("drive_c/Program Files/Steam/steam.exe"),
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    var setupStage: SetupStage {
        SetupFlow.stage(
            environmentReady: environmentReady,
            steamInstalled: steamExecutable != nil,
            installedGameCount: steamGames.count
        )
    }

    init() {
        store = StateStore(databaseURL: paths.database)
        controllerManager = ControllerManager()
        steamSessionManager = SteamSessionManager()
        onboardingTask = Task {
            await refresh()
            await runOnboarding()
        }
    }

    var onboardingGraphicsReady: Bool { d3dMetalRuntimeAvailable }
    var onboardingWineReady: Bool { gamingWineRuntime != nil }
    var onboardingDXMTReady: Bool { rendererOverlays.contains { $0.kind == .dxmt } }

    func shutdownManagedSteam() async {
        onboardingTask?.cancel()
        gptkSetupTask?.cancel()
        steamMetadataTask?.cancel()
        // Join first so an installation cannot launch Steam after shutdown.
        await onboardingTask?.value
        await gptkSetupTask?.value
        steamSessionManager.didStop()
        guard let bottle = steamBottle, let runtime = gamingWineRuntime else { return }
        let environment = ["WINEPREFIX": bottle.root.path, "WINEDEBUG": "-all",
                           "DYLD_LIBRARY_PATH": runtime.root.appendingPathComponent("lib").path]
        if let steam = steamExecutable {
            _ = try? await Subprocess().run(
                runtime.root.appendingPathComponent("bin/wine"),
                arguments: [steam.path, "-shutdown"], environment: environment,
                workingDirectory: steam.deletingLastPathComponent(),
                timeout: .seconds(10), requireSuccess: false
            )
            _ = try? await Subprocess().run(
                runtime.root.appendingPathComponent("bin/wineserver"),
                arguments: ["-w"], environment: environment,
                timeout: .seconds(8), requireSuccess: false
            )
        }
        await WineRuntimeProvider(manifest: runtime.manifest, root: runtime.root).stopBottle(bottle)
    }

    func retryOnboarding() {
        guard !onboardingBusy else { return }
        onboardingTask = Task { await runOnboarding() }
    }

    private func runOnboarding() async {
        guard !onboardingBusy else { return }
        onboardingBusy = true
        onboardingError = nil
        defer { onboardingBusy = false }
        do {
            onboardingStage = .environment
            guard let report = systemReport else {
                throw IndieError.invalidData(lastError ?? L("无法读取系统信息，请重新打开应用"))
            }
            let failures = report.items.filter { $0.severity == .failure && $0.id != "rosetta" }
            guard failures.isEmpty else {
                throw IndieError.unsupported(failures.map(\.detail).joined(separator: "；"))
            }
            if !report.rosettaInstalled {
                onboardingMessage = L("正在安装 Apple Rosetta 2…")
                try await Subprocess().run(
                    URL(fileURLWithPath: "/usr/sbin/softwareupdate"),
                    arguments: ["--install-rosetta", "--agree-to-license"], timeout: .seconds(600)
                )
                systemReport = await probe.run()
            }
            if !onboardingWineReady {
                onboardingMessage = L("正在下载并校验 Wine 与 SDL 手柄组件…")
                await prepareEnvironment()
                guard onboardingWineReady else { throw IndieError.invalidData(lastError ?? L("Wine 安装未完成")) }
            }
            if !onboardingDXMTReady {
                onboardingMessage = L("正在安装 DXMT 图形兼容组件…")
                _ = try await communityDXMT.installLatest()
                rendererOverlays = await overlayImporter.installed()
            }
            if !onboardingGraphicsReady {
                onboardingMessage = L("正在自动下载 GPTK 4 图形组件…")
                await setupLatestGPTK()
                guard onboardingGraphicsReady else { throw IndieError.invalidData(lastError ?? L("GPTK 安装未完成")) }
            }
            try Task.checkCancellation()
            if steamExecutable != nil,
               UserDefaults.standard.bool(forKey: "firstRunSteamLoginCompleted") {
                onboardingStage = .complete
                return
            }
            onboardingStage = .steam
            onboardingMessage = L("环境已就绪，正在准备 Steam…")
            try await prepareOnboardingSteam()
        } catch {
            onboardingError = error.localizedDescription
            lastError = nil
        }
    }

    private func prepareOnboardingSteam() async throws {
        guard let runtime = gamingWineRuntime else { throw IndieError.notFound(L("Wine 尚未安装")) }
        let provider = WineRuntimeProvider(manifest: runtime.manifest, root: runtime.root)
        let bottle: BottleRecord
        if let existing = steamBottle { bottle = existing }
        else {
            bottle = try await BottleManager(paths: paths, store: store).create(name: "Steam", runtime: provider)
            bottles = try await store.bottles()
        }
        if steamExecutable == nil {
            onboardingMessage = L("正在从 Valve 官方下载并安装 Steam…")
            let installer = SteamInstaller(paths: paths)
            let staged = try await installer.stageForLaunch(try await installer.download(), in: bottle)
            try await provider.prepareBottleForInstaller(bottle)
            let plan = try LaunchPlanBuilder.build(
                executable: staged.fileURL, windowsExecutablePath: staged.windowsPath,
                bottle: bottle,
                profile: .init(runtimeID: runtime.manifest.id, preferredRenderer: .wineD3D,
                               arguments: ["/S"], environment: ["WINEDEBUG": "-all", "WINEDLLOVERRIDES": "mscoree,mshtml="]),
                analysis: try PEAnalyzer.analyze(at: staged.fileURL), recipe: nil,
                installed: .init(available: [.wineD3D])
            )
            _ = try await provider.launchDetached(plan, logURL: paths.logs.appendingPathComponent("onboarding-steam-install.log"))
            let deadline = Date().addingTimeInterval(600)
            while steamExecutable == nil {
                try Task.checkCancellation()
                guard Date() < deadline else { throw IndieError.timedOut(L("Steam 安装或更新，请检查网络后重试")) }
                try await Task.sleep(for: .seconds(2))
            }
        }
        let helper = SteamCompatibilityManager.steamRoot(in: bottle).appendingPathComponent("bin/cef/cef.win64/steamwebhelper.exe")
        if !FileManager.default.fileExists(atPath: helper.path), let steam = steamExecutable {
            onboardingMessage = L("Steam 基础安装已完成，正在下载客户端更新…")
            let updatePlan = try LaunchPlanBuilder.build(
                executable: steam, windowsExecutablePath: try WinePath.windowsPath(for: steam, in: bottle), bottle: bottle,
                profile: .init(runtimeID: runtime.manifest.id, preferredRenderer: .wineD3D,
                               arguments: ["-no-cef-sandbox"], environment: ["WINEDEBUG": "-all", "WINEDLLOVERRIDES": "mscoree,mshtml="]),
                analysis: try PEAnalyzer.analyze(at: steam), recipe: nil, installed: .init(available: [.wineD3D])
            )
            _ = try await provider.launchDetached(updatePlan, logURL: paths.logs.appendingPathComponent("onboarding-steam-update.log"))
            let deadline = Date().addingTimeInterval(900)
            while !FileManager.default.fileExists(atPath: helper.path) {
                try Task.checkCancellation()
                guard Date() < deadline else { throw IndieError.timedOut(L("Steam 客户端更新")) }
                try await Task.sleep(for: .seconds(2))
            }
            // Allow the updater to finish replacing its other client files.
            try await Task.sleep(for: .seconds(10))
        }
        guard let steam = steamExecutable,
              let wrapper = SteamCompatibilityManager.bundledWrapperURL() else {
            throw IndieError.notFound(L("Steam 登录组件不完整，请重试安装"))
        }
        try await provider.prepareBottleForInstaller(bottle)
        try await provider.configureControllerSupport(in: bottle)
        _ = try SteamCompatibilityManager.prepare(bottle: bottle, wrapper: wrapper)
        let environment = ["WINEDEBUG": "-all", "LANG": "zh_CN.UTF-8", "LC_ALL": "zh_CN.UTF-8",
                           "WINEDLLOVERRIDES": "mscoree,mshtml=;winedbg.exe=d;dxgi,d3d10,d3d10core,d3d11,d3d12=b"]
        let plan = try LaunchPlanBuilder.build(
            executable: steam, windowsExecutablePath: try WinePath.windowsPath(for: steam, in: bottle), bottle: bottle,
            profile: .init(runtimeID: runtime.manifest.id, preferredRenderer: .wineD3D,
                           arguments: SteamCompatibilityManager.launchArguments(appID: nil), environment: environment),
            analysis: .init(identity: .init(executableName: "steam.exe"), architecture: .x86_64,
                            directX: .none, antiCheat: .none, importedLibraries: []),
            recipe: nil, installed: .init(available: [.wineD3D])
        )
        let launchedAt = Date()
        _ = try await provider.launchDetached(plan, logURL: paths.logs.appendingPathComponent("onboarding-steam-login.log"))
        onboardingMessage = L("请在 Steam 官方窗口中扫码，或输入账号密码登录。登录成功后会自动进入游戏库。")
        let deadline = Date().addingTimeInterval(30 * 60)
        while !SteamCompatibilityManager.isLoggedOn(in: bottle, since: launchedAt) {
            try Task.checkCancellation()
            guard Date() < deadline else { throw IndieError.timedOut(L("Steam 登录，可点击重试重新打开登录窗口")) }
            try await Task.sleep(for: .seconds(2))
        }
        steamSessionManager.didLaunch(.init(bottleID: bottle.id, runtimeID: runtime.manifest.id,
                                           environment: plan.environment, virtualDesktop: nil), reused: false)
        try scanDefaultSteamLibrary()
        UserDefaults.standard.set(true, forKey: "firstRunSteamLoginCompleted")
        onboardingStage = .complete
        requestedDestination = "library"
    }

    func refresh() async {
        isWorking = true
        defer { isWorking = false }
        do {
            try paths.createDirectories()
            try await store.open()
            async let report = probe.run()
            async let savedGames = store.games()
            async let savedBottles = store.bottles()
            async let imported = importer.installedComponents()
            async let wine = wineImporter.installed()
            async let overlays = overlayImporter.installed()
            async let savedConfigurations = store.gameConfigurations()
            systemReport = await report
            games = try await savedGames
            bottles = try await savedBottles
            d3dMetal = try await imported
            wineRuntimes = await wine
            rendererOverlays = await overlays
            gameConfigurations = Dictionary(uniqueKeysWithValues: try await savedConfigurations.map { ($0.id, $0) })
            var loadedRecipes = try RecipeRepository.builtIn().recipes
            loadedRecipes.append(contentsOf: try RecipeRepository.load(from: paths.recipes).recipes)
            recipeRepository = RecipeRepository(recipes: loadedRecipes)
            try scanDefaultSteamLibrary()
            if self.steamSessionManager.state == .running,
               (self.steamBottle.map { SteamCompatibilityManager.isLoggedOn(in: $0) } != true) {
                self.steamSessionManager.didStop()
            }
            status = L("准备就绪")
            Task { await self.loadNativeSteamStore() }
        } catch { present(error) }
    }

    func handleDeepLink(_ url: URL) {
        guard let scheme = url.scheme?.lowercased(), ["macgaminguncle", "indie"].contains(scheme) else {
            present(IndieError.invalidArgument(L("无法识别 Mac Gaming Uncle 链接：\(url.absoluteString)")))
            return
        }
        if let destination = url.host?.lowercased(),
           ["home", "store", "library", "controllers", "environment"].contains(destination) {
            requestedDestination = destination
            return
        }
        guard
              url.host?.lowercased() == "launch",
              let appIDText = url.pathComponents.dropFirst().first,
              let appID = UInt64(appIDText) else {
            present(IndieError.invalidArgument(L("无法识别 Mac Gaming Uncle 链接：\(url.absoluteString)")))
            return
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            while self.isWorking { try? await Task.sleep(for: .milliseconds(100)) }
            guard let game = self.steamGames.first(where: { $0.appID == appID }) else {
                self.present(IndieError.notFound(L("Steam 游戏库中没有 AppID \(appID)")))
                return
            }
            await self.launchSteamGame(game)
        }
    }

    func prepareEnvironment() async {
        await perform(L("正在安装 Mac Gaming Uncle Wine 11 开源运行环境…")) {
            guard self.systemReport?.isSupported == true else {
                throw IndieError.unsupported(L("这台 Mac 尚未通过环境检查，请打开高级设置查看原因"))
            }
            self.status = L("正在下载并校验 Mac Gaming Uncle Wine 11…")
            let installed = try await self.communityGamingWine.installLatest()
            self.wineRuntimes = await self.wineImporter.installed()
            self.status = L("游戏运行环境 \(installed.manifest.version) 已准备好")
        }
    }

    func importExecutable(_ url: URL) async {
        await perform(L("正在分析 \(url.lastPathComponent)…")) {
            let analysis = try PEAnalyzer.analyze(at: url)
            let game = GameRecord(displayName: url.deletingPathExtension().lastPathComponent, source: .local, executableURL: url, analysis: analysis)
            try await self.store.saveGame(game)
            self.games = try await self.store.games()
            self.status = L("已导入 \(url.lastPathComponent)：\(analysis.architecture.rawValue) / \(analysis.directX.rawValue)")
        }
    }

    func scanSteam(_ steamApps: URL) async {
        await perform(L("正在扫描 Steam 游戏库…")) {
            self.steamGames = try SteamScanner.scan(steamApps: steamApps)
            self.status = L("发现 \(self.steamGames.count) 个 Steam 游戏")
        }
    }

    func installSteam() async {
        await perform(L("正在从 Valve 官方 CDN 下载 Steam…")) {
            guard let runtime = self.gamingWineRuntime else {
                throw IndieError.notFound(L("请先准备 Mac Gaming Uncle Wine 11 开源运行环境"))
            }
            let steamInstaller = SteamInstaller(paths: self.paths)
            let installer = try await steamInstaller.download()
            let provider = WineRuntimeProvider(manifest: runtime.manifest, root: runtime.root)
            let bottle = if let existing = self.bottles.first(where: { $0.name == "Steam" }) {
                existing
            } else {
                try await BottleManager(paths: self.paths, store: self.store).create(name: "Steam", runtime: provider)
            }
            await provider.stopBottle(bottle)
            self.steamSessionManager.didStop()
            try await provider.prepareBottleForInstaller(bottle)
            try await provider.configureControllerSupport(in: bottle)
            let stagedInstaller = try await steamInstaller.stageForLaunch(installer, in: bottle)
            let analysis = try PEAnalyzer.analyze(at: stagedInstaller.fileURL)
            let profile = LaunchProfile(
                runtimeID: runtime.manifest.id,
                preferredRenderer: .wineD3D,
                environment: ["LANG": "zh_CN.UTF-8", "LC_ALL": "zh_CN.UTF-8"]
            )
            let plan = try LaunchPlanBuilder.build(
                executable: stagedInstaller.fileURL,
                windowsExecutablePath: stagedInstaller.windowsPath,
                bottle: bottle, profile: profile, analysis: analysis,
                recipe: nil, installed: InstalledRenderers(available: [.wineD3D])
            )
            let log = self.paths.logs.appendingPathComponent("\(plan.id.uuidString)-steam-install.log")
            self.status = L("请在 Wine 窗口中完成 Steam 安装…")
            let session = await provider.launch(plan, logURL: log)
            try await self.store.saveSession(session)
            self.bottles = try await self.store.bottles()
            let steamApps = bottle.root.appendingPathComponent("drive_c/Program Files (x86)/Steam/steamapps", isDirectory: true)
            if FileManager.default.fileExists(atPath: steamApps.path) {
                self.steamGames = try SteamScanner.scan(steamApps: steamApps)
            }
            self.status = L("Steam 安装流程已结束")
        }
    }

    func launchSteam(appID: UInt64? = nil) async {
        if appID == nil, steamSessionManager.state == .running,
           let bottle = steamBottle, SteamCompatibilityManager.isLoggedOn(in: bottle) {
            syncSteamLibrary()
            requestedDestination = "library"
            return
        }
        await perform(appID == nil ? L("正在打开 Steam…") : L("正在通过 Steam 启动游戏…")) {
            guard let runtime = self.gamingWineRuntime,
                  let bottle = self.steamBottle,
                  let executable = self.steamExecutable else {
                throw IndieError.notFound(L("尚未完成 Steam 安装"))
            }
            let provider = WineRuntimeProvider(manifest: runtime.manifest, root: runtime.root)
            guard let wrapper = SteamCompatibilityManager.bundledWrapperURL() else {
                throw IndieError.notFound(L("Mac Gaming Uncle 缺少 Steam 界面兼容组件，请重新安装应用"))
            }
            await provider.stopBottle(bottle)
            self.steamSessionManager.didStop()
            try await provider.prepareBottleForInstaller(bottle)
            try await provider.configureControllerSupport(in: bottle)
            _ = try SteamCompatibilityManager.prepare(bottle: bottle, wrapper: wrapper)
            let analysis = GameAnalysis(
                identity: GameIdentity(steamAppID: appID, executableName: "steam.exe"),
                architecture: .x86_64, directX: .none, antiCheat: .none, importedLibraries: []
            )
            let environment = [
                "LANG": "zh_CN.UTF-8",
                "LC_ALL": "zh_CN.UTF-8",
                "WINEDEBUG": "-all",
                "WINEMSYNC": "1",
                // Renderer bridges are installed in this shared Steam bottle,
                // but Steam/CEF must stay on Wine builtins. The selected game
                // gets its own renderer overrides in gamePlan below.
                "WINEDLLOVERRIDES": "mscoree,mshtml=;winedbg.exe=d;dxgi,d3d10,d3d10core,d3d11,d3d12=b",
            ]
            let profile = LaunchProfile(
                runtimeID: runtime.manifest.id,
                preferredRenderer: .wineD3D,
                arguments: SteamCompatibilityManager.launchArguments(appID: appID),
                environment: environment
            )
            let plan = try LaunchPlanBuilder.build(
                executable: executable,
                windowsExecutablePath: try WinePath.windowsPath(for: executable, in: bottle),
                bottle: bottle, profile: profile, analysis: analysis,
                recipe: nil, installed: InstalledRenderers(available: [.wineD3D])
            )
            let log = self.paths.logs.appendingPathComponent("\(plan.id.uuidString)-steam.log")
            self.status = appID == nil ? L("Steam 正在运行；请登录并安装游戏") : L("游戏正在运行")
            _ = try await provider.launchDetached(plan, logURL: log)
            self.steamSessionManager.didLaunch(
                .init(bottleID: bottle.id, runtimeID: runtime.manifest.id,
                      environment: plan.environment, virtualDesktop: nil), reused: false
            )
            try self.scanDefaultSteamLibrary()
            self.status = L("Steam 已打开，登录后自动同步游戏库")
        }
    }

    func launchSteamGame(_ game: SteamGame) async {
        await perform(L("正在为 \(game.name) 选择最佳图形后端…")) {
            guard let bottle = self.steamBottle else {
                throw IndieError.notFound(L("尚未完成 Steam 安装"))
            }
            guard let gamingRuntime = self.gamingWineRuntime else {
                throw IndieError.notFound(L("需要 Mac Gaming Uncle Wine 11 游戏引擎，请重新运行环境准备"))
            }
            let gamingProvider = WineRuntimeProvider(manifest: gamingRuntime.manifest, root: gamingRuntime.root)
            let executable = try SteamExecutableResolver.shippingExecutable(for: game)
            self.status = L("正在快速检查游戏兼容性…")
            let analysis = try await Task.detached(priority: .userInitiated) {
                try PEAnalyzer.analyze(at: executable, steamAppID: game.appID)
            }.value
            let configuration = self.configuration(for: game)
            let recipe = self.recipeRepository.match(analysis)
            if game.appID == 219990 {
                self.status = L("正在应用 Grim Dawn 1.3 HUD 兼容配置…")
                let screen = NSScreen.main?.frame.size
                let safeResolution = configuration.virtualDesktop?.label.replacingOccurrences(of: " × ", with: " ")
                    ?? GrimDawnCompatibility.logicalDisplayResolution(
                        width: screen.map { Double($0.width) },
                        height: screen.map { Double($0.height) }
                    )
                _ = try GrimDawnCompatibility.prepare(
                    bottleRoot: bottle.root,
                    safeResolution: safeResolution
                )
            }
            if (configuration.preferredRenderer == .dxmt || recipe?.profiles.first?.renderer == .dxmt),
               !self.rendererOverlays.contains(where: { $0.kind == .dxmt }) {
                self.status = L("正在安装 \(game.name) 所需的 DXMT 0.80…")
                _ = try await self.communityDXMT.installLatest()
                self.rendererOverlays = await self.overlayImporter.installed()
            }
            var availableRenderers: Set<RendererKind> = [.wineD3D]
            var overlayPaths: [RendererKind: URL] = [:]
            if let component = self.preferredD3DMetal,
               let renderer = component.rendererRoot,
               Self.majorVersion(component.version) >= 4 {
                availableRenderers.insert(.d3dMetal)
                overlayPaths[.d3dMetal] = renderer.appendingPathComponent("wine", isDirectory: true)
            }
            for overlay in self.rendererOverlays where overlay.kind == .dxmt {
                availableRenderers.insert(.dxmt)
                overlayPaths[.dxmt] = overlay.root
            }
            let installedRenderers = InstalledRenderers(available: availableRenderers, overlayPaths: overlayPaths)
            let resolution = try RendererResolver.resolve(
                analysis: analysis,
                preferred: configuration.preferredRenderer,
                recipe: recipe,
                installed: installedRenderers
            )
            let recipeProfile = recipe?.profiles.first { $0.renderer == resolution.renderer }
            let recipeArguments = recipeProfile?.arguments ?? []

            let wantsMetalHUD = configuration.metalHUD.resolve(
                default: UserDefaults.standard.bool(forKey: "metalHUD")
            )
            // Both D3DMetal and DXMT submit work directly to Metal. Keep the
            // Apple HUD available for either backend; restricting it to
            // D3DMetal made the setting appear broken for DX11 titles whose
            // compatibility recipe deliberately selects DXMT.
            let metalHUDEnabled = wantsMetalHUD && [.d3dMetal, .dxmt].contains(resolution.renderer)
            let metalFXEnabled = configuration.metalFX.resolve(
                default: UserDefaults.standard.bool(forKey: "metalFX")
            ) &&
                resolution.renderer == .d3dMetal && recipeProfile?.metalFX != false
            let wantsMetal4 = UserDefaults.standard.object(forKey: "metal4") as? Bool ?? true
            let metal4Enabled = configuration.metal4.resolve(default: wantsMetal4) &&
                recipeProfile?.metal4 != false && Self.supportsMetal4
            var environment = [
                "LANG": "zh_CN.UTF-8",
                "LC_ALL": "zh_CN.UTF-8",
                "WINEDEBUG": "-all",
            ]
            var needsWarmupProtection = false
            if resolution.renderer == .d3dMetal {
                guard let component = self.preferredD3DMetal,
                      let renderer = component.rendererRoot else {
                    throw IndieError.notFound(L("请先使用“一键安装 GPTK 4”导入 D3DMetal"))
                }
                environment = try D3DMetalLaunchEnvironment.make(
                    rendererRoot: renderer,
                    runtimeRoot: gamingRuntime.root,
                    metalHUD: metalHUDEnabled,
                    metalFX: metalFXEnabled,
                    metal4: metal4Enabled
                )
                let shaderPreparation = try D3DMetalShaderCacheManager.prepare(
                    executableName: executable.lastPathComponent,
                    profile: D3DMetalShaderProfile(
                        rendererVersion: component.version,
                        rendererSHA256: component.sourceSHA256,
                        metalFX: metalFXEnabled,
                        dxr: false,
                        metal4: metal4Enabled,
                        launchArguments: recipeArguments
                    ),
                    backupRoot: self.paths.shaderCacheBackups
                )
                needsWarmupProtection = shaderPreparation.needsWarmupProtection
            } else if resolution.renderer == .wineD3D {
                environment["CX_ACTIVE_GRAPHICS_BACKEND"] = "wined3d"
                environment["WINEDLLOVERRIDES"] = "dxgi,d3d10,d3d10core,d3d11,d3d12=b"
            }

            var gameEnvironment = environment
            gameEnvironment.merge(
                ControllerLaunchEnvironment.make(
                    mode: configuration.controllerMode,
                    rumble: configuration.controllerRumble
                )
            ) { _, configured in configured }
            // Steam supplies the correct AppID to each child. Keeping an AppID
            // on the long-lived Steam process would leak the first game's ID
            // into later launches when the client is reused.
            // Steam owns executable selection for `-applaunch`; only pass
            // compatibility switches here. Positional launcher shims are for
            // direct EXE execution and would corrupt Steam launch options.
            var gameArguments = configuration.arguments
            if needsWarmupProtection,
               executable.lastPathComponent.lowercased().contains("-win64-shipping") {
                // D3DMetal may need more than UE's 120-second RenderThread
                // watchdog allowance while rebuilding a large pipeline cache.
                if !gameArguments.contains("-nothreadtimeout") && !recipeArguments.contains("-nothreadtimeout") {
                    gameArguments.append("-nothreadtimeout")
                }
            }
            let gameProfile = LaunchProfile(
                runtimeID: gamingProvider.manifest.id,
                preferredRenderer: resolution.renderer,
                syncBackend: configuration.syncBackend,
                arguments: gameArguments,
                environment: gameEnvironment,
                metalHUD: metalHUDEnabled,
                virtualDesktop: configuration.virtualDesktop
            )
            let gamePlan = try LaunchPlanBuilder.build(
                executable: executable,
                windowsExecutablePath: try WinePath.windowsPath(for: executable, in: bottle),
                bottle: bottle, profile: gameProfile, analysis: analysis,
                recipe: recipe,
                installed: installedRenderers
            )
            if let option = recipeProfile?.steamLaunchOption {
                _ = try SteamCompatibilityManager.setDefaultLaunchOption(
                    appID: game.appID, option: option, in: bottle
                )
            }
            guard let steam = self.steamExecutable else { throw IndieError.notFound(L("尚未完成 Steam 安装")) }
            let steamAnalysis = GameAnalysis(
                identity: GameIdentity(steamAppID: game.appID, executableName: "steam.exe"),
                architecture: .x86_64, directX: .none, antiCheat: .none, importedLibraries: []
            )
            let steamProfile = LaunchProfile(
                runtimeID: gamingRuntime.manifest.id,
                preferredRenderer: .wineD3D,
                syncBackend: gamePlan.environment["WINEMSYNC"] == "1" ? .msync : .wineserver,
                arguments: SteamCompatibilityManager.launchArguments(
                    appID: game.appID,
                    gameArguments: gamePlan.arguments,
                    launchOption: recipeProfile?.steamLaunchOption,
                    silent: true
                ),
                environment: SteamCompatibilityManager.relayEnvironment(for: gamePlan.environment),
                metalHUD: false,
                virtualDesktop: configuration.virtualDesktop
            )
            let steamPlan = try LaunchPlanBuilder.build(
                executable: steam,
                windowsExecutablePath: try WinePath.windowsPath(for: steam, in: bottle),
                bottle: bottle, profile: steamProfile, analysis: steamAnalysis,
                recipe: nil, installed: InstalledRenderers(available: [.wineD3D])
            )
            let descriptor = SteamSessionDescriptor(
                bottleID: bottle.id,
                runtimeID: gamingRuntime.manifest.id,
                environment: steamPlan.environment,
                virtualDesktop: configuration.virtualDesktop
            )
            let reusingSteam = self.steamSessionManager.canReuse(descriptor) &&
                SteamCompatibilityManager.isLoggedOn(in: bottle)
            if !reusingSteam {
                self.steamSessionManager.didStop()
                self.status = L("正在准备全局 Steam 会话…")
                try await gamingProvider.prepareBottleForInstaller(bottle)
                try await gamingProvider.configureControllerSupport(in: bottle)
                guard let wrapper = SteamCompatibilityManager.bundledWrapperURL() else {
                    throw IndieError.notFound(L("Mac Gaming Uncle 缺少 Steam 界面兼容组件，请重新安装应用"))
                }
                _ = try SteamCompatibilityManager.prepare(bottle: bottle, wrapper: wrapper)
                if resolution.renderer == .d3dMetal,
                   let component = self.preferredD3DMetal,
                   let renderer = component.rendererRoot {
                    try D3DMetalRendererPreparer.installBridge(
                        rendererRoot: renderer, version: component.version, bottle: bottle
                    )
                    if metalFXEnabled {
                        try D3DMetalRendererPreparer.enableMetalFX(
                            rendererRoot: renderer, version: component.version, bottle: bottle
                        )
                    }
                } else if resolution.renderer == .wineD3D {
                    try await gamingProvider.configureWineD3DGraphics(in: bottle)
                }
            }
            let launchPlan = reusingSteam ? steamPlan.withoutVirtualDesktop() : steamPlan
            let log = self.paths.logs.appendingPathComponent("\(launchPlan.id.uuidString)-steam-\(resolution.renderer.rawValue).log")
            let architecture = analysis.architecture == .x86_64 ? "x64" : analysis.architecture.rawValue
            self.status = reusingSteam
                ? L("正在通过已登录的 Steam 启动 \(game.name)…")
                : needsWarmupProtection
                ? L("\(game.name) 正在首次构建图形缓存，可能需要几分钟…")
                : L("正在由 Steam 启动 \(game.name) · \(architecture) + \(resolution.renderer.rawValue.uppercased())\(metal4Enabled ? " + Metal 4" : "")")
            _ = try await gamingProvider.launchDetached(launchPlan, logURL: log)
            self.steamSessionManager.didLaunch(descriptor, reused: reusingSteam)
        }
    }

    private static var supportsMetal4: Bool {
        if #available(macOS 26.0, *) {
            return MTLCreateSystemDefaultDevice()?.supportsFamily(.metal4) == true
        }
        return false
    }

    func rescanSteam() {
        do {
            try scanDefaultSteamLibrary()
            status = steamGames.isEmpty ? L("尚未发现已安装的 Steam 游戏") : L("发现 \(steamGames.count) 个 Steam 游戏")
        } catch { present(error) }
    }

    func installSteamGame(appID: UInt64) async {
        await sendSteamURI("steam://install/\(appID)", status: L("正在通过 Steam 安装游戏…"))
    }

    func loadNativeSteamStore(force: Bool = false) async {
        if !force, steamStoreCatalog != nil,
           let loadedAt = steamStoreLoadedAt, Date().timeIntervalSince(loadedAt) < 15 * 60 { return }
        isSteamStoreLoading = true
        steamStoreError = nil
        defer { isSteamStoreLoading = false }
        if steamStoreCatalog == nil {
            steamStoreCatalog = SteamNativeStoreCache.load(from: paths.steamNativeStoreCache)
        }
        do {
            let catalog = try await SteamNativeStoreService.featured()
            steamStoreCatalog = catalog
            try? SteamNativeStoreCache.save(catalog, to: paths.steamNativeStoreCache)
            steamStoreLoadedAt = Date()
        } catch {
            if steamStoreCatalog == nil {
                steamStoreError = L("Steam 商店暂时无法连接：\(error.localizedDescription)")
            }
        }
    }

    func searchNativeSteamStore(_ query: String) async {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard term.count >= 2 else { steamStoreSearchResults = []; return }
        isSteamStoreLoading = true
        steamStoreError = nil
        defer { isSteamStoreLoading = false }
        do {
            steamStoreSearchResults = try await SteamNativeStoreService.search(term)
        } catch {
            steamStoreError = L("搜索失败：\(error.localizedDescription)")
        }
    }

    func openSteamStore(appID: UInt64) {
        guard let url = URL(string: "https://store.steampowered.com/app/\(appID)/?l=\(AppLanguage.steamLanguage)") else { return }
        NSWorkspace.shared.open(url)
    }

    func handleSteamWebURL(_ url: URL) {
        guard url.scheme?.lowercased() == "steam" else { return }
        Task { await sendSteamURI(url.absoluteString, status: L("正在交给 Steam 处理…")) }
    }

    func importGPTK(_ url: URL) async {
        await perform(L("正在验证并导入 Apple D3DMetal…")) {
            let component = try await self.importer.importFromAppleImage(url)
            self.d3dMetal = try await self.importer.installedComponents()
            self.status = L("D3DMetal \(component.version) 已导入")
        }
    }

    func startGPTKSetup() {
        guard gptkSetupTask == nil else { return }
        gptkSetupTask = Task { [weak self] in
            guard let self else { return }
            await self.setupLatestGPTK()
            self.gptkSetupTask = nil
        }
    }

    func cancelGPTKSetup() {
        gptkSetupTask?.cancel()
    }

    func importWine(_ url: URL) async {
        await perform(L("正在验证并导入 Wine…")) {
            let runtime = try await self.wineImporter.importRuntime(from: url)
            self.wineRuntimes = await self.wineImporter.installed()
            self.status = L("Wine \(runtime.manifest.version) 已导入")
        }
    }

    func importRenderer(_ kind: RendererKind, from url: URL) async {
        await perform(L("正在导入 \(kind.rawValue)…")) {
            let overlay = try await self.overlayImporter.importOverlay(kind, from: url)
            self.rendererOverlays = await self.overlayImporter.installed()
            self.status = L("\(overlay.kind.rawValue) \(overlay.version) 已导入")
        }
    }

    func play(_ game: GameRecord) async {
        await perform(L("正在准备 \(game.displayName)…")) {
            guard let runtime = self.gamingWineRuntime else {
                throw IndieError.notFound(L("请先准备 Mac Gaming Uncle Wine 11 开源运行环境"))
            }
            let provider = WineRuntimeProvider(manifest: runtime.manifest, root: runtime.root)
            let bottle: BottleRecord
            if let bottleID = game.bottleID, let existing = self.bottles.first(where: { $0.id == bottleID }) {
                bottle = existing
            } else {
                bottle = try await BottleManager(paths: self.paths, store: self.store).create(name: game.displayName, runtime: provider)
                var updated = game
                updated.bottleID = bottle.id
                try await self.store.saveGame(updated)
                self.games = try await self.store.games()
                self.bottles = try await self.store.bottles()
            }
            var rendererSet: Set<RendererKind> = [.wineD3D]
            var overlays: [RendererKind: URL] = [:]
            if let metal = self.preferredD3DMetal, let renderer = metal.rendererRoot {
                rendererSet.insert(.d3dMetal)
                overlays[.d3dMetal] = renderer.appendingPathComponent("wine", isDirectory: true)
            }
            for overlay in self.rendererOverlays where overlays[overlay.kind] == nil {
                rendererSet.insert(overlay.kind)
                overlays[overlay.kind] = overlay.root
            }
            let configuration = self.configuration(for: game)
            await provider.stopBottle(bottle)
            try await provider.configureControllerSupport(in: bottle)
            let recipe = self.recipeRepository.match(game.analysis)
            let renderer = try RendererResolver.resolve(
                analysis: game.analysis,
                preferred: configuration.preferredRenderer,
                recipe: recipe,
                installed: InstalledRenderers(available: rendererSet, overlayPaths: overlays)
            ).renderer
            let recipeProfile = recipe?.profiles.first { $0.renderer == renderer }
            let wantsHUD = configuration.metalHUD.resolve(
                default: UserDefaults.standard.bool(forKey: "metalHUD")
            )
            let metalHUD = wantsHUD && [.d3dMetal, .dxmt].contains(renderer)
            let metalFX = configuration.metalFX.resolve(
                default: UserDefaults.standard.bool(forKey: "metalFX")
            ) && renderer == .d3dMetal && recipeProfile?.metalFX != false
            let defaultMetal4 = UserDefaults.standard.object(forKey: "metal4") as? Bool ?? true
            let metal4 = configuration.metal4.resolve(default: defaultMetal4) &&
                renderer == .d3dMetal && recipeProfile?.metal4 != false && Self.supportsMetal4
            var environment = ControllerLaunchEnvironment.make(
                mode: configuration.controllerMode,
                rumble: configuration.controllerRumble
            )
            if renderer == .d3dMetal {
                guard let component = self.preferredD3DMetal,
                      let rendererRoot = component.rendererRoot else {
                    throw IndieError.notFound(L("请先使用“一键安装 GPTK 4”导入 D3DMetal"))
                }
                try D3DMetalRendererPreparer.installBridge(
                    rendererRoot: rendererRoot, version: component.version, bottle: bottle
                )
                if metalFX {
                    try D3DMetalRendererPreparer.enableMetalFX(
                        rendererRoot: rendererRoot, version: component.version, bottle: bottle
                    )
                }
                let metalEnvironment = try D3DMetalLaunchEnvironment.make(
                    rendererRoot: rendererRoot,
                    runtimeRoot: runtime.root,
                    metalHUD: metalHUD,
                    metalFX: metalFX,
                    metal4: metal4
                )
                environment.merge(metalEnvironment) { current, _ in current }
            } else if renderer == .wineD3D {
                try await provider.configureWineD3DGraphics(in: bottle)
            }
            let profile = LaunchProfile(
                runtimeID: runtime.manifest.id,
                preferredRenderer: renderer,
                syncBackend: configuration.syncBackend,
                arguments: configuration.arguments,
                environment: environment,
                metalHUD: metalHUD,
                virtualDesktop: configuration.virtualDesktop
            )
            let plan = try LaunchPlanBuilder.build(
                executable: game.executableURL, bottle: bottle, profile: profile,
                analysis: game.analysis, recipe: recipe,
                installed: InstalledRenderers(available: rendererSet, overlayPaths: overlays)
            )
            try self.paths.createDirectories()
            let log = self.paths.logs.appendingPathComponent("\(plan.id.uuidString).log")
            self.status = L("正在运行 \(game.displayName)…")
            let session = await provider.launch(plan, logURL: log)
            try await self.store.saveSession(session)
            self.status = L("游戏已退出：\(String(describing: session.result))")
        }
    }

    func configuration(for game: SteamGame) -> GameConfiguration {
        configuration(appID: game.appID)
    }

    func configuration(appID: UInt64) -> GameConfiguration {
        let fallback = defaultGameConfiguration(id: GameConfiguration.steam(appID: appID).id)
        return gameConfigurations[fallback.id] ?? fallback
    }

    func configuration(for game: GameRecord) -> GameConfiguration {
        let fallback = defaultGameConfiguration(id: GameConfiguration.local(gameID: game.id).id)
        return gameConfigurations[fallback.id] ?? fallback
    }

    func defaultGameConfiguration(id: String) -> GameConfiguration {
        let rawMode = UserDefaults.standard.string(forKey: "defaultControllerMode")
        let mode = rawMode.flatMap(ControllerMode.init(rawValue:)) ?? .automatic
        let rumble = UserDefaults.standard.object(forKey: "defaultControllerRumble") as? Bool ?? true
        return GameConfiguration(id: id, controllerMode: mode, controllerRumble: rumble)
    }

    func saveGameConfiguration(_ configuration: GameConfiguration) async {
        lastError = nil
        do {
            guard configuration.virtualDesktop?.isValid != false else {
                throw IndieError.invalidArgument(L("分辨率必须在 640×480 到 7680×4320 之间"))
            }
            var updated = configuration
            updated.updatedAt = Date()
            try await store.saveGameConfiguration(updated)
            gameConfigurations[updated.id] = updated
            status = L("游戏设置已保存")
        } catch { present(error) }
    }

    private func perform(_ initialStatus: String, operation: @escaping @MainActor () async throws -> Void) async {
        guard !isWorking else { return }
        isWorking = true
        lastError = nil
        status = initialStatus
        defer { isWorking = false }
        do { try await operation() }
        catch is CancellationError { status = L("已取消 GPTK 安装") }
        catch { present(error) }
    }

    private func setupLatestGPTK() async {
        isGPTKSetupRunning = true
        defer { isGPTKSetupRunning = false }
        await perform(L("正在从下载服务器安装 GPTK 4…")) {
            self.status = L("正在下载并校验 GPTK 4（约 26.5 MB）…")
            let image = try await GPTKDownloadService(paths: self.paths).download()
            self.status = L("正在验证 Apple 签名并安装 GPTK 4…")
            let component = try await self.importer.importFromAppleImage(image)
            self.d3dMetal = try await self.importer.installedComponents()
            let version = component.version.split(whereSeparator: { !$0.isNumber }).first.flatMap { Int($0) } ?? 0
            guard version >= 4 else {
                throw IndieError.invalidData(L("下载的 D3DMetal 版本是 \(component.version)，不是 GPTK 4"))
            }
            guard component.rendererRoot != nil else {
                throw IndieError.invalidData(L("GPTK 4 镜像缺少 D3DMetal Wine Bridge；请确认下载的是 Windows 游戏评估环境"))
            }
            self.status = L("正在安装支持现代 Steam 的 Mac Gaming Uncle Wine 11（约 50 MB）…")
            _ = try await self.communityGamingWine.installLatest()
            self.wineRuntimes = await self.wineImporter.installed()
            self.status = L("GPTK \(component.version) 已验证并安装，可以启动游戏")
        }
    }

    private static func majorVersion(_ value: String) -> Int {
        value.split(whereSeparator: { !$0.isNumber }).first.flatMap { Int($0) } ?? 0
    }

    private func present(_ error: Error) {
        lastError = error.localizedDescription
        status = L("操作失败")
    }

    private func scanDefaultSteamLibrary() throws {
        guard let bottle = steamBottle else { return }
        let previousIDs = steamAccountGames.map(\.appID)
        let steamApps = bottle.root.appendingPathComponent("drive_c/Program Files (x86)/Steam/steamapps", isDirectory: true)
        steamGames = FileManager.default.fileExists(atPath: steamApps.path)
            ? try SteamScanner.scan(steamApps: steamApps) : []
        steamAccountGames = try SteamAccountLibraryScanner.scan(
            steamRoot: SteamCompatibilityManager.steamRoot(in: bottle),
            installed: steamGames
        )
        steamActivities = SteamActivityScanner.scan(
            steamRoot: SteamCompatibilityManager.steamRoot(in: bottle)
        )
        steamMetadataCache = SteamStoreMetadataCache.load(from: paths.steamCatalogCache)
        for index in steamAccountGames.indices {
            guard let metadata = steamMetadataCache[steamAccountGames[index].appID] else { continue }
            steamAccountGames[index].name = metadata.name
            steamAccountGames[index].headerImageURL = metadata.headerImageURL
            steamAccountGames[index].description = metadata.description
        }
        if previousIDs != steamAccountGames.map(\.appID) || steamMetadataTask == nil {
            scheduleSteamMetadataHydration()
        }
    }

    func syncSteamLibrary() {
        guard !onboardingBusy, !isWorking else { return }
        do {
            try scanDefaultSteamLibrary()
            if !steamAccountGames.isEmpty {
                status = L("已同步 \(steamAccountGames.count) 款账户游戏")
            } else {
                status = L("正在等待 Steam 写入账户游戏库…")
            }
        } catch {
            status = L("游戏库同步失败：\(error.localizedDescription)")
        }
    }

    private func scheduleSteamMetadataHydration() {
        steamMetadataTask?.cancel()
        let appIDs = steamAccountGames
            .filter { steamMetadataCache[$0.appID] == nil }
            .map(\.appID)
        guard !appIDs.isEmpty else { return }
        steamMetadataTask = Task { [weak self] in
            guard let self else { return }
            for offset in stride(from: 0, to: appIDs.count, by: 8) {
                if Task.isCancelled { return }
                let chunk = Array(appIDs[offset..<min(offset + 8, appIDs.count)])
                let metadata = await withTaskGroup(of: (UInt64, SteamStoreMetadataService.Metadata?).self) { group in
                    for appID in chunk {
                        group.addTask { (appID, await SteamStoreMetadataService.fetch(appID: appID)) }
                    }
                    var values: [(UInt64, SteamStoreMetadataService.Metadata?)] = []
                    for await value in group { values.append(value) }
                    return values
                }
                for (appID, details) in metadata {
                    guard let details,
                          let index = self.steamAccountGames.firstIndex(where: { $0.appID == appID }) else { continue }
                    self.steamAccountGames[index].name = details.name
                    self.steamAccountGames[index].headerImageURL = details.headerImageURL
                    self.steamAccountGames[index].description = details.description
                    self.steamMetadataCache[appID] = details
                }
                try? SteamStoreMetadataCache.save(self.steamMetadataCache, to: self.paths.steamCatalogCache)
            }
        }
    }

    private func sendSteamURI(_ uri: String, status initialStatus: String) async {
        await perform(initialStatus) {
            guard let runtime = self.gamingWineRuntime,
                  let bottle = self.steamBottle,
                  let steam = self.steamExecutable else {
                throw IndieError.notFound(L("尚未完成 Steam 安装"))
            }
            let provider = WineRuntimeProvider(manifest: runtime.manifest, root: runtime.root)
            let hasReusableSteam = self.steamSessionManager.state == .running &&
                SteamCompatibilityManager.isLoggedOn(in: bottle)
            if !hasReusableSteam {
                self.steamSessionManager.didStop()
                try await provider.prepareBottleForInstaller(bottle)
                try await provider.configureControllerSupport(in: bottle)
                guard let wrapper = SteamCompatibilityManager.bundledWrapperURL() else {
                    throw IndieError.notFound(L("缺少 Steam 界面兼容组件"))
                }
                _ = try SteamCompatibilityManager.prepare(bottle: bottle, wrapper: wrapper)
            }
            let analysis = GameAnalysis(
                identity: .init(executableName: "steam.exe"), architecture: .x86_64,
                directX: .none, antiCheat: .none, importedLibraries: []
            )
            let environment = hasReusableSteam
                ? (self.steamSessionManager.currentDescriptor?.environment ?? [:])
                : ["LANG": "zh_CN.UTF-8", "LC_ALL": "zh_CN.UTF-8", "WINEDEBUG": "-all"]
            let profile = LaunchProfile(
                runtimeID: runtime.manifest.id,
                preferredRenderer: .wineD3D,
                syncBackend: .wineserver,
                arguments: ["-noverifyfiles", "-no-cef-sandbox", "-silent", uri],
                environment: environment
            )
            let plan = try LaunchPlanBuilder.build(
                executable: steam,
                windowsExecutablePath: try WinePath.windowsPath(for: steam, in: bottle),
                bottle: bottle, profile: profile, analysis: analysis,
                recipe: nil, installed: .init(available: [.wineD3D])
            )
            let log = self.paths.logs.appendingPathComponent("\(plan.id)-steam-uri.log")
            _ = try await provider.launchDetached(plan, logURL: log)
            if !hasReusableSteam {
                self.steamSessionManager.didLaunch(
                    .init(
                        bottleID: bottle.id, runtimeID: runtime.manifest.id,
                        environment: plan.environment, virtualDesktop: nil
                    ),
                    reused: false
                )
            }
            self.status = L("Steam 已接收请求")
        }
    }
}
