import XCTest
import GRDB
@testable import RecompCore

/// Smoke test for the database skeleton.
///
/// Deliberately makes no assertion about *which* tables exist — the schema is
/// replaced in the next commit, and a test that enumerated the current tables
/// would have to be rewritten alongside it. This asserts only that the writer
/// opens and the migrator runs clean, which stays true across that change.
final class DatabaseSmokeTests: XCTestCase {

    func testInMemoryDatabaseOpensAndMigrates() async throws {
        let db = try AppDatabase.inMemory()

        let one = try await db.read { db in
            try Int.fetchOne(db, sql: "SELECT 1")
        }
        XCTAssertEqual(one, 1)
    }

    func testRunMigrationsIsIdempotent() throws {
        let db = try AppDatabase.inMemory()
        XCTAssertNoThrow(try db.runMigrations())
        XCTAssertNoThrow(try db.runMigrations())
    }

    func testForeignKeysAreEnforced() async throws {
        let db = try AppDatabase.inMemory()

        let enabled = try await db.read { db in
            try Bool.fetchOne(db, sql: "PRAGMA foreign_keys")
        }
        XCTAssertEqual(enabled, true, "FK enforcement must be on before the new schema lands")
    }
}
