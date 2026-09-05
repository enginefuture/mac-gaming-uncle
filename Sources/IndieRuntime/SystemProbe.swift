import Foundation
import IndieCore
import Metal

public enum ProbeSeverity: String, Codable, Sendable {
    case pass
    case warning
    case failure
}

public struct ProbeItem: Codable, Identifiable, Sendable, Equatable {
    public let id: String
    public let title: String
    public let detail: String
    public let severity: ProbeSeverity

    public init(id: String, title: String, detail: String, severity: ProbeSeverity) {
        self.id = id
        self.title = title
        self.detail = detail
        self.severity = severity
    }
}

public struct SystemReport: Codable, Sendable, Equatable {
    public let generatedAt: Date
    public let macOSVersion: String
    public let architecture: CPUArchitecture
    public let model: String
    public let chip: String
    public let memoryBytes: UInt64
    public let rosettaInstalled: Bool
    public let metalDevice: String?
    public let items: [ProbeItem]

    public var isSupported: Bool { !items.contains { $0.severity == .failure } }
}

public actor SystemProbe {
    private let subprocess: Subprocess

    public init(subprocess: Subprocess = Subprocess()) { self.subprocess = subprocess }

    public func run() async -> SystemReport {
        let version = await value("/usr/bin/sw_vers", ["-productVersion"]) ?? ProcessInfo.processInfo.operatingSystemVersionString
        let machine = await value("/usr/bin/uname", ["-m"]) ?? "unknown"
        let architecture: CPUArchitecture = machine == "arm64" ? .arm64 : (machine == "x86_64" ? .x86_64 : .unknown)
        let model = await value("/usr/sbin/sysctl", ["-n", "hw.model"]) ?? "Unknown Mac"
        let chip = await value("/usr/sbin/sysctl", ["-n", "machdep.cpu.brand_string"]) ?? model
        let memory = UInt64(await value("/usr/sbin/sysctl", ["-n", "hw.memsize"]) ?? "0") ?? 0
        let rosetta = await packageInstalled("com.apple.pkg.RosettaUpdateAuto")
        let metalDevice = MTLCreateSystemDefaultDevice()?.name
        let major = Int(version.split(separator: ".").first ?? "0") ?? 0

        var items: [ProbeItem] = []
        items.append(.init(
            id: "architecture",
            title: "Apple Silicon",
            detail: architecture == .arm64 ? chip : L("Mac Gaming Uncle 仅支持 Apple Silicon"),
            severity: architecture == .arm64 ? .pass : .failure
        ))
        items.append(.init(
            id: "metal",
            title: "Metal GPU",
            detail: metalDevice ?? L("未检测到 Metal 设备"),
            severity: metalDevice == nil ? .failure : .pass
        ))
        items.append(.init(
            id: "macos",
            title: L("macOS 版本"),
            detail: version,
            severity: major >= 15 ? .pass : .failure
        ))
        items.append(.init(
            id: "rosetta",
            title: "Rosetta 2",
            detail: rosetta ? L("已安装") : L("运行 x86/x64 Windows 游戏前必须安装"),
            severity: rosetta ? .pass : .failure
        ))
        items.append(.init(
            id: "memory",
            title: L("内存"),
            detail: ByteCountFormatter.string(fromByteCount: Int64(memory), countStyle: .memory),
            severity: memory >= 16 * 1_073_741_824 ? .pass : .warning
        ))

        return SystemReport(
            generatedAt: Date(), macOSVersion: version, architecture: architecture,
            model: model, chip: chip, memoryBytes: memory, rosettaInstalled: rosetta,
            metalDevice: metalDevice, items: items
        )
    }

    private func value(_ executable: String, _ arguments: [String]) async -> String? {
        guard let result = try? await subprocess.run(URL(fileURLWithPath: executable), arguments: arguments, timeout: .seconds(5)) else { return nil }
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func packageInstalled(_ identifier: String) async -> Bool {
        guard let result = try? await subprocess.run(
            URL(fileURLWithPath: "/usr/sbin/pkgutil"), arguments: ["--pkg-info", identifier],
            timeout: .seconds(5), requireSuccess: false
        ) else { return false }
        return result.status == 0
    }
}
