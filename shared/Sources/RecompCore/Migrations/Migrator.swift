import Foundation
import GRDB

/// Central registration point for schema migrations.
///
/// Add a new migration by:
///   1. Creating `MNNN_YourMigration.swift` in this directory following the
///      pattern in `M001_InitialSchema.swift`.
///   2. Registering it below, in order.
///
/// Migrations are forward-only. Never edit a migration after it has shipped —
/// write a new one that superseeds it.
public enum AppMigrator {

    public static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        #if DEBUG
        // Convenience during development: if a migration is edited in place
        // (which we should not do post-ship, but is normal pre-ship), the DB
        // is rebuilt from scratch instead of getting stuck on an inconsistent
        // migration bookkeeping row.
        migrator.eraseDatabaseOnSchemaChange = true
        #endif

        M001_InitialSchema.register(in: &migrator)
        M002_AddWaterOz.register(in: &migrator)

        return migrator
    }
}
