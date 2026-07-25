import Foundation
import GRDB

/// Adds a partial unique index on `body_metrics.healthkit_uuid` (unique when
/// not null). Belt-and-suspenders for the import path — the importer also
/// checks for existing rows before insert, but the index prevents duplicates
/// even under unexpected race conditions or importer bugs.
///
/// Partial index (`WHERE healthkit_uuid IS NOT NULL`) is essential — most
/// rows in this table are manual entries with null uuid, and those must
/// remain freely duplicable (e.g., you can weigh in twice on the same day).
enum M003_UniqueHealthKitUuid {
    static let identifier = "003_unique_healthkit_uuid"

    static func register(in migrator: inout DatabaseMigrator) {
        migrator.registerMigration(identifier) { db in
            try db.execute(sql: """
                CREATE UNIQUE INDEX body_metrics_healthkit_uuid_unique
                ON body_metrics(healthkit_uuid)
                WHERE healthkit_uuid IS NOT NULL
                """)
        }
    }
}
