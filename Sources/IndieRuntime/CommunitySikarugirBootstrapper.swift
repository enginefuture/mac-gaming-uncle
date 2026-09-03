import Foundation
import IndieCore

public actor CommunitySikarugirBootstrapper {
    public static let runtimeID = "org.indie.wine.sikarugir"
    public static let version = SemanticVersion(major: 10, minor: 0, patch: 6)

    private let paths: IndiePaths
    private let session: URLSession

    public init(paths: IndiePaths, session: URLSession = .shared) {
        self.paths = paths
        self.session = session
    }

    public func installLatest() async throws -> LocalWineRuntime {
        let manifest = Self.manifest
        let destination = try await RuntimeInstaller(paths: paths, session: session).install(
            manifest: manifest,
            publicKeyBase64: nil,
            allowUnsignedDevelopmentManifest: true
        )
        guard LocalWineImporter.findWine(in: destination) != nil,
              Self.frameworksRoot(in: destination) != nil else {
            throw IndieError.invalidData("Sikarugir 游戏运行环境不完整")
        }
        let installed = LocalWineRuntime(manifest: manifest, root: destination, importedAt: Date())
        try IndieJSON.encoder(pretty: true).encode(installed)
            .write(to: destination.appendingPathComponent("local-runtime.json"), options: .atomic)
        return installed
    }

    public static func frameworksRoot(in runtimeRoot: URL) -> URL? {
        let candidates = [
            runtimeRoot.appendingPathComponent("Template-1.0.11.app/Contents/Frameworks", isDirectory: true),
            runtimeRoot.appendingPathComponent("Frameworks", isDirectory: true),
        ]
        return candidates.first {
            FileManager.default.fileExists(atPath: $0.appendingPathComponent("libinotify.0.dylib").path)
        }
    }

    public static let manifest = RuntimeManifest(
        id: runtimeID,
        displayName: "Sikarugir Wine 10 游戏引擎",
        version: version,
        channel: .candidate,
        hostArchitecture: .x86_64,
        minimumMacOS: SemanticVersion(major: 14, minor: 0),
        capabilities: RuntimeCapabilities(
            architectures: [.i386, .x86_64],
            renderers: [.wineD3D, .d3dMetal, .dxmt, .dxvk],
            supportsWoW64: true,
            supportsMSync: true
        ),
        artifacts: [
            ArtifactDescriptor(
                url: URL(string: "https://github.com/Sikarugir-App/Engines/releases/download/v1.0/WS12WineSikarugir10.0_6.tar.xz")!,
                sha256: "9da7ee0cbf386522f3a9906943726d9c3c125dbbd9ab120e3cde80e88d6091b2",
                size: 166_304_096
            ),
            ArtifactDescriptor(
                url: URL(string: "https://github.com/Sikarugir-App/Wrapper/releases/download/v1.0/Template-1.0.11.tar.xz")!,
                sha256: "9fa15479e7ff6abd99c1d07be285fb95f41fc6991586502427152b1f7d6ccb8a",
                size: 84_533_420
            ),
        ],
        licenses: [LicenseDescriptor(
            identifier: "LGPL-2.1-or-later",
            name: "Wine GNU LGPL",
            sourceURL: URL(string: "https://github.com/Sikarugir-App")!,
            correspondingSourceURL: URL(string: "https://github.com/Sikarugir-App")!
        )],
        publishedAt: Date(timeIntervalSince1970: 1_744_348_800)
    )
}
