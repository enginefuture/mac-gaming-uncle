import IndieCatalog
import IndieCore
import SwiftUI

struct SteamInstallProgress: View {
    let game: SteamGame
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(game.installationLabel, systemImage: "arrow.down.circle")
                .font(.callout.weight(.semibold))
            if let progress = game.downloadProgress, game.downloadIncomplete {
                ProgressView(value: progress)
                Text(progress, format: .percent.precision(.fractionLength(0)))
                    .font(.caption).monospacedDigit()
            } else {
                Text(L("安装完成后即可开始游戏")).font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(width: 220, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
