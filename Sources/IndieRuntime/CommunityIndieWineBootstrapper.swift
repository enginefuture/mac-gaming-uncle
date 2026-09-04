import Foundation
import IndieCore

/// Installs the reproducible Wine 11 runtime maintained by Mac Gaming Uncle.
///
/// The archive contains only LGPL/open-source Wine and its open-source host
/// dependencies. Apple D3DMetal remains a separate, user-imported component.
public actor CommunityIndieWineBootstrapper {
    public static let runtimeID = "org.indie.wine11"
    public static let version = SemanticVersion(major: 11, minor: 0, patch: 1)

    private let paths: IndiePaths
    private let session: URLSession

    public init(paths: IndiePaths, session: URLSession = .shared) {
        self.paths = paths
        self.session = session
    }

    public func installLatest() async throws -> LocalWineRuntime {
        if let installed = installedRuntime() { return installed }
        let destination = try await RuntimeInstaller(paths: paths, session: session).install(
            manifest: Self.manifest,
            publicKeyBase64: nil,
            allowUnsignedDevelopmentManifest: true
        )
        return try finishInstallation(at: destination)
    }

    /// Development/offline path used by contributors immediately after running
    /// `scripts/build-indie-wine11.sh`.
    public func installLocalBuild(from source: URL) throws -> LocalWineRuntime {
        try paths.createDirectories()
        let sourceRoot = Self.runtimePayloadRoot(in: source)
        guard Self.isCompleteRuntime(sourceRoot) else {
            throw IndieError.invalidData("本地 Mac Gaming Uncle Wine 11 构建不完整")
        }
        let destination = runtimeDestination
        if FileManager.default.fileExists(atPath: destination.path) {
            if Self.isCompleteRuntime(destination) {
                return try finishInstallation(at: destination)
            }
            throw IndieError.invalidData("运行时目标目录已存在但元数据无效：\(destination.path)")
        }
        let staging = paths.runtimes.appendingPathComponent(".indie-wine11-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.copyItem(at: sourceRoot, to: staging)
            let installed = try finishInstallation(at: staging, metadataRoot: staging)
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: staging, to: destination)
            return LocalWineRuntime(manifest: installed.manifest, root: destination, importedAt: installed.importedAt)
        } catch {
            try? FileManager.default.removeItem(at: staging)
            throw error
        }
    }

    private var runtimeDestination: URL {
        paths.runtimes
            .appendingPathComponent(Self.runtimeID, isDirectory: true)
            .appendingPathComponent(Self.version.description, isDirectory: true)
    }

    private func installedRuntime() -> LocalWineRuntime? {
        let destination = runtimeDestination
        let metadata = destination.appendingPathComponent("local-runtime.json")
        guard Self.isCompleteRuntime(destination),
              let data = try? Data(contentsOf: metadata),
              let value = try? IndieJSON.decoder().decode(LocalWineRuntime.self, from: data),
              value.manifest.id == Self.runtimeID,
              value.manifest.version == Self.version else { return nil }
        return LocalWineRuntime(manifest: value.manifest, root: destination, importedAt: value.importedAt)
    }

    private func finishInstallation(at root: URL, metadataRoot: URL? = nil) throws -> LocalWineRuntime {
        guard Self.isCompleteRuntime(root) else {
            throw IndieError.invalidData("Mac Gaming Uncle Wine 11 运行环境不完整")
        }
        let installed = LocalWineRuntime(manifest: Self.manifest, root: root, importedAt: Date())
        try IndieJSON.encoder(pretty: true).encode(installed)
            .write(to: (metadataRoot ?? root).appendingPathComponent("local-runtime.json"), options: .atomic)
        return installed
    }

    private static func runtimePayloadRoot(in source: URL) -> URL {
        let nested = source.appendingPathComponent("wine-runtime", isDirectory: true)
        return isCompleteRuntime(nested) ? nested : source
    }

    public static func isCompleteRuntime(_ root: URL) -> Bool {
        LocalWineImporter.findWine(in: root) != nil &&
            FileManager.default.isExecutableFile(atPath: root.appendingPathComponent("bin/wineserver").path) &&
            FileManager.default.fileExists(atPath: root.appendingPathComponent("lib/wine/x86_64-unix/ntdll.so").path) &&
            FileManager.default.fileExists(atPath: root.appendingPathComponent("lib/wine/i386-windows/ntdll.dll").path) &&
            FileManager.default.fileExists(atPath: root.appendingPathComponent("lib/libgnutls.30.dylib").path)
    }

    public static let manifest = RuntimeManifest(
        id: runtimeID,
        displayName: "Mac Gaming Uncle Wine 11 开源游戏引擎",
        version: version,
        channel: .experimental,
        hostArchitecture: .x86_64,
        minimumMacOS: SemanticVersion(major: 15, minor: 0),
        capabilities: RuntimeCapabilities(
            architectures: [.i386, .x86_64],
            renderers: [.wineD3D, .d3dMetal, .dxmt],
            supportsWoW64: true,
            supportsMSync: true
        ),
        artifacts: [ArtifactDescriptor(
            url: URL(string: "https://github.com/enginefuture/mac-gaming-uncle/releases/download/runtime-wine-11.0.1/indie-wine-11.0.1-macos-x86_64.tar.xz")!,
            sha256: "78c57653b5fb62f2df2a31d6074a99506e68b3d375b86573dc4adcfc280e3680",
            size: 46_058_220,
            archiveRoot: "wine-runtime"
        )],
        licenses: [
            LicenseDescriptor(
                identifier: "LGPL-2.1-or-later", name: "Wine GNU LGPL",
                sourceURL: URL(string: "https://www.codeweavers.com/crossover/source")!,
                correspondingSourceURL: URL(string: "https://media.codeweavers.com/pub/crossover/source/crossover-sources-26.3.0.tar.gz")!
            ),
            LicenseDescriptor(
                identifier: "LGPL-3.0-or-later", name: "GnuTLS, GMP and Nettle licenses",
                sourceURL: URL(string: "https://www.gnutls.org/")!,
                correspondingSourceURL: URL(string: "https://ftp.gnu.org/gnu/nettle/nettle-3.10.tar.gz")!
            ),
            LicenseDescriptor(
                identifier: "MIT", name: "libinotify-kqueue MIT License",
                sourceURL: URL(string: "https://github.com/libinotify-kqueue/libinotify-kqueue")!,
                correspondingSourceURL: URL(string: "https://github.com/libinotify-kqueue/libinotify-kqueue/archive/refs/tags/20240724.tar.gz")!
            ),
        ],
        publishedAt: Date(timeIntervalSince1970: 1_788_451_200)
    )
}
