import Foundation
import IndieCore

/// A complete Apple evaluation runtime is required for D3DMetal. The framework
/// alone is insufficient because its PE and Unix bridge DLLs must match Wine's
/// internal ABI. Mac Gaming Uncle therefore discovers the user-installed GPTK app and runs
/// D3DMetal games with that complete runtime without redistributing it.
public struct AppleGPTKRuntime: Sendable, Equatable {
    public let rootURL: URL
    public let version: String

    public var majorVersion: Int {
        version.split(whereSeparator: { !$0.isNumber }).first.flatMap { Int($0) } ?? 0
    }

    public var wineRoot: URL {
        let bundled = rootURL.appendingPathComponent("Contents/Resources/wine", isDirectory: true)
        return FileManager.default.fileExists(atPath: bundled.path) ? bundled : rootURL
    }

    public var manifest: RuntimeManifest {
        RuntimeManifest(
            id: "com.apple.game-porting-toolkit.local",
            displayName: "Apple Game Porting Toolkit \(version)",
            version: Self.semanticVersion(from: version),
            channel: .experimental,
            hostArchitecture: .x86_64,
            minimumMacOS: SemanticVersion(major: 14, minor: 2),
            capabilities: RuntimeCapabilities(
                architectures: [.x86_64], renderers: [.d3dMetal],
                supportsWoW64: false, supportsMSync: false
            ),
            artifacts: [],
            licenses: [LicenseDescriptor(
                identifier: "LicenseRef-Apple-GPTK",
                name: "Apple Game Porting Toolkit License",
                sourceURL: URL(string: "https://developer.apple.com/games/game-porting-toolkit/")!,
                correspondingSourceURL: nil
            )],
            publishedAt: Date(timeIntervalSince1970: 0)
        )
    }

    public static func discover(applicationsDirectory: URL = URL(fileURLWithPath: "/Applications", isDirectory: true)) -> AppleGPTKRuntime? {
        let app = applicationsDirectory.appendingPathComponent("Game Porting Toolkit.app", isDirectory: true)
        let wine = app.appendingPathComponent("Contents/Resources/wine/bin/wine64")
        let framework = app.appendingPathComponent("Contents/Resources/wine/lib/external/D3DMetal.framework", isDirectory: true)
        let shared = app.appendingPathComponent("Contents/Resources/wine/lib/external/libd3dshared.dylib")
        guard FileManager.default.isExecutableFile(atPath: wine.path),
              FileManager.default.fileExists(atPath: framework.path),
              FileManager.default.fileExists(atPath: shared.path) else { return nil }
        let version = bundleVersion(framework) ?? bundleVersion(app) ?? "unknown"
        return AppleGPTKRuntime(rootURL: app, version: version)
    }

    public static func discover(importedComponents: [ImportedD3DMetal]) -> AppleGPTKRuntime? {
        for component in importedComponents.sorted(by: { $0.version > $1.version }) {
            guard let runtime = component.runtimeRoot,
                  FileManager.default.isExecutableFile(atPath: runtime.appendingPathComponent("bin/wine64").path),
                  FileManager.default.fileExists(atPath: runtime.appendingPathComponent("lib/wine", isDirectory: true).path) else { continue }
            return AppleGPTKRuntime(rootURL: runtime, version: component.version)
        }
        return nil
    }

    private static func bundleVersion(_ bundle: URL) -> String? {
        for relative in ["Resources/Info.plist", "Versions/A/Resources/Info.plist", "Contents/Info.plist"] {
            let url = bundle.appendingPathComponent(relative)
            guard let data = try? Data(contentsOf: url),
                  let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { continue }
            if let version = plist["CFBundleShortVersionString"] as? String ?? plist["CFBundleVersion"] as? String {
                return version
            }
        }
        return nil
    }

    private static func semanticVersion(from value: String) -> SemanticVersion {
        let numbers = value.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        return SemanticVersion(
            major: numbers.indices.contains(0) ? numbers[0] : 0,
            minor: numbers.indices.contains(1) ? numbers[1] : 0,
            patch: numbers.indices.contains(2) ? numbers[2] : 0,
            prerelease: value.contains("b") ? "beta" : nil
        )
    }
}
