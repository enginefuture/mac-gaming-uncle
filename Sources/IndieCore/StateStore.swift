import CSQLite
import Foundation

public actor StateStore {
    private let databaseURL: URL
    private var database: OpaquePointer?

    public init(databaseURL: URL) { self.databaseURL = databaseURL }

    public func open() throws {
        guard database == nil else { return }
        try FileManager.default.createDirectory(at: databaseURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        var handle: OpaquePointer?
        guard sqlite3_open_v2(databaseURL.path, &handle, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
              let handle else {
            let message = handle.flatMap { sqlite3_errmsg($0) }.map(String.init(cString:)) ?? "无法打开数据库"
            if let handle { sqlite3_close(handle) }
            throw IndieError.database(message)
        }
        database = handle
        try execute("PRAGMA journal_mode=WAL")
        try execute("PRAGMA foreign_keys=ON")
        try migrate()
    }

    public func close() {
        if let database { sqlite3_close(database) }
        database = nil
    }

    public func saveBottle(_ bottle: BottleRecord) throws {
        try ensureOpen()
        let data = try IndieJSON.encoder().encode(bottle)
        try upsert(kind: "bottle", id: bottle.id.uuidString, data: data, updatedAt: bottle.updatedAt)
    }

    public func bottles() throws -> [BottleRecord] {
        try fetch(kind: "bottle").map { try IndieJSON.decoder().decode(BottleRecord.self, from: $0) }
    }

    public func saveGame(_ game: GameRecord) throws {
        try ensureOpen()
        try upsert(kind: "game", id: game.id.uuidString, data: IndieJSON.encoder().encode(game), updatedAt: Date())
    }

    public func games() throws -> [GameRecord] {
        try fetch(kind: "game").map { try IndieJSON.decoder().decode(GameRecord.self, from: $0) }
    }

    public func saveSession(_ session: RunSession) throws {
        try ensureOpen()
        try upsert(kind: "session", id: session.id.uuidString, data: IndieJSON.encoder().encode(session), updatedAt: session.endedAt)
    }

    public func sessions(limit: Int = 100) throws -> [RunSession] {
        try fetch(kind: "session", limit: limit).map { try IndieJSON.decoder().decode(RunSession.self, from: $0) }
    }

    private func migrate() throws {
        try execute("""
        CREATE TABLE IF NOT EXISTS metadata (
            key TEXT PRIMARY KEY NOT NULL,
            value TEXT NOT NULL
        )
        """)
        try execute("""
        CREATE TABLE IF NOT EXISTS records (
            kind TEXT NOT NULL,
            id TEXT NOT NULL,
            payload BLOB NOT NULL,
            updated_at REAL NOT NULL,
            PRIMARY KEY(kind, id)
        )
        """)
        try execute("CREATE INDEX IF NOT EXISTS records_kind_updated ON records(kind, updated_at DESC)")
        try execute("INSERT OR REPLACE INTO metadata(key, value) VALUES ('schema_version', '1')")
    }

    private func ensureOpen() throws {
        if database == nil { try open() }
    }

    private func execute(_ sql: String) throws {
        guard let database else { throw IndieError.database("数据库尚未打开") }
        var error: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(database, sql, nil, nil, &error) == SQLITE_OK else {
            let message = error.map { String(cString: $0) } ?? String(cString: sqlite3_errmsg(database))
            sqlite3_free(error)
            throw IndieError.database(message)
        }
    }

    private func upsert(kind: String, id: String, data: Data, updatedAt: Date) throws {
        guard let database else { throw IndieError.database("数据库尚未打开") }
        let sql = "INSERT INTO records(kind,id,payload,updated_at) VALUES(?,?,?,?) ON CONFLICT(kind,id) DO UPDATE SET payload=excluded.payload, updated_at=excluded.updated_at"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw IndieError.database(String(cString: sqlite3_errmsg(database)))
        }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(statement, 1, kind, -1, transient)
        sqlite3_bind_text(statement, 2, id, -1, transient)
        _ = data.withUnsafeBytes { bytes in
            sqlite3_bind_blob(statement, 3, bytes.baseAddress, Int32(bytes.count), transient)
        }
        sqlite3_bind_double(statement, 4, updatedAt.timeIntervalSince1970)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw IndieError.database(String(cString: sqlite3_errmsg(database)))
        }
    }

    private func fetch(kind: String, limit: Int = .max) throws -> [Data] {
        guard let database else { throw IndieError.database("数据库尚未打开") }
        let sql = "SELECT payload FROM records WHERE kind=? ORDER BY updated_at DESC LIMIT ?"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw IndieError.database(String(cString: sqlite3_errmsg(database)))
        }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(statement, 1, kind, -1, transient)
        sqlite3_bind_int64(statement, 2, Int64(limit))
        var result: [Data] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let bytes = sqlite3_column_blob(statement, 0) else { continue }
            let count = Int(sqlite3_column_bytes(statement, 0))
            result.append(Data(bytes: bytes, count: count))
        }
        return result
    }
}
