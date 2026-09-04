import Foundation

public struct IndiePaths: Sendable {
    public let root: URL

    public init(root: URL) { self.root = root.standardizedFileURL }

    public static var userDefault: IndiePaths {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        // Keep the original storage location so the rename does not orphan
        // existing Wine runtimes, Steam bottles, installed games, or caches.
        return IndiePaths(root: base.appendingPathComponent("Indie", isDirectory: true))
    }

    public var database: URL { root.appendingPathComponent("state.sqlite") }
    public var bottles: URL { root.appendingPathComponent("Bottles", isDirectory: true) }
    public var runtimes: URL { root.appendingPathComponent("Runtimes", isDirectory: true) }
    public var importedComponents: URL { root.appendingPathComponent("ImportedComponents", isDirectory: true) }
    public var overlays: URL { root.appendingPathComponent("Overlays", isDirectory: true) }
    public var shaderCaches: URL { root.appendingPathComponent("ShaderCaches", isDirectory: true) }
    public var shaderCacheBackups: URL { root.appendingPathComponent("ShaderCacheBackups", isDirectory: true) }
    public var logs: URL { root.appendingPathComponent("Logs", isDirectory: true) }
    public var downloads: URL { root.appendingPathComponent("Downloads", isDirectory: true) }
    public var recipes: URL { root.appendingPathComponent("Recipes", isDirectory: true) }

    public func createDirectories(fileManager: FileManager = .default) throws {
        for directory in [root, bottles, runtimes, importedComponents, overlays, shaderCaches, shaderCacheBackups, logs, downloads, recipes] {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }
}
