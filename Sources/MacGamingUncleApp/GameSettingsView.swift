import IndieCore
import SwiftUI

struct GameSettingsTarget: Identifiable {
    let id: String
    let name: String
    let detail: String
    let configuration: GameConfiguration
}

private enum RendererChoice: String, CaseIterable, Identifiable {
    case automatic, d3dMetal, dxmt, dxvk, wineD3D, vkd3d
    var id: String { rawValue }

    init(_ renderer: RendererKind?) {
        switch renderer {
        case .d3dMetal: self = .d3dMetal
        case .dxmt: self = .dxmt
        case .dxvk: self = .dxvk
        case .wineD3D: self = .wineD3D
        case .vkd3d: self = .vkd3d
        case nil: self = .automatic
        }
    }

    var renderer: RendererKind? {
        switch self {
        case .automatic: nil
        case .d3dMetal: .d3dMetal
        case .dxmt: .dxmt
        case .dxvk: .dxvk
        case .wineD3D: .wineD3D
        case .vkd3d: .vkd3d
        }
    }

    var label: String {
        switch self {
        case .automatic: "自动（推荐）"
        case .d3dMetal: "D3DMetal"
        case .dxmt: "DXMT"
        case .dxvk: "DXVK"
        case .wineD3D: "WineD3D"
        case .vkd3d: "VKD3D"
        }
    }
}

struct GameSettingsView: View {
    @EnvironmentObject private var model: MacGamingUncleAppModel
    @Environment(\.dismiss) private var dismiss
    let target: GameSettingsTarget

    @State private var configuration: GameConfiguration
    @State private var useVirtualDesktop: Bool
    @State private var width: String
    @State private var height: String
    @State private var renderer: RendererChoice
    @State private var argumentLines: String

    init(target: GameSettingsTarget) {
        self.target = target
        let resolution = target.configuration.virtualDesktop
        _configuration = State(initialValue: target.configuration)
        _useVirtualDesktop = State(initialValue: resolution != nil)
        _width = State(initialValue: String(resolution?.width ?? 1920))
        _height = State(initialValue: String(resolution?.height ?? 1080))
        _renderer = State(initialValue: RendererChoice(target.configuration.preferredRenderer))
        _argumentLines = State(initialValue: target.configuration.arguments.joined(separator: "\n"))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(target.name).font(.system(size: 24, weight: .bold, design: .rounded))
                    Text("独立游戏设置 · \(target.detail)").font(.system(size: 13)).foregroundStyle(.secondary)
                }
                Spacer()
                Button("恢复默认") { reset() }
                Button("取消") { dismiss() }
                Button("保存") { save() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
            .padding(24)
            Divider()

            Form {
                Section("显示") {
                    Toggle("使用 Wine 虚拟桌面", isOn: $useVirtualDesktop)
                    Text("为这个游戏创建固定尺寸的 Windows 桌面，可避免 Retina 缩放导致的画面拉伸和鼠标错位。")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        TextField("宽度", text: $width).frame(width: 100)
                        Text("×").foregroundStyle(.secondary)
                        TextField("高度", text: $height).frame(width: 100)
                        Text("像素").foregroundStyle(.secondary)
                        Spacer()
                        Menu("常用分辨率") {
                            resolutionButton(1280, 720)
                            resolutionButton(1600, 900)
                            resolutionButton(1920, 1080)
                            resolutionButton(2560, 1440)
                            resolutionButton(3840, 2160)
                        }
                    }
                    .disabled(!useVirtualDesktop)
                }

                Section("图形") {
                    Picker("渲染后端", selection: $renderer) {
                        ForEach(rendererChoices) { choice in Text(choice.label).tag(choice) }
                    }
                    Picker("同步方式", selection: $configuration.syncBackend) {
                        Text("自动（推荐）").tag(SyncBackend.automatic)
                        Text("MSync").tag(SyncBackend.msync)
                        Text("Wine Server").tag(SyncBackend.wineserver)
                    }
                    overridePicker("Apple Metal HUD", selection: $configuration.metalHUD)
                    overridePicker("MetalFX / DLSS", selection: $configuration.metalFX)
                    overridePicker("Metal 4", selection: $configuration.metal4)
                }

                Section("手柄") {
                    Picker("输入模式", selection: $configuration.controllerMode) {
                        Text("自动（Wine / Steam Input）").tag(ControllerMode.automatic)
                        Text("增强兼容（SDL HIDAPI）").tag(ControllerMode.enhanced)
                    }
                    Toggle("启用手柄震动", isOn: $configuration.controllerRumble)
                        .disabled(configuration.controllerMode != .enhanced)
                    ControllerConnectionSummary(manager: model.controllerManager)
                    Text("Xbox、PlayStation、Switch Pro 及标准 USB/蓝牙手柄由 macOS 检测，再交给 Wine；部分 Steam 游戏仍需在 Steam 中启用 Steam Input。")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section("启动参数") {
                    TextEditor(text: $argumentLines).font(.system(.body, design: .monospaced)).frame(minHeight: 70)
                    Text("每行一个参数；仅应用于这个游戏。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
        }
        .frame(minWidth: 660, minHeight: 680)
        .preferredColorScheme(.dark)
    }

    private var rendererChoices: [RendererChoice] {
        RendererChoice.allCases.filter { choice in
            choice == .automatic || choice == renderer ||
                choice.renderer.map(model.availableRendererKinds.contains) == true
        }
    }

    @ViewBuilder
    private func overridePicker(_ title: String, selection: Binding<GameSettingOverride>) -> some View {
        Picker(title, selection: selection) {
            Text("跟随全局设置").tag(GameSettingOverride.inherit)
            Text("开启").tag(GameSettingOverride.enabled)
            Text("关闭").tag(GameSettingOverride.disabled)
        }
    }

    private func resolutionButton(_ width: Int, _ height: Int) -> some View {
        Button("\(width) × \(height)") {
            self.width = String(width)
            self.height = String(height)
        }
    }

    private func save() {
        if useVirtualDesktop {
            configuration.virtualDesktop = GameResolution(
                width: Int(width) ?? 0,
                height: Int(height) ?? 0
            )
        } else {
            configuration.virtualDesktop = nil
        }
        configuration.preferredRenderer = renderer.renderer
        configuration.arguments = argumentLines
            .split(whereSeparator: \Character.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        Task {
            await model.saveGameConfiguration(configuration)
            if model.lastError == nil { dismiss() }
        }
    }

    private func reset() {
        configuration = model.defaultGameConfiguration(id: target.id)
        useVirtualDesktop = false
        width = "1920"
        height = "1080"
        renderer = .automatic
        argumentLines = ""
    }
}
