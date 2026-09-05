import GameController
import IndieCore
import SwiftUI

struct ControllerConnectionSummary: View {
    @ObservedObject var manager: ControllerManager

    var body: some View {
        HStack(alignment: .top) {
            Label(
                manager.devices.isEmpty ? "未检测到已连接手柄" : "已连接 \(manager.devices.count) 个手柄",
                systemImage: manager.devices.isEmpty ? "gamecontroller" : "gamecontroller.fill"
            )
            Spacer()
            if !manager.devices.isEmpty {
                Text(manager.connectedNames.joined(separator: "、"))
                    .foregroundStyle(.secondary).multilineTextAlignment(.trailing)
            }
        }
        .font(.caption)
    }
}

struct ControllerManagementView: View {
    @EnvironmentObject private var model: MacGamingUncleAppModel

    var body: some View {
        ControllerManagementContent(manager: model.controllerManager)
    }
}

private struct ControllerManagementContent: View {
    @ObservedObject var manager: ControllerManager
    @AppStorage("defaultControllerMode") private var defaultMode = ControllerMode.automatic.rawValue
    @AppStorage("defaultControllerRumble") private var defaultRumble = true

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("手柄中心").font(.system(size: 34, weight: .bold, design: .rounded))
                    Text("连接、检查并管理用于 Windows 游戏的控制器。")
                        .foregroundStyle(IndiePalette.secondaryText)
                }
                Spacer()
                Button("macOS 手柄设置", systemImage: "gearshape") {
                    manager.openSystemControllerSettings()
                }
                if manager.isDiscovering {
                    Button("停止搜索", systemImage: "stop.fill") { manager.stopDiscovery() }
                } else {
                    Button("搜索蓝牙手柄", systemImage: "dot.radiowaves.left.and.right") {
                        manager.startDiscovery()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            HStack(spacing: 10) {
                if manager.isDiscovering { ProgressView().controlSize(.small) }
                Image(systemName: manager.devices.isEmpty ? "gamecontroller" : "checkmark.circle.fill")
                    .foregroundStyle(manager.devices.isEmpty ? IndiePalette.secondaryText : IndiePalette.green)
                Text(manager.status).font(.system(size: 13.5))
                    .foregroundStyle(IndiePalette.secondaryText)
                Spacer()
                Button("刷新", systemImage: "arrow.clockwise") { manager.refresh() }
                    .buttonStyle(.plain)
            }

            ScrollView {
                VStack(spacing: 18) {
                    defaultPolicyCard
                    if manager.devices.isEmpty { emptyState }
                    else {
                        ForEach(manager.devices) { device in
                            ControllerDeviceCard(device: device, manager: manager)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(34)
        .alert("手柄操作失败", isPresented: Binding(
            get: { manager.lastError != nil },
            set: { if !$0 { manager.lastError = nil } }
        )) {
            Button("知道了") { manager.lastError = nil }
        } message: {
            Text(manager.lastError ?? "")
        }
        .onAppear { manager.refresh() }
    }

    private var defaultPolicyCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("游戏默认策略", systemImage: "switch.2")
                    .font(.system(size: 17, weight: .semibold))
                Spacer()
                Text("可在每个游戏中覆盖").font(.caption).foregroundStyle(IndiePalette.secondaryText)
            }
            Divider().overlay(IndiePalette.border)
            Picker("默认输入模式", selection: $defaultMode) {
                Text("自动（Wine / Steam Input）").tag(ControllerMode.automatic.rawValue)
                Text("增强兼容（SDL HIDAPI）").tag(ControllerMode.enhanced.rawValue)
            }
            Toggle("默认启用震动", isOn: $defaultRumble)
            Text("增强模式会为 PlayStation、Switch 和通用 HID 手柄启用 SDL 兼容路径；游戏已有独立设置时，以游戏设置为准。")
                .font(.caption).foregroundStyle(IndiePalette.secondaryText)
        }
        .padding(18)
        .background(IndiePalette.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(IndiePalette.border))
    }

    private var emptyState: some View {
        VStack(spacing: 15) {
            Image(systemName: "gamecontroller").font(.system(size: 38, weight: .light))
                .foregroundStyle(IndiePalette.primary)
            Text("还没有连接手柄").font(.system(size: 19, weight: .semibold))
            Text("先让手柄进入配对模式，再点击“搜索蓝牙手柄”；有线手柄连接后会自动出现。")
                .multilineTextAlignment(.center).foregroundStyle(IndiePalette.secondaryText)
            HStack {
                Button("搜索蓝牙手柄") { manager.startDiscovery() }.buttonStyle(.borderedProminent)
                Button("打开系统设置") { manager.openSystemControllerSettings() }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 230)
        .background(IndiePalette.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(IndiePalette.border))
    }
}

private struct ControllerDeviceCard: View {
    let device: ControllerDeviceSnapshot
    @ObservedObject var manager: ControllerManager

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(spacing: 14) {
                Image(systemName: "gamecontroller.fill")
                    .font(.system(size: 24)).foregroundStyle(IndiePalette.primary)
                    .frame(width: 48, height: 48)
                    .background(IndiePalette.surfaceStrong, in: RoundedRectangle(cornerRadius: 13))
                VStack(alignment: .leading, spacing: 4) {
                    Text(device.name).font(.system(size: 17, weight: .semibold))
                    Text("\(device.category) · \(device.profile)")
                        .font(.system(size: 12.5)).foregroundStyle(IndiePalette.secondaryText)
                }
                Spacer()
                Label("已连接", systemImage: "checkmark.circle.fill")
                    .font(.caption).foregroundStyle(IndiePalette.green)
            }

            Divider().overlay(IndiePalette.border)

            HStack(spacing: 24) {
                Picker("玩家编号", selection: Binding(
                    get: { device.playerIndex },
                    set: { manager.assignPlayer($0, to: device.id) }
                )) {
                    Text("未分配").tag(-1)
                    Text("玩家 1").tag(0)
                    Text("玩家 2").tag(1)
                    Text("玩家 3").tag(2)
                    Text("玩家 4").tag(3)
                }
                .frame(maxWidth: 240)

                if let level = device.batteryLevel {
                    HStack(spacing: 8) {
                        Image(systemName: batteryIcon(level))
                        ProgressView(value: level).frame(width: 74)
                        Text("\(Int(level * 100))%")
                        if let state = device.batteryState { Text(state).foregroundStyle(IndiePalette.secondaryText) }
                    }
                    .font(.caption)
                }
                Spacer()
                if device.supportsMotion { Label("体感", systemImage: "gyroscope") }
                if device.supportsHaptics {
                    Button("测试震动", systemImage: "waveform") { manager.testRumble(device.id) }
                } else {
                    Text("无震动接口").foregroundStyle(IndiePalette.secondaryText)
                }
            }
            .font(.system(size: 13))

            HStack {
                Label("实时输入测试", systemImage: "scope")
                    .font(.system(size: 13, weight: .medium))
                Spacer()
                Text(device.lastInput ?? "按下按键或移动摇杆…")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(device.lastInput == nil ? IndiePalette.secondaryText : IndiePalette.green)
            }
            .padding(12)
            .background(Color.black.opacity(0.16), in: RoundedRectangle(cornerRadius: 10))
        }
        .padding(18)
        .background(IndiePalette.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(IndiePalette.border))
    }

    private func batteryIcon(_ level: Double) -> String {
        if level > 0.75 { return "battery.100percent" }
        if level > 0.35 { return "battery.50percent" }
        return "battery.25percent"
    }
}
