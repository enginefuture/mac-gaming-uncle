import AppKit
import Foundation
import IndieCatalog
import IndieCore
import IndieRuntime

@MainActor
final class IndieAppModel: ObservableObject {
    @Published var systemReport: SystemReport?
    @Published var games: [GameRecord] = []
    @Published var steamGames: [SteamGame] = []
    @Published var bottles: [BottleRecord] = []
    @Published var d3dMetal: [ImportedD3DMetal] = []
    @Published var wineRuntimes: [LocalWineRuntime] = []
    @Published var rendererOverlays: [RendererOverlay] = []
    @Published var isWorking = false
    @Published var isGPTKSetupRunning = false
    @Published var status = ""
    @Published var lastError: String?

    let paths = IndiePaths.userDefault
    private let store: StateStore
    private let probe = SystemProbe()
    private lazy var importer = GPTKImporter(paths: paths)
    private lazy var wineImporter = LocalWineImporter(paths: paths)
    private lazy var overlayImporter = RendererOverlayImporter(paths: paths)
    private lazy var communityWine = CommunityWineBootstrapper(paths: paths)
    private lazy var communityDXVK = CommunityDXVKBootstrapper(paths: paths)
    private lazy var communityGamingWine = CommunitySikarugirBootstrapper(paths: paths)
    private var recipeRepository = RecipeRepository(recipes: [])
    private var gptkSetupTask: Task<Void, Never>?

    var environmentReady: Bool {
        systemReport?.isSupported == true && !wineRuntimes.isEmpty
    }

    private var preferredGPTKRuntime: AppleGPTKRuntime? {
        AppleGPTKRuntime.discover(importedComponents: d3dMetal) ?? AppleGPTKRuntime.discover()
    }
    private var preferredD3DMetal: ImportedD3DMetal? {
        d3dMetal.first { $0.rendererRoot != nil }
    }
    private var gamingWineRuntime: LocalWineRuntime? {
        wineRuntimes.first { $0.manifest.id == CommunitySikarugirBootstrapper.runtimeID }
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
        Task { await refresh() }
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
            systemReport = await report
            games = try await savedGames
            bottles = try await savedBottles
            d3dMetal = try await imported
            wineRuntimes = await wine
            rendererOverlays = await overlays
            var loadedRecipes = try RecipeRepository.builtIn().recipes
            loadedRecipes.append(contentsOf: try RecipeRepository.load(from: paths.recipes).recipes)
            recipeRepository = RecipeRepository(recipes: loadedRecipes)
            try scanDefaultSteamLibrary()
            status = "准备就绪"
        } catch { present(error) }
    }

    func handleDeepLink(_ url: URL) {
        guard url.scheme?.lowercased() == "indie", url.host?.lowercased() == "launch",
              let appIDText = url.pathComponents.dropFirst().first,
              let appID = UInt64(appIDText) else {
            present(IndieError.invalidArgument("无法识别 Indie 链接：\(url.absoluteString)"))
            return
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            while self.isWorking { try? await Task.sleep(for: .milliseconds(100)) }
            guard let game = self.steamGames.first(where: { $0.appID == appID }) else {
                self.present(IndieError.notFound("Steam 游戏库中没有 AppID \(appID)"))
                return
            }
            await self.launchSteamGame(game)
        }
    }

    func prepareEnvironment() async {
        await perform("正在查找最新的兼容运行环境…") {
            guard self.systemReport?.isSupported == true else {
                throw IndieError.unsupported("这台 Mac 尚未通过环境检查，请打开高级设置查看原因")
            }
            let release = try await self.communityWine.latest()
            self.status = "正在下载 Wine \(release.version)（\(ByteCountFormatter.string(fromByteCount: release.downloadSize, countStyle: .file))）…"
            let installed = try await self.communityWine.installLatest()
            self.wineRuntimes = await self.wineImporter.installed()
            self.status = "游戏运行环境 \(installed.manifest.version) 已准备好"
        }
    }

    func importExecutable(_ url: URL) async {
        await perform("正在分析 \(url.lastPathComponent)…") {
            let analysis = try PEAnalyzer.analyze(at: url)
            let game = GameRecord(displayName: url.deletingPathExtension().lastPathComponent, source: .local, executableURL: url, analysis: analysis)
            try await self.store.saveGame(game)
            self.games = try await self.store.games()
            self.status = "已导入 \(url.lastPathComponent)：\(analysis.architecture.rawValue) / \(analysis.directX.rawValue)"
        }
    }

    func scanSteam(_ steamApps: URL) async {
        await perform("正在扫描 Steam 游戏库…") {
            self.steamGames = try SteamScanner.scan(steamApps: steamApps)
            self.status = "发现 \(self.steamGames.count) 个 Steam 游戏"
        }
    }

    func installSteam() async {
        await perform("正在从 Valve 官方 CDN 下载 Steam…") {
            guard let runtime = self.wineRuntimes.first else {
                throw IndieError.notFound("请先在“运行时”页面导入兼容的 macOS Wine 11 运行时")
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
            try await provider.prepareBottleForInstaller(bottle)
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
            self.status = "请在 Wine 窗口中完成 Steam 安装…"
            let session = await provider.launch(plan, logURL: log)
            try await self.store.saveSession(session)
            self.bottles = try await self.store.bottles()
            let steamApps = bottle.root.appendingPathComponent("drive_c/Program Files (x86)/Steam/steamapps", isDirectory: true)
            if FileManager.default.fileExists(atPath: steamApps.path) {
                self.steamGames = try SteamScanner.scan(steamApps: steamApps)
            }
            self.status = "Steam 安装流程已结束"
        }
    }

    func launchSteam(appID: UInt64? = nil) async {
        await perform(appID == nil ? "正在打开 Steam…" : "正在通过 Steam 启动游戏…") {
            guard let runtime = self.wineRuntimes.first,
                  let bottle = self.steamBottle,
                  let executable = self.steamExecutable else {
                throw IndieError.notFound("尚未完成 Steam 安装")
            }
            let provider = WineRuntimeProvider(manifest: runtime.manifest, root: runtime.root)
            guard let wrapper = SteamCompatibilityManager.bundledWrapperURL() else {
                throw IndieError.notFound("Indie 缺少 Steam 界面兼容组件，请重新安装应用")
            }
            await provider.stopBottle(bottle)
            try await provider.prepareBottleForInstaller(bottle)
            try await provider.configureVulkanGraphics(in: bottle)
            self.status = "正在准备 DirectX 11 图形兼容层…"
            let dxvk = try await self.communityDXVK.installLatest()
            _ = try BottleDXVKInstaller.install(overlay: dxvk, in: bottle)
            self.rendererOverlays = await self.overlayImporter.installed()
            _ = try SteamCompatibilityManager.prepare(bottle: bottle, wrapper: wrapper)
            let analysis = GameAnalysis(
                identity: GameIdentity(steamAppID: appID, executableName: "steam.exe"),
                architecture: .x86_64, directX: .none, antiCheat: .none, importedLibraries: []
            )
            var environment = WineRuntimeProvider.vulkanEnvironment
            environment["LANG"] = "zh_CN.UTF-8"
            environment["LC_ALL"] = "zh_CN.UTF-8"
            environment["DXVK_ASYNC"] = "0"
            environment["DXVK_LOG_PATH"] = self.paths.logs.appendingPathComponent("DXVK", isDirectory: true).path
            environment["DXVK_STATE_CACHE_PATH"] = self.paths.shaderCaches.appendingPathComponent("DXVK", isDirectory: true).path
            try FileManager.default.createDirectory(at: URL(fileURLWithPath: environment["DXVK_LOG_PATH"]!), withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: URL(fileURLWithPath: environment["DXVK_STATE_CACHE_PATH"]!), withIntermediateDirectories: true)
            let profile = LaunchProfile(
                runtimeID: runtime.manifest.id,
                preferredRenderer: .dxvk,
                arguments: SteamCompatibilityManager.launchArguments(appID: appID),
                environment: environment
            )
            let plan = try LaunchPlanBuilder.build(
                executable: executable,
                windowsExecutablePath: try WinePath.windowsPath(for: executable, in: bottle),
                bottle: bottle, profile: profile, analysis: analysis,
                recipe: nil, installed: InstalledRenderers(available: [.wineD3D, .dxvk])
            )
            let log = self.paths.logs.appendingPathComponent("\(plan.id.uuidString)-steam.log")
            self.status = appID == nil ? "Steam 正在运行；请登录并安装游戏" : "游戏正在运行"
            let session = await provider.launch(plan, logURL: log)
            try await self.store.saveSession(session)
            try self.scanDefaultSteamLibrary()
            self.status = "Steam 已退出"
        }
    }

    func launchSteamGame(_ game: SteamGame) async {
        await perform("正在为 \(game.name) 准备 D3DMetal…") {
            guard let bottle = self.steamBottle else {
                throw IndieError.notFound("尚未完成 Steam 安装")
            }
            guard let component = self.preferredD3DMetal,
                  let renderer = component.rendererRoot,
                  Self.majorVersion(component.version) >= 4 else {
                throw IndieError.notFound("请先使用“一键安装 GPTK 4”导入 Windows 游戏评估环境")
            }
            guard let gamingRuntime = self.gamingWineRuntime,
                  let frameworks = CommunitySikarugirBootstrapper.frameworksRoot(in: gamingRuntime.root) else {
                throw IndieError.notFound("D3DMetal 需要 Sikarugir Wine 10 游戏引擎，请重新运行 GPTK 4 一键安装")
            }
            guard let primaryRuntime = self.wineRuntimes.first else {
                throw IndieError.notFound("尚未安装 Wine 运行环境")
            }

            let primaryProvider = WineRuntimeProvider(manifest: primaryRuntime.manifest, root: primaryRuntime.root)
            let gamingProvider = WineRuntimeProvider(manifest: gamingRuntime.manifest, root: gamingRuntime.root)
            await primaryProvider.stopBottle(bottle)
            await gamingProvider.stopBottle(bottle)
            self.status = "正在修复 Steam 中文字体…"
            try await gamingProvider.prepareBottleForInstaller(bottle)
            guard let wrapper = SteamCompatibilityManager.bundledWrapperURL() else {
                throw IndieError.notFound("Indie 缺少 Steam 界面兼容组件，请重新安装应用")
            }
            _ = try SteamCompatibilityManager.prepare(bottle: bottle, wrapper: wrapper)
            guard let steam = self.steamExecutable else { throw IndieError.notFound("尚未完成 Steam 安装") }
            let steamAnalysis = GameAnalysis(
                identity: GameIdentity(steamAppID: game.appID, executableName: "steam.exe"),
                architecture: .x86_64, directX: .none, antiCheat: .none, importedLibraries: []
            )
            let shared = renderer.appendingPathComponent("external/libd3dshared.dylib")
            var environment = [
                "LANG": "zh_CN.UTF-8",
                "LC_ALL": "zh_CN.UTF-8",
                "WINEDEBUG": "-all",
                "GRAPHICS_BACKEND": "d3dmetal",
                "CX_GRAPHICS_BACKEND": "d3dmetal",
                "D3DMETAL_RUNTIME_DIR": renderer.path,
                "CX_APPLEGPTK_LIBD3DSHARED_PATH": shared.path,
                "CX_APPLEGPT_LIBD3DSHARED_PATH": shared.path,
                "WINEDLLPATH_PREPEND": renderer.appendingPathComponent("wine").path,
                "WINEDLLPATH": renderer.appendingPathComponent("wine").path,
                "DYLD_LIBRARY_PATH": frameworks.path,
                "DYLD_FALLBACK_LIBRARY_PATH": "\(renderer.appendingPathComponent("external").path):\(frameworks.path)",
            ]
            environment["D3DM_UNBUFFERED_OUTPUT"] = "0"
            environment["D3DM_SUPPORT_DXR"] = "0"
            environment["ROSETTA_ADVERTISE_AVX"] = "1"
            // Match the synchronization defaults used by the Sikarugir
            // wrapper. Indie invokes Wine directly, so these are not read
            // from the wrapper's Info.plist automatically.
            environment["WINEMSYNC"] = "1"
            environment["WINEESYNC"] = "1"
            let metalFXEnabled = UserDefaults.standard.bool(forKey: "metalFX")
            if metalFXEnabled {
                try D3DMetalRendererPreparer.enableMetalFX(
                    rendererRoot: renderer, version: component.version, bottle: bottle
                )
                environment["D3DM_ENABLE_METALFX"] = "1"
                environment["D3DMETAL_UPSCALER_PROFILE"] = "nvidia"
                environment["D3DM_VENDOR_ID"] = "4318"
                environment["D3DM_DEVICE_ID"] = "10370"
                environment["D3DM_DEVICE_DESCRIPTION"] = "NVIDIA GeForce RTX 4080"
            }
            let metal4Enabled = ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27
            if metal4Enabled {
                environment["D3DM_MTL4"] = "1"
            }
            let steamProfile = LaunchProfile(
                runtimeID: gamingRuntime.manifest.id,
                preferredRenderer: .d3dMetal,
                syncBackend: .msync,
                arguments: SteamCompatibilityManager.launchArguments(appID: nil),
                environment: environment,
                metalHUD: false
            )
            let steamPlan = try LaunchPlanBuilder.build(
                executable: steam,
                windowsExecutablePath: try WinePath.windowsPath(for: steam, in: bottle),
                bottle: bottle, profile: steamProfile, analysis: steamAnalysis,
                recipe: nil, installed: InstalledRenderers(available: [.d3dMetal])
            )
            let steamLog = self.paths.logs.appendingPathComponent("\(steamPlan.id.uuidString)-steam-d3dmetal.log")
            let steamStartedAt = Date()
            _ = try await gamingProvider.launchDetached(steamPlan, logURL: steamLog)
            self.status = "正在等待 Steam 登录…"
            let loginDeadline = Date().addingTimeInterval(90)
            while !SteamCompatibilityManager.isLoggedOn(in: bottle, since: steamStartedAt) {
                try Task.checkCancellation()
                if Date() >= loginDeadline { throw IndieError.timedOut("Steam 登录") }
                try await Task.sleep(for: .seconds(1))
            }

            let executable = try SteamExecutableResolver.shippingExecutable(for: game)
            let launcher = try SteamExecutableResolver.preferredExecutable(for: game)
            self.status = "正在快速检查游戏兼容性…"
            let analysis = try await Task.detached(priority: .userInitiated) {
                try PEAnalyzer.analyze(at: executable, steamAppID: game.appID)
            }.value
            let recipe = self.recipeRepository.match(analysis)
            let recipeProfile = recipe?.profiles.first { $0.renderer == .d3dMetal }
            let recipeArguments = recipeProfile?.arguments ?? []
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
            var gameEnvironment = environment
            gameEnvironment["SteamAppId"] = String(game.appID)
            gameEnvironment["SteamGameId"] = String(game.appID)
            var gameArguments = executable == launcher ? [] : [launcher.deletingPathExtension().lastPathComponent]
            if shaderPreparation.needsWarmupProtection,
               executable.lastPathComponent.lowercased().contains("-win64-shipping") {
                // D3DMetal may need more than UE's 120-second RenderThread
                // watchdog allowance while rebuilding a large pipeline cache.
                if !gameArguments.contains("-nothreadtimeout") && !recipeArguments.contains("-nothreadtimeout") {
                    gameArguments.append("-nothreadtimeout")
                }
            }
            let gameProfile = LaunchProfile(
                runtimeID: gamingRuntime.manifest.id,
                preferredRenderer: .d3dMetal,
                syncBackend: .msync,
                arguments: gameArguments,
                environment: gameEnvironment,
                metalHUD: recipeProfile?.metalHUD ?? UserDefaults.standard.bool(forKey: "metalHUD")
            )
            let gamePlan = try LaunchPlanBuilder.build(
                executable: executable,
                windowsExecutablePath: try WinePath.windowsPath(for: executable, in: bottle),
                bottle: bottle, profile: gameProfile, analysis: analysis,
                recipe: recipe, installed: InstalledRenderers(available: [.d3dMetal])
            )
            let log = self.paths.logs.appendingPathComponent("\(gamePlan.id.uuidString)-d3dmetal.log")
            self.status = shaderPreparation.needsWarmupProtection
                ? "\(game.name) 正在首次构建图形缓存，可能需要几分钟…"
                : "\(game.name) 正在通过 Steam + D3DMetal 4 运行"
            await Task.yield()
            let session = await gamingProvider.launch(gamePlan, logURL: log) { processID in
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(2))
                    NSRunningApplication(processIdentifier: processID)?.activate(options: [.activateAllWindows])
                }
            }
            try await self.store.saveSession(session)
            self.status = "游戏已退出：\(String(describing: session.result))"
        }
    }

    func rescanSteam() {
        do {
            try scanDefaultSteamLibrary()
            status = steamGames.isEmpty ? "尚未发现已安装的 Steam 游戏" : "发现 \(steamGames.count) 个 Steam 游戏"
        } catch { present(error) }
    }

    func importGPTK(_ url: URL) async {
        await perform("正在验证并导入 Apple D3DMetal…") {
            let component = try await self.importer.importFromAppleImage(url)
            self.d3dMetal = try await self.importer.installedComponents()
            self.status = "D3DMetal \(component.version) 已导入"
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
        await perform("正在验证并导入 Wine…") {
            let runtime = try await self.wineImporter.importRuntime(from: url)
            self.wineRuntimes = await self.wineImporter.installed()
            self.status = "Wine \(runtime.manifest.version) 已导入"
        }
    }

    func importRenderer(_ kind: RendererKind, from url: URL) async {
        await perform("正在导入 \(kind.rawValue)…") {
            let overlay = try await self.overlayImporter.importOverlay(kind, from: url)
            self.rendererOverlays = await self.overlayImporter.installed()
            self.status = "\(overlay.kind.rawValue) \(overlay.version) 已导入"
        }
    }

    func play(_ game: GameRecord) async {
        await perform("正在准备 \(game.displayName)…") {
            guard let runtime = self.wineRuntimes.first else {
                throw IndieError.notFound("请先在“运行时”页面导入兼容的 macOS Wine 11 运行时")
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
            if let metal = self.d3dMetal.first {
                rendererSet.insert(.d3dMetal)
                overlays[.d3dMetal] = metal.root
            }
            for overlay in self.rendererOverlays where overlays[overlay.kind] == nil {
                rendererSet.insert(overlay.kind)
                overlays[overlay.kind] = overlay.root
            }
            let profile = LaunchProfile(runtimeID: runtime.manifest.id, metalHUD: UserDefaults.standard.bool(forKey: "metalHUD"))
            let recipe = self.recipeRepository.match(game.analysis)
            let plan = try LaunchPlanBuilder.build(
                executable: game.executableURL, bottle: bottle, profile: profile,
                analysis: game.analysis, recipe: recipe,
                installed: InstalledRenderers(available: rendererSet, overlayPaths: overlays)
            )
            try self.paths.createDirectories()
            let log = self.paths.logs.appendingPathComponent("\(plan.id.uuidString).log")
            self.status = "正在运行 \(game.displayName)…"
            let session = await provider.launch(plan, logURL: log)
            try await self.store.saveSession(session)
            self.status = "游戏已退出：\(String(describing: session.result))"
        }
    }

    private func perform(_ initialStatus: String, operation: @escaping @MainActor () async throws -> Void) async {
        guard !isWorking else { return }
        isWorking = true
        lastError = nil
        status = initialStatus
        defer { isWorking = false }
        do { try await operation() }
        catch is CancellationError { status = "已取消 GPTK 安装" }
        catch { present(error) }
    }

    private func setupLatestGPTK() async {
        isGPTKSetupRunning = true
        defer { isGPTKSetupRunning = false }
        await perform("正在查找 GPTK 4 安装镜像…") {
            let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
            var snapshot = GPTKDownloadWatcher.scan(downloads)
            if snapshot.completedImage == nil {
                let downloadPage = URL(string: "https://developer.apple.com/download/all/?q=Evaluation%20environment%20for%20Windows%20games")!
                guard NSWorkspace.shared.open(downloadPage) else {
                    throw IndieError.processFailed(executable: "浏览器", status: 1, stderr: "无法打开 Apple Developer 下载页")
                }
                self.status = "请在 Apple 官方页面点击 GPTK 4 下载；Indie 会自动接管后续安装"
                let deadline = Date().addingTimeInterval(45 * 60)
                while snapshot.completedImage == nil {
                    try Task.checkCancellation()
                    if Date() >= deadline { throw IndieError.timedOut("GPTK 4 下载") }
                    if let partial = snapshot.partialDownload {
                        let size = ByteCountFormatter.string(fromByteCount: snapshot.partialSize, countStyle: .file)
                        self.status = "正在等待 \(partial.deletingPathExtension().lastPathComponent) 下载完成（\(size)）…"
                    }
                    try await Task.sleep(for: .seconds(2))
                    snapshot = GPTKDownloadWatcher.scan(downloads)
                }
            }
            guard let image = snapshot.completedImage else {
                throw IndieError.notFound("下载目录中没有找到 GPTK 4 镜像")
            }
            self.status = "正在验证 Apple 签名并安装 GPTK 4…"
            let component = try await self.importer.importFromAppleImage(image)
            self.d3dMetal = try await self.importer.installedComponents()
            let version = component.version.split(whereSeparator: { !$0.isNumber }).first.flatMap { Int($0) } ?? 0
            guard version >= 4 else {
                throw IndieError.invalidData("下载的 D3DMetal 版本是 \(component.version)，不是 GPTK 4")
            }
            guard component.rendererRoot != nil else {
                throw IndieError.invalidData("GPTK 4 镜像缺少 D3DMetal Wine Bridge；请确认下载的是 Windows 游戏评估环境")
            }
            self.status = "正在安装支持现代 Steam 的开源游戏引擎（约 250 MB）…"
            _ = try await self.communityGamingWine.installLatest()
            self.wineRuntimes = await self.wineImporter.installed()
            self.status = "GPTK \(component.version) 已验证并安装，可以启动游戏"
        }
    }

    private static func majorVersion(_ value: String) -> Int {
        value.split(whereSeparator: { !$0.isNumber }).first.flatMap { Int($0) } ?? 0
    }

    private func present(_ error: Error) {
        lastError = error.localizedDescription
        status = "操作失败"
    }

    private func scanDefaultSteamLibrary() throws {
        guard let bottle = steamBottle else { return }
        let steamApps = bottle.root.appendingPathComponent("drive_c/Program Files (x86)/Steam/steamapps", isDirectory: true)
        guard FileManager.default.fileExists(atPath: steamApps.path) else { return }
        steamGames = try SteamScanner.scan(steamApps: steamApps)
    }
}
