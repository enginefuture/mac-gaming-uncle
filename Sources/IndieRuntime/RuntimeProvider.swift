import Foundation
import IndieCore

public protocol RuntimeProvider: Sendable {
    var manifest: RuntimeManifest { get }
    func probeInstallation(at root: URL) async -> [ProbeItem]
    func initializeBottle(_ bottle: BottleRecord) async throws
    func launch(_ plan: LaunchPlan, logURL: URL) async -> RunSession
}

public struct WineRuntimeProvider: RuntimeProvider, Sendable {
    public let manifest: RuntimeManifest
    public let root: URL
    private let subprocess: Subprocess

    public init(manifest: RuntimeManifest, root: URL, subprocess: Subprocess = Subprocess()) {
        self.manifest = manifest
        self.root = root
        self.subprocess = subprocess
    }

    public var wineBinary: URL {
        if let imported = LocalWineImporter.findWine(in: root) { return imported }
        let candidates = [
            root.appendingPathComponent("bin/wine64"),
            root.appendingPathComponent("bin/wine"),
            root.appendingPathComponent("Wine.app/Contents/Resources/wine/bin/wine64"),
            root.appendingPathComponent("Wine.app/Contents/Resources/wine/bin/wine"),
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) } ?? candidates[0]
    }

    public var wineserverBinary: URL {
        wineBinary.deletingLastPathComponent().appendingPathComponent("wineserver")
    }

    private var hostEnvironment: [String: String] {
        guard let frameworks = CommunitySikarugirBootstrapper.frameworksRoot(in: root) else { return [:] }
        return ["DYLD_LIBRARY_PATH": frameworks.path]
    }

    public func probeInstallation(at root: URL) async -> [ProbeItem] {
        let binary = wineBinary
        guard FileManager.default.isExecutableFile(atPath: binary.path) else {
            return [.init(id: "wine", title: "Wine", detail: "未找到 \(binary.path)", severity: .failure)]
        }
        do {
            let result = try await subprocess.run(binary, arguments: ["--version"], environment: hostEnvironment, timeout: .seconds(10))
            return [.init(id: "wine", title: "Wine", detail: result.stdout.trimmingCharacters(in: .whitespacesAndNewlines), severity: .pass)]
        } catch {
            return [.init(id: "wine", title: "Wine", detail: error.localizedDescription, severity: .failure)]
        }
    }

    public func initializeBottle(_ bottle: BottleRecord) async throws {
        try FileManager.default.createDirectory(at: bottle.root, withIntermediateDirectories: true)
        try await subprocess.run(
            wineBinary,
            arguments: ["wineboot", "--init"],
            environment: hostEnvironment.merging(["WINEPREFIX": bottle.root.path, "WINEDEBUG": "-all", "WINEDLLOVERRIDES": "mscoree,mshtml=", "LANG": "zh_CN.UTF-8", "LC_ALL": "zh_CN.UTF-8"]) { _, new in new },
            workingDirectory: bottle.root,
            timeout: .seconds(300)
        )
        try await registerCJKFonts(in: bottle)
        try await configureVulkanGraphics(in: bottle)
        await stopBottle(bottle)
        let rootDrive = bottle.root.appendingPathComponent("dosdevices/z:")
        if FileManager.default.fileExists(atPath: rootDrive.path) {
            try FileManager.default.removeItem(at: rootDrive)
        }
    }

    public func launch(_ plan: LaunchPlan, logURL: URL) async -> RunSession {
        await launch(plan, logURL: logURL, onStart: nil)
    }

    public func launch(
        _ plan: LaunchPlan,
        logURL: URL,
        onStart: (@Sendable (Int32) -> Void)?
    ) async -> RunSession {
        let startedAt = Date()
        let result: RunExit
        do {
            let execution = try await subprocess.run(
                wineBinary,
                arguments: [plan.windowsExecutablePath ?? plan.executable.path] + plan.arguments,
                environment: hostEnvironment.merging(plan.environment) { _, new in new }
                    .merging(["WINEPREFIX": plan.bottle.root.path]) { current, _ in current },
                workingDirectory: plan.executable.deletingLastPathComponent(),
                onStart: onStart,
                requireSuccess: false
            )
            let content = "[stdout]\n\(execution.stdout)\n[stderr]\n\(execution.stderr)"
            try content.data(using: .utf8)?.write(to: logURL, options: .atomic)
            result = .exited(execution.status)
        } catch is CancellationError {
            result = .cancelled
        } catch let error as IndieError {
            if case .timedOut = error { result = .timedOut }
            else { result = .launchFailed(error.localizedDescription) }
        } catch {
            result = .launchFailed(error.localizedDescription)
        }
        return RunSession(planID: plan.id, startedAt: startedAt, endedAt: Date(), result: result, logURL: logURL)
    }

    public func launchDetached(_ plan: LaunchPlan, logURL: URL) async throws -> Int32 {
        try await subprocess.launchDetached(
            wineBinary,
            arguments: [plan.windowsExecutablePath ?? plan.executable.path] + plan.arguments,
            environment: hostEnvironment.merging(plan.environment) { _, new in new }
                .merging(["WINEPREFIX": plan.bottle.root.path]) { current, _ in current },
            workingDirectory: plan.executable.deletingLastPathComponent(),
            logURL: logURL
        )
    }

    public func stopBottle(_ bottle: BottleRecord) async {
        _ = try? await subprocess.run(
            wineserverBinary,
            arguments: ["-k"],
            environment: hostEnvironment.merging(["WINEPREFIX": bottle.root.path, "WINEDEBUG": "-all", "WINEDLLOVERRIDES": "mscoree,mshtml="]) { _, new in new },
            timeout: .seconds(15),
            requireSuccess: false
        )
        _ = try? await subprocess.run(
            wineserverBinary,
            arguments: ["-w"],
            environment: hostEnvironment.merging(["WINEPREFIX": bottle.root.path, "WINEDEBUG": "-all", "WINEDLLOVERRIDES": "mscoree,mshtml="]) { _, new in new },
            timeout: .seconds(15),
            requireSuccess: false
        )
    }

    public func prepareBottleForInstaller(_ bottle: BottleRecord) async throws {
        try await registerCJKFonts(in: bottle)
        await stopBottle(bottle)
    }

    /// Uses Wine's Vulkan renderer for Direct3D 10/11 instead of macOS' legacy
    /// OpenGL path. The value is stored in the bottle so Steam child processes
    /// inherit the same renderer without per-game launch-option changes.
    public func configureVulkanGraphics(in bottle: BottleRecord) async throws {
        try await subprocess.run(
            wineBinary,
            arguments: Self.vulkanRegistryArguments,
            environment: hostEnvironment.merging([
                "WINEPREFIX": bottle.root.path,
                "WINEDEBUG": "-all",
                "LANG": "zh_CN.UTF-8",
                "LC_ALL": "zh_CN.UTF-8",
            ]) { _, new in new },
            workingDirectory: bottle.root,
            timeout: .seconds(30)
        )
    }

    /// GPTK's Wine build uses a fixed `crossover` profile name. Repointing its
    /// volatile environment keeps saves shared with the primary Wine runtime.
    public func configureWindowsUserProfile(in bottle: BottleRecord, username: String) async throws {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        guard !username.isEmpty, username.unicodeScalars.allSatisfy(allowed.contains) else {
            throw IndieError.invalidArgument("Windows 用户名包含不安全字符")
        }
        let values = [
            "USERNAME": username,
            "USERPROFILE": "C:\\users\\\(username)",
            "APPDATA": "C:\\users\\\(username)\\AppData\\Roaming",
            "LOCALAPPDATA": "C:\\users\\\(username)\\AppData\\Local",
            "HOMEPATH": "\\users\\\(username)",
        ]
        for key in values.keys.sorted() {
            try await subprocess.run(
                wineBinary,
                arguments: ["reg", "add", #"HKCU\Volatile Environment"#, "/v", key, "/t", "REG_SZ", "/d", values[key]!, "/f"],
                environment: hostEnvironment.merging(["WINEPREFIX": bottle.root.path, "WINEDEBUG": "-all"]) { _, new in new },
                workingDirectory: bottle.root,
                timeout: .seconds(30)
            )
        }
    }

    public static let vulkanRegistryArguments = [
        "reg", "add", #"HKCU\Software\Wine\Direct3D"#,
        "/v", "renderer", "/t", "REG_SZ", "/d", "vulkan", "/f",
    ]

    public static let vulkanEnvironment = [
        // Gcenx's macOS Wine builds require this recovery behavior because
        // Wine does not handle VK_ERROR_DEVICE_LOST itself.
        "MVK_CONFIG_RESUME_LOST_DEVICE": "1",
    ]

    private func registerCJKFonts(in bottle: BottleRecord) async throws {
        let registration = try BottleFonts.prepare(in: bottle)
        try await subprocess.run(
            wineBinary,
            arguments: ["regedit.exe", "/S", registration.registryWindowsPath],
            environment: hostEnvironment.merging([
                "WINEPREFIX": bottle.root.path,
                "WINEDEBUG": "-all",
                "WINEDLLOVERRIDES": "mscoree,mshtml=",
                "LANG": "zh_CN.UTF-8",
                "LC_ALL": "zh_CN.UTF-8",
            ]) { _, new in new },
            timeout: .seconds(30)
        )
    }
}
