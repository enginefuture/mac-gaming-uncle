import Foundation
import IndieCore

public actor BottleManager {
    private let paths: IndiePaths
    private let store: StateStore
    private let subprocess: Subprocess
    private var lockedBottles: Set<UUID> = []

    public init(paths: IndiePaths, store: StateStore, subprocess: Subprocess = Subprocess()) {
        self.paths = paths
        self.store = store
        self.subprocess = subprocess
    }

    public func create(name: String, runtime: any RuntimeProvider) async throws -> BottleRecord {
        try paths.createDirectories()
        let safeName = sanitized(name)
        guard !safeName.isEmpty else { throw IndieError.invalidArgument(L("Bottle 名称不能为空")) }
        let id = UUID()
        let root = paths.bottles.appendingPathComponent("\(safeName)-\(id.uuidString.lowercased())", isDirectory: true)
        guard !FileManager.default.fileExists(atPath: root.path) else { throw IndieError.invalidData(L("Bottle 目录已存在")) }
        let bottle = BottleRecord(id: id, name: name, root: root, runtimeID: runtime.manifest.id)
        do {
            try await withLock(id) { try await runtime.initializeBottle(bottle) }
            try IndieJSON.encoder(pretty: true).encode(bottle).write(to: root.appendingPathComponent("indie-bottle.json"), options: .atomic)
            try await store.saveBottle(bottle)
            return bottle
        } catch {
            try? FileManager.default.removeItem(at: root)
            throw error
        }
    }

    public func snapshot(_ bottle: BottleRecord, reason: String) async throws -> URL {
        let snapshots = bottle.root.deletingLastPathComponent().appendingPathComponent("Snapshots", isDirectory: true)
        try FileManager.default.createDirectory(at: snapshots, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let destination = snapshots.appendingPathComponent("\(bottle.id.uuidString)-\(stamp)-\(sanitized(reason))", isDirectory: true)
        return try await withLock(bottle.id) {
            do {
                try await subprocess.run(URL(fileURLWithPath: "/bin/cp"), arguments: ["-cR", bottle.root.path, destination.path], timeout: .seconds(1_800))
            } catch {
                try await subprocess.run(URL(fileURLWithPath: "/usr/bin/ditto"), arguments: [bottle.root.path, destination.path], timeout: .seconds(3_600))
            }
            return destination
        }
    }

    public func removeRootDriveMapping(from bottle: BottleRecord) throws {
        let rootDrive = bottle.root.appendingPathComponent("dosdevices/z:")
        if FileManager.default.fileExists(atPath: rootDrive.path) { try FileManager.default.removeItem(at: rootDrive) }
    }

    private func withLock<T: Sendable>(_ id: UUID, operation: () async throws -> T) async throws -> T {
        guard lockedBottles.insert(id).inserted else { throw IndieError.invalidData(L("Bottle 正在被另一个操作使用")) }
        defer { lockedBottles.remove(id) }
        return try await operation()
    }

    private func sanitized(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return value.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }.reduce(into: "") { $0.append($1) }
    }
}
