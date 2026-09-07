import AppKit
import Combine
import IndieCore
import IndieCatalog
import IndieRuntime

/// Observes known executable paths. Never selects a window merely by its title,
/// steals focus, or requests capture permission from the background.
@available(macOS 26, *)
@MainActor
final class AutomaticFrameInterpolation: ObservableObject {
    static let shared = AutomaticFrameInterpolation()
    @Published private(set) var statuses: [String: String] = [:]
    private var targets: [String: String] = [:]
    private var states: [String: AutomaticInterpolationState] = [:]
    private var subscription: AnyCancellable?
    private var loop: Task<Void, Never>?
    private var revision = 0
    private struct Owner: Equatable {
        let game: String
        let run: String
        let window: String
    }
    private var owner: Owner?
    private let service = GameFrameInterpolation.shared

    private init() {
        service.onStopped = { [weak self] cause in self?.stopped(cause) }
    }

    func bind(model: MacGamingUncleAppModel) {
        guard subscription == nil else { return }
        subscription = Publishers.CombineLatest4(model.$gameConfigurations, model.$steamGames, model.$games, model.$bottles)
            .sink { [weak self, weak model] _, _, _, _ in
                // @Published sends before the stored property is updated.
                Task { @MainActor in
                    guard let self, let model else { return }
                    self.configure(model: model)
                }
            }
        configure(model: model)
    }

    private func configure(model: MacGamingUncleAppModel) {
        var updated: [String: String] = [:]
        if let bottle = model.steamBottle {
            for game in model.steamGames where model.gameConfigurations["steam:\(game.appID)"]?.frameInterpolation == true {
                guard let executable = try? SteamExecutableResolver.shippingExecutable(for: game),
                      let path = try? WinePath.windowsPath(for: executable, in: bottle) else { continue }
                updated["steam:\(game.appID)"] = path
            }
        }
        for game in model.games where model.gameConfigurations["local:\(game.id.uuidString)"]?.frameInterpolation == true {
            guard let bottle = model.bottles.first(where: { $0.id == game.bottleID }),
                  let path = try? WinePath.windowsPath(for: game.executableURL, in: bottle) else { continue }
            updated["local:\(game.id.uuidString)"] = path
        }
        guard updated != targets else { return }
        revision += 1
        if let owner, updated[owner.game] != targets[owner.game] {
            self.owner = nil
            service.stop(kind: .replaced)
        }
        states = states.filter { updated[$0.key] != nil && updated[$0.key] == targets[$0.key] }
        statuses = statuses.filter { updated[$0.key] != nil }
        targets = updated
        if targets.isEmpty { loop?.cancel(); loop = nil; return }
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.poll()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func rearm(gameID: String) {
        states[gameID]?.rearm()
        statuses[gameID] = L("已重新允许自动插帧，等待游戏窗口")
    }

    func shutdown() {
        revision += 1
        loop?.cancel(); loop = nil
        subscription?.cancel(); subscription = nil
        targets.removeAll(); states.removeAll(); owner = nil
        service.stop(kind: .replaced)
    }

    private func stopped(_ cause: GameFrameInterpolation.StopKind) {
        if cause == .replaced { return }
        if cause == .manual {
            // Global stop applies to currently observed runs, not future launches.
            for key in states.keys {
                states[key]?.suppressCurrentRun()
                if states[key]?.run != nil { statuses[key] = L("本次运行已手动停止；重新启动游戏或点击重新允许") }
            }
        } else if cause == .failure, let owner {
            states[owner.game]?.failed(window: owner.window)
            statuses[owner.game] = service.status
        }
        owner = nil
    }

    private func poll() async {
        let version = revision
        let processes: [GameProcessProbe.Process]
        do { processes = try await GameProcessProbe.processes() }
        catch { return } // A failed read is not a process exit.
        guard !Task.isCancelled, version == revision else { return }
        let foreground = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let permission = CGPreflightScreenCaptureAccess()
        let windows = permission
            ? (CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []) : []
        let topology = GameDisplaySnapshot.policy(retinaEnabled: false).topology
        for game in targets.keys.sorted() {
            guard let path = targets[game] else { continue }
            let matches = processes.filter { GameProcessProbe.matches(command: $0.command, windowsPath: path) }
            // If two prefixes expose the same Windows path, do not guess.
            let process = matches.count == 1 ? matches.first : nil
            var state = states[game] ?? AutomaticInterpolationState()
            let candidate = process.flatMap { Self.window(for: $0.pid, in: windows) }
            let key = candidate.map { "\($0.id):\($0.frame.width)x\($0.frame.height):\(topology)" }
            let focused = process != nil && foreground == process?.pid
            let observedRun = matches.count > 1 ? state.run : process?.identity
            let decision = state.observe(run: observedRun, window: key, foreground: focused)
            states[game] = state
            if let owner, owner.game == game,
               owner.run != process?.identity || owner.window != key || !focused || !permission {
                self.owner = nil
                service.stop(kind: .transient)
            }
            if state.isSuppressed {
                setStatus(game, L("本次运行已手动停止；重新启动游戏或点击重新允许")); continue
            }
            if let key, state.hasFailed(window: key) { continue }
            guard permission else {
                setStatus(game, L("等待录屏授权；请打开插帧面板完成授权，不会自动放行")); continue
            }
            guard let process else {
                setStatus(game, matches.isEmpty ? L("等待游戏启动，之后自动匹配窗口") : L("发现多个同路径进程，暂停自动匹配以免选错")); continue
            }
            guard focused else { setStatus(game, L("游戏在后台，返回后自动恢复插帧")); continue }
            guard let candidate, let key else { setStatus(game, L("等待可捕获的游戏窗口；支持窗口／无边框模式")); continue }
            guard decision == .start else { setStatus(game, L("等待游戏窗口尺寸稳定…")); continue }
            let expected = Owner(game: game, run: process.identity, window: key)
            if owner == expected && service.active { setStatus(game, service.status); continue }
            // A manually selected active stream retains control until stopped.
            guard !service.active else { continue }
            owner = expected
            setStatus(game, L("正在自动启动 2× 插帧…"))
            Task { [weak self] in
                guard let self, self.owner == expected else { return }
                await self.service.start(windowID: candidate.id, automatically: true, expectedPID: process.pid)
                if self.owner == expected && !self.service.active {
                    self.states[game]?.failed(window: key)
                    self.setStatus(game, self.service.status)
                    self.owner = nil
                }
            }
        }
    }

    private func setStatus(_ game: String, _ text: String) {
        if statuses[game] != text { statuses[game] = text }
    }

    private static func window(for pid: Int32, in windows: [[String: Any]]) -> (id: CGWindowID, frame: CGRect)? {
        let candidates: [(id: CGWindowID, frame: CGRect)] = windows.compactMap { info in
            guard (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid,
                  (info[kCGWindowLayer as String] as? Int) == 0,
                  let number = info[kCGWindowNumber as String] as? NSNumber,
                  let raw = info[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: raw), frame.width >= 640, frame.height >= 360 else { return nil }
            return (number.uint32Value, frame)
        }.sorted { $0.frame.width * $0.frame.height > $1.frame.width * $1.frame.height }
        // Equal-size windows are ambiguous (e.g. a splash and a new render window).
        if candidates.count > 1 && candidates[0].frame.size == candidates[1].frame.size { return nil }
        return candidates.first
    }
}
