import Foundation
import GRDB

/// The application's database handle.
///
/// Wraps a GRDB `DatabaseWriter` (either a `DatabasePool` for on-disk use or a
/// `DatabaseQueue` for in-memory tests) and exposes an async-only API surface.
///
/// Internally, database operations use GRDB's synchronous block API — the async
/// wrapper is the boundary, not the implementation.
public struct AppDatabase: Sendable {

    /// The underlying GRDB writer. Exposed for advanced use (e.g. constructing
    /// GRDB `ValueObservation` streams that need a `DatabaseReader`). Prefer the
    /// `read`/`write` methods below for normal work.
    public let dbWriter: any DatabaseWriter

    /// Standard initializer. Takes an already-configured writer and runs any
    /// pending migrations before returning.
    public init(_ dbWriter: any DatabaseWriter) throws {
        self.dbWriter = dbWriter
        try runMigrations()
    }

    // MARK: - Factories

    /// Opens the SQLite file at
    /// `<Application Support>/RecompTracker/recomp.sqlite`, creating the
    /// containing directory if needed.
    public static func standard() throws -> AppDatabase {
        let fileManager = FileManager.default
        let appSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = appSupport.appendingPathComponent("RecompTracker", isDirectory: true)
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let dbURL = directory.appendingPathComponent("recomp.sqlite")
        let dbPool = try DatabasePool(path: dbURL.path)
        return try AppDatabase(dbPool)
    }

    /// In-memory database. Use in tests and previews.
    public static func inMemory() throws -> AppDatabase {
        let dbQueue = try DatabaseQueue()
        return try AppDatabase(dbQueue)
    }

    // MARK: - Migrations

    /// Runs any pending migrations. Safe to call more than once — GRDB's
    /// migrator is idempotent.
    public func runMigrations() throws {
        try AppMigrator.migrator.migrate(dbWriter)
    }

    // MARK: - Async operations

    /// Perform a write operation asynchronously.
    ///
    /// The closure runs on GRDB's writer queue and receives a `Database`
    /// handle. Returning a value from the closure is the recommended way to
    /// hand results back across the async boundary in a `Sendable`-safe way.
    public func write<T: Sendable>(
        _ updates: @Sendable @escaping (Database) throws -> T
    ) async throws -> T {
        try await dbWriter.write(updates)
    }

    /// Perform a read operation asynchronously.
    public func read<T: Sendable>(
        _ value: @Sendable @escaping (Database) throws -> T
    ) async throws -> T {
        try await dbWriter.read(value)
    }
}
