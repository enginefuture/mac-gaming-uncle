import Foundation
import IndieCore

public struct WineBootstrapRelease: Codable, Sendable, Equatable {
    public let version: SemanticVersion
    public let downloadSize: Int64
    public let assetName: String
}

public actor CommunityWineBootstrapper {
    private struct GitHubRelease: Decodable {
        let tagName: String
        let publishedAt: Date
        let assets: [GitHubAsset]

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case publishedAt = "published_at"
            case assets
        }
    }

    private struct GitHubAsset: Decodable {
        let name: String
        let size: Int64
        let digest: String?
        let browserDownloadURL: URL

        enum CodingKeys: String, CodingKey {
            case name, size, digest
            case browserDownloadURL = "browser_download_url"
        }
    }

    private static let latestReleaseURL = URL(string: "https://api.github.com/repos/Gcenx/macOS_Wine_builds/releases/latest")!
    private let paths: IndiePaths
    private let session: URLSession

    public init(paths: IndiePaths, session: URLSession = .shared) {
        self.paths = paths
        self.session = session
    }

    public func latest() async throws -> WineBootstrapRelease {
        let (release, asset) = try await resolveLatest()
        return WineBootstrapRelease(version: try SemanticVersion(release.tagName), downloadSize: asset.size, assetName: asset.name)
    }

    public func installLatest() async throws -> LocalWineRuntime {
        let (release, asset) = try await resolveLatest()
        guard let digest = asset.digest?.lowercased(), digest.hasPrefix("sha256:"), digest.count == 71 else {
            throw IndieError.securityViolation(L("上游 Release 没有提供 SHA-256，拒绝自动安装"))
        }
        let version = try SemanticVersion(release.tagName)
        let manifest = RuntimeManifest(
            id: "org.indie.wine.community",
            displayName: "Wine Staging \(version)",
            version: version,
            channel: .candidate,
            hostArchitecture: .x86_64,
            minimumMacOS: SemanticVersion(major: 15, minor: 0),
            capabilities: RuntimeCapabilities(
                architectures: [.i386, .x86_64], renderers: [.wineD3D],
                supportsWoW64: version.major >= 9, supportsMSync: false
            ),
            artifacts: [ArtifactDescriptor(
                url: asset.browserDownloadURL,
                sha256: String(digest.dropFirst("sha256:".count)),
                size: asset.size,
                archiveRoot: nil
            )],
            licenses: [LicenseDescriptor(
                identifier: "LGPL-2.1-or-later",
                name: "Wine GNU LGPL",
                sourceURL: URL(string: "https://github.com/Gcenx/macOS_Wine_builds")!,
                correspondingSourceURL: URL(string: "https://gitlab.winehq.org/wine/wine/-/releases/wine-\(version)")
            )],
            publishedAt: release.publishedAt,
            signature: nil
        )
        let destination = try await RuntimeInstaller(paths: paths, session: session).install(
            manifest: manifest,
            publicKeyBase64: nil,
            allowUnsignedDevelopmentManifest: true
        )
        guard LocalWineImporter.findWine(in: destination) != nil else {
            throw IndieError.invalidData(L("下载的 Wine 运行时缺少可执行文件"))
        }
        let installed = LocalWineRuntime(manifest: manifest, root: destination, importedAt: Date())
        try IndieJSON.encoder(pretty: true).encode(installed)
            .write(to: destination.appendingPathComponent("local-runtime.json"), options: .atomic)
        return installed
    }

    private func resolveLatest() async throws -> (GitHubRelease, GitHubAsset) {
        var request = URLRequest(url: Self.latestReleaseURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("Mac Gaming Uncle/0.1", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              http.url?.host?.lowercased() == "api.github.com" else {
            throw IndieError.invalidData(L("无法读取 Wine 上游 Release"))
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let release = try decoder.decode(GitHubRelease.self, from: data)
        guard let asset = release.assets.first(where: {
            let name = $0.name.lowercased()
            return name.hasPrefix("wine-staging-") && name.hasSuffix("-osx64.tar.xz")
        }) else {
            throw IndieError.notFound(L("上游最新 Release 没有 macOS x86_64 Wine Staging 制品"))
        }
        guard asset.browserDownloadURL.scheme == "https", asset.browserDownloadURL.host?.lowercased() == "github.com" else {
            throw IndieError.securityViolation(L("Wine 下载地址不属于 GitHub"))
        }
        return (release, asset)
    }
}
