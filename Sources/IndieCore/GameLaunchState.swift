import Foundation

public enum GameLaunchState: Sendable, Equatable {
    case idle, preparing, waiting, running, unconfirmed, failed

    public var blocksLaunch: Bool {
        switch self {
        case .preparing, .waiting, .running: true
        default: false
        }
    }
}
