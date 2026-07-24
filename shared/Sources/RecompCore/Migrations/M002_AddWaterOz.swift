import Foundation
import GRDB

/// Adds `water_oz` (integer, nullable) to `nutrition_log`.
///
/// Water intake wasn't in the original v1 schema — added when the Log tab UI
/// exposed a 120oz daily goal tracker. Kept as a single running total per day
/// rather than a separate `water_entries` table because there's no intraday
/// view planned and the daily total is the only thing the UI needs.
enum M002_AddWaterOz {
    static let identifier = "002_add_water_oz"

    static func register(in migrator: inout DatabaseMigrator) {
        migrator.registerMigration(identifier) { db in
            try db.alter(table: "nutrition_log") { t in
                t.add(column: "water_oz", .integer)
            }
        }
    }
}
