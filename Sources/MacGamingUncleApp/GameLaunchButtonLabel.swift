import IndieCore
import SwiftUI

struct GameLaunchButtonLabel: View {
    let state: GameLaunchState
    var body: some View {
        HStack(spacing: 8) {
            if state == .preparing || state == .waiting {
                ProgressView().controlSize(.small)
            } else if state == .running {
                Image(systemName: "checkmark.circle.fill")
            } else {
                UncleAppleMark(size: 24)
            }
            Text(title)
        }
        .accessibilityLabel(title)
    }
    private var title: String {
        switch state {
        case .idle: L("开始游戏")
        case .preparing: L("正在启动…")
        case .waiting: L("等待游戏启动…")
        case .running: L("游戏运行中")
        case .failed: L("启动失败，重试")
        case .unconfirmed: L("启动未确认，重试")
        }
    }
}
