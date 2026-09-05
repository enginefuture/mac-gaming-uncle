import Combine
import Foundation
import IndieCore

@MainActor
final class SteamSessionManager: ObservableObject {
    enum State: Equatable {
        case stopped
        case running
    }

    @Published private(set) var state: State = .stopped
    @Published private(set) var reuseCount = 0
    private var tracker = SteamSessionTracker()
    private let persistenceKey = "activeSteamSessionDescriptor"

    init() {
        guard let data = UserDefaults.standard.data(forKey: persistenceKey),
              let restored = try? IndieJSON.decoder().decode(SteamSessionDescriptor.self, from: data) else { return }
        tracker.didLaunch(restored, reused: false)
        state = .running
    }

    var currentDescriptor: SteamSessionDescriptor? { tracker.current }

    func canReuse(_ candidate: SteamSessionDescriptor) -> Bool {
        state == .running && tracker.canReuse(candidate)
    }

    func didLaunch(_ descriptor: SteamSessionDescriptor, reused: Bool) {
        tracker.didLaunch(descriptor, reused: reused)
        state = .running
        reuseCount = tracker.reuseCount
        if let data = try? IndieJSON.encoder().encode(descriptor) {
            UserDefaults.standard.set(data, forKey: persistenceKey)
        }
    }

    func didStop() {
        tracker.didStop()
        state = .stopped
        reuseCount = 0
        UserDefaults.standard.removeObject(forKey: persistenceKey)
    }
}

extension LaunchPlan {
    func withoutVirtualDesktop() -> LaunchPlan {
        LaunchPlan(
            id: id,
            executable: executable,
            windowsExecutablePath: windowsExecutablePath,
            bottle: bottle,
            runtimeID: runtimeID,
            renderer: renderer,
            arguments: arguments,
            environment: environment,
            warnings: warnings,
            virtualDesktop: nil,
            generatedAt: generatedAt
        )
    }
}
