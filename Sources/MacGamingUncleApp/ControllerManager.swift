import AppKit
import CoreHaptics
import Foundation
import GameController

struct ControllerDeviceSnapshot: Identifiable, Equatable {
    let id: UUID
    let name: String
    let category: String
    let profile: String
    let playerIndex: Int
    let batteryLevel: Double?
    let batteryState: String?
    let supportsHaptics: Bool
    let supportsMotion: Bool
    let lastInput: String?
}

@MainActor
final class ControllerManager: ObservableObject {
    @Published private(set) var devices: [ControllerDeviceSnapshot] = []
    @Published private(set) var isDiscovering = false
    @Published private(set) var status = ""
    @Published var lastError: String?

    private var observers: [NSObjectProtocol] = []
    private var identifiers: [ObjectIdentifier: UUID] = [:]
    private var controllers: [UUID: GCController] = [:]
    private var lastInputs: [UUID: String] = [:]
    private var hapticEngines: [UUID: CHHapticEngine] = [:]
    private var hapticPlayers: [UUID: any CHHapticPatternPlayer] = [:]

    init() {
        let center = NotificationCenter.default
        for name in [
            Notification.Name.GCControllerDidConnect,
            .GCControllerDidDisconnect,
            .GCControllerDidBecomeCurrent,
            .GCControllerUserCustomizationsDidChange,
        ] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            })
        }
        refresh()
    }

    var connectedNames: [String] { devices.map(\.name) }

    func refresh() {
        let connected = GCController.controllers()
        let liveObjects = Set(connected.map(ObjectIdentifier.init))
        identifiers = identifiers.filter { liveObjects.contains($0.key) }
        controllers.removeAll(keepingCapacity: true)

        devices = connected.enumerated().map { index, controller in
            let objectID = ObjectIdentifier(controller)
            let id = identifiers[objectID] ?? UUID()
            identifiers[objectID] = id
            controllers[id] = controller
            installInputHandler(for: controller, id: id)
            return snapshot(for: controller, id: id, fallbackIndex: index)
        }
        if !isDiscovering {
            status = devices.isEmpty ? "尚未连接手柄" : "已连接 \(devices.count) 个手柄"
        }
    }

    func startDiscovery() {
        guard !isDiscovering else { return }
        isDiscovering = true
        status = "正在搜索可发现的蓝牙手柄…"
        GCController.startWirelessControllerDiscovery { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.isDiscovering = false
                self.refresh()
                self.status = self.devices.isEmpty ? "没有发现新手柄" : "搜索完成 · 已连接 \(self.devices.count) 个"
            }
        }
    }

    func stopDiscovery() {
        GCController.stopWirelessControllerDiscovery()
        isDiscovering = false
        refresh()
    }

    func assignPlayer(_ player: Int, to id: UUID) {
        guard let controller = controllers[id] else { return }
        controller.playerIndex = switch player {
        case 0: .index1
        case 1: .index2
        case 2: .index3
        case 3: .index4
        default: .indexUnset
        }
        status = player < 0 ? "已取消玩家编号" : "已分配给玩家 \(player + 1)"
        refresh()
    }

    func testRumble(_ id: UUID) {
        guard let controller = controllers[id], let haptics = controller.haptics,
              let engine = haptics.createEngine(withLocality: .default) else {
            lastError = "这个手柄没有向 macOS 提供震动能力"
            return
        }
        do {
            let event = CHHapticEvent(
                eventType: .hapticContinuous,
                parameters: [
                    .init(parameterID: .hapticIntensity, value: 0.75),
                    .init(parameterID: .hapticSharpness, value: 0.25),
                ],
                relativeTime: 0,
                duration: 0.35
            )
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try engine.start()
            try player.start(atTime: 0)
            hapticEngines[id] = engine
            hapticPlayers[id] = player
            status = "已向 \(deviceName(id)) 发送震动测试"
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(1))
                self?.hapticPlayers[id] = nil
                try? await self?.hapticEngines[id]?.stop()
                self?.hapticEngines[id] = nil
            }
        } catch {
            lastError = "震动测试失败：\(error.localizedDescription)"
        }
    }

    func openSystemControllerSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Game-Controller-Settings.extension"),
              NSWorkspace.shared.open(url) else {
            lastError = "无法打开 macOS 游戏控制器设置"
            return
        }
        status = "已打开 macOS 游戏控制器设置"
    }

    private func installInputHandler(for controller: GCController, id: UUID) {
        if let gamepad = controller.extendedGamepad {
            gamepad.valueChangedHandler = { [weak self] _, element in
                let label = element.localizedName ?? "手柄输入"
                Task { @MainActor in self?.recordInput(label, id: id) }
            }
        } else if let gamepad = controller.microGamepad {
            gamepad.valueChangedHandler = { [weak self] _, element in
                let label = element.localizedName ?? "手柄输入"
                Task { @MainActor in self?.recordInput(label, id: id) }
            }
        }
    }

    private func recordInput(_ label: String, id: UUID) {
        lastInputs[id] = label
        guard let index = devices.firstIndex(where: { $0.id == id }),
              let controller = controllers[id] else { return }
        devices[index] = snapshot(for: controller, id: id, fallbackIndex: index)
        status = "输入测试：\(label)"
    }

    private func snapshot(for controller: GCController, id: UUID, fallbackIndex: Int) -> ControllerDeviceSnapshot {
        let trimmedName = controller.vendorName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmedName?.isEmpty == false ? trimmedName! : "游戏手柄 \(fallbackIndex + 1)"
        let profile: String
        if controller.extendedGamepad != nil { profile = "扩展手柄 · 双摇杆与扳机" }
        else if controller.microGamepad != nil { profile = "标准手柄" }
        else { profile = "通用控制器" }
        let battery = controller.battery
        return ControllerDeviceSnapshot(
            id: id,
            name: name,
            category: controller.productCategory,
            profile: profile,
            playerIndex: controller.playerIndex.rawValue,
            batteryLevel: battery.map { Double($0.batteryLevel) },
            batteryState: battery.map { batteryStateName($0.batteryState) },
            supportsHaptics: controller.haptics != nil,
            supportsMotion: controller.motion != nil,
            lastInput: lastInputs[id]
        )
    }

    private func batteryStateName(_ state: GCDeviceBattery.State) -> String {
        switch state {
        case .charging: "充电中"
        case .discharging: "使用电池"
        case .full: "已充满"
        default: "状态未知"
        }
    }

    private func deviceName(_ id: UUID) -> String {
        devices.first(where: { $0.id == id })?.name ?? "手柄"
    }
}
