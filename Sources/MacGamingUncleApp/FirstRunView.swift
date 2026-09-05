import IndieCore
import SwiftUI

enum FirstRunStage { case checking, environment, steam, complete }

struct FirstRunView: View {
    @EnvironmentObject private var model: MacGamingUncleAppModel

    var body: some View {
        ZStack {
            Color.black.opacity(0.72).ignoresSafeArea()
            ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 12) {
                    UncleAppleMark(size: 40)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(L("欢迎来到 Mac Gaming Uncle")).font(.title2.bold())
                        Text(L("准备好环境，登录 Steam，就可以开始玩了。"))
                            .foregroundStyle(.secondary)
                    }
                }
                HStack {
                    Label(L("1  安装游戏环境"), systemImage: model.onboardingStage == .steam ? "checkmark.circle.fill" : "shippingbox")
                        .foregroundStyle(model.onboardingStage == .steam ? .green : .blue)
                    Spacer()
                    Image(systemName: "arrow.right").foregroundStyle(.secondary)
                    Spacer()
                    Label(L("2  登录 Steam"), systemImage: "person.crop.circle")
                        .foregroundStyle(model.onboardingStage == .steam ? .blue : .secondary)
                }.font(.headline)
                Divider()
                LanguagePicker()
                if model.onboardingStage == .steam {
                    Text(L("环境已就绪，连接你的游戏库")).font(.title.bold())
                    Text(L("Steam 会在独立的官方窗口中完成登录。Mac Gaming Uncle 不收集你的密码或验证码。"))
                        .foregroundStyle(.secondary)
                    Label(L("游戏环境安装完成"), systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    Label(L("登录后自动同步游戏库"), systemImage: "rectangle.stack")
                } else {
                    Text(L("正在为你准备游戏环境")).font(.title.bold())
                    component("Rosetta 2", detail: L("运行 Windows 游戏所需的指令转译"), ready: model.systemReport?.rosettaInstalled == true)
                    component(L("Wine 与手柄支持"), detail: L("Windows 兼容层与 SDL / XInput"), ready: model.onboardingWineReady)
                    component("DXMT", detail: L("备用图形兼容组件"), ready: model.onboardingDXMTReady)
                    component("GPTK 4 / D3DMetal", detail: L("Apple 图形组件 · 下载后自动校验并导入"), ready: model.onboardingGraphicsReady)
                    Text(L("仅首次需要安装。所有组件自动下载、校验并安装。Apple 组件保留其原始许可，仅用于非商业用途。"))
                        .font(.callout).foregroundStyle(.secondary)
                    Link(L("查看 Apple 组件许可"), destination: URL(string: "https://download.pingclaws.com/mac-gaming-uncle/gptk/4.0b2/License.rtf")!)
                        .font(.caption)
                }
                HStack(alignment: .top, spacing: 12) {
                    if model.onboardingBusy || model.onboardingStage == .checking { ProgressView().controlSize(.small) }
                    VStack(alignment: .leading, spacing: 6) {
                        Text(model.onboardingMessage)
                        if model.isGPTKSetupRunning { Text(model.status).font(.caption).foregroundStyle(.secondary) }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.padding(16).background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
                if let error = model.onboardingError {
                    Text(error).foregroundStyle(.orange).textSelection(.enabled)
                    HStack {
                        Text(L("已完成的安装会保留。")).foregroundStyle(.secondary)
                        Spacer()
                        Button(L("重试并继续")) { model.retryOnboarding() }
                            .buttonStyle(.borderedProminent).disabled(model.onboardingBusy)
                    }
                }
            }
            .padding(32)
            }
            .frame(width: 660).frame(maxHeight: 650)
            .background(IndiePalette.topBar, in: RoundedRectangle(cornerRadius: 24))
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(IndiePalette.border))
            .shadow(radius: 35)
        }
    }

    private func component(_ title: String, detail: String, ready: Bool) -> some View {
        HStack(spacing: 14) {
            Image(systemName: ready ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(ready ? .green : .secondary).font(.title2)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(ready ? L("已就绪") : L("待安装")).font(.caption).foregroundStyle(.secondary)
        }
    }
}
