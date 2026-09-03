import Foundation
import IndieCore

public struct RendererOverlay: Codable, Sendable, Identifiable, Equatable {
    public var id: String { "\(kind.rawValue)@\(version)" }
    public let kind: RendererKind
    public let version: String
    public let root: URL
    public let importedAt: Date
}

public actor RendererOverlayImporter {
    private let paths: IndiePaths

    public init(paths: IndiePaths) { self.paths = paths }

    public func importOverlay(_ kind: RendererKind, from source: URL) throws -> RendererOverlay {
        guard [.dxmt, .dxvk, .vkd3d].contains(kind) else {
            throw IndieError.invalidArgument("该渲染器不使用开源 DLL Overlay 导入")
        }
        try paths.createDirectories()
        let files = Self.fileNames(under: source)
        let required: Set<String> = switch kind {
        case .dxmt: ["dxgi.dll", "d3d11.dll"]
        // DXVK-macOS intentionally uses Wine's DXGI implementation; its release
        // packages contain only the D3D10/11 DLLs.
        case .dxvk: ["d3d10core.dll", "d3d11.dll"]
        case .vkd3d: ["d3d12.dll"]
        default: []
        }
        guard required.isSubset(of: files) else {
            throw IndieError.invalidData("\(kind.rawValue) Overlay 缺少：\(required.subtracting(files).sorted().joined(separator: ", "))")
        }
        let version = Self.version(from: source.lastPathComponent)
        let destination = paths.overlays.appendingPathComponent(kind.rawValue, isDirectory: true).appendingPathComponent(version, isDirectory: true)
        let metadata = destination.appendingPathComponent("overlay.json")
        if let data = try? Data(contentsOf: metadata),
           let existing = try? IndieJSON.decoder().decode(RendererOverlay.self, from: data) { return existing }
        let staging = paths.overlays.appendingPathComponent(".overlay-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.copyItem(at: source, to: staging)
            let overlay = RendererOverlay(kind: kind, version: version, root: destination, importedAt: Date())
            try IndieJSON.encoder(pretty: true).encode(overlay).write(to: staging.appendingPathComponent("overlay.json"), options: .atomic)
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: staging, to: destination)
            return overlay
        } catch {
            try? FileManager.default.removeItem(at: staging)
            throw error
        }
    }

    public func installed() -> [RendererOverlay] {
        RendererKind.allCases.flatMap { kind -> [RendererOverlay] in
            let base = paths.overlays.appendingPathComponent(kind.rawValue, isDirectory: true)
            return ((try? FileManager.default.contentsOfDirectory(at: base, includingPropertiesForKeys: nil)) ?? []).compactMap { directory in
                let metadata = directory.appendingPathComponent("overlay.json")
                guard let data = try? Data(contentsOf: metadata),
                      let stored = try? IndieJSON.decoder().decode(RendererOverlay.self, from: data) else { return nil }
                return RendererOverlay(kind: stored.kind, version: stored.version, root: directory, importedAt: stored.importedAt)
            }
        }.sorted { $0.importedAt > $1.importedAt }
    }

    private static func fileNames(under root: URL) -> Set<String> {
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { return [] }
        return Set(enumerator.compactMap { ($0 as? URL)?.lastPathComponent.lowercased() })
    }

    private static func version(from name: String) -> String {
        let pattern = #"[0-9]+(?:\.[0-9]+)+"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)),
              let range = Range(match.range, in: name) else {
            return ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        }
        return String(name[range])
    }
}
