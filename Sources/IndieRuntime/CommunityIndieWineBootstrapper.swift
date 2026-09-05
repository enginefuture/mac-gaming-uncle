import Foundation
import IndieCore

/// Installs the reproducible Wine 11 runtime maintained by Mac Gaming Uncle.
///
/// The archive contains only LGPL/open-source Wine and its open-source host
/// dependencies. Apple D3DMetal remains a separate, user-imported component.
public actor CommunityIndieWineBootstrapper {
    public static let runtimeID = "org.indie.wine11"
    public static let version = SemanticVersion(major: 11, minor: 0, patch: 2)

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
        let sourceVersion = Self.runtimeVersion(in: sourceRoot) ?? Self.version
        if sourceVersion >= SemanticVersion(major: 11, minor: 0, patch: 2),
           !Self.hasControllerSupport(sourceRoot) {
            throw IndieError.invalidData("手柄版 Wine 运行时缺少 SDL2 winebus 组件")
        }
        let localManifest = Self.manifest(for: sourceVersion)
        let destination = runtimeDestination(for: sourceVersion)
        if FileManager.default.fileExists(atPath: destination.path) {
            if Self.isCompleteRuntime(destination) {
                return try finishInstallation(at: destination)
            }
            throw IndieError.invalidData("运行时目标目录已存在但元数据无效：\(destination.path)")
        }
        let staging = paths.runtimes.appendingPathComponent(".indie-wine11-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.copyItem(at: sourceRoot, to: staging)
            let installed = try finishInstallation(at: staging, metadataRoot: staging, manifest: localManifest)
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: staging, to: destination)
            return LocalWineRuntime(manifest: installed.manifest, root: destination, importedAt: installed.importedAt)
        } catch {
            try? FileManager.default.removeItem(at: staging)
            throw error
        }
    }

    private var runtimeDestination: URL {
        runtimeDestination(for: Self.version)
    }

    private func runtimeDestination(for version: SemanticVersion) -> URL {
        paths.runtimes
            .appendingPathComponent(Self.runtimeID, isDirectory: true)
            .appendingPathComponent(version.description, isDirectory: true)
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

    private func finishInstallation(
        at root: URL,
        metadataRoot: URL? = nil,
        manifest: RuntimeManifest? = nil
    ) throws -> LocalWineRuntime {
        guard Self.isCompleteRuntime(root) else {
            throw IndieError.invalidData("Mac Gaming Uncle Wine 11 运行环境不完整")
        }
        let installed = LocalWineRuntime(manifest: manifest ?? Self.manifest, root: root, importedAt: Date())
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

    public static func hasControllerSupport(_ root: URL) -> Bool {
        FileManager.default.fileExists(atPath: root.appendingPathComponent("lib/libSDL2-2.0.0.dylib").path) &&
            ((try? String(contentsOf: root.appendingPathComponent("runtime-version.txt"), encoding: .utf8)) != nil)
    }

    private static func runtimeVersion(in root: URL) -> SemanticVersion? {
        guard let text = try? String(contentsOf: root.appendingPathComponent("runtime-version.txt"), encoding: .utf8) else {
            return nil
        }
        return try? SemanticVersion(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func manifest(for version: SemanticVersion) -> RuntimeManifest {
        guard version != Self.version else { return Self.manifest }
        return RuntimeManifest(
            id: runtimeID,
            displayName: "Mac Gaming Uncle Wine \(version) 手柄增强引擎",
            version: version,
            channel: .experimental,
            hostArchitecture: .x86_64,
            minimumMacOS: SemanticVersion(major: 15, minor: 0),
            capabilities: Self.manifest.capabilities,
            artifacts: [],
            licenses: Self.manifest.licenses,
            publishedAt: Date()
        )
    }

    public static let manifest = RuntimeManifest(
        id: runtimeID,
        displayName: "Mac Gaming Uncle Wine 11 手柄增强游戏引擎",
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
            url: URL(string: "https://github.com/enginefuture/mac-gaming-uncle/releases/download/runtime-wine-11.0.2/indie-wine-11.0.2-macos-x86_64.tar.xz")!,
            sha256: "412d2135f70683c34e80f50c4fa209a53be8ec9656dd51dcb92af8049fce3150",
            size: 46_596_600,
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
            LicenseDescriptor(
                identifier: "Zlib", name: "SDL2 zlib License",
                sourceURL: URL(string: "https://github.com/libsdl-org/SDL")!,
                correspondingSourceURL: URL(string: "https://github.com/libsdl-org/SDL/releases/download/release-2.32.10/SDL2-2.32.10.tar.gz")!
            ),
        ],
        publishedAt: Date(timeIntervalSince1970: 1_788_576_603)
    )
}
