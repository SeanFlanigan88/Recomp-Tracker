import Foundation
import GRDB

/// Migration 001: Initial schema.
///
/// Three tables: `workouts`, `exercises`, `exercise_logs`.
///
/// Rewritten in place rather than superseded by a new migration. The old schema
/// carried five other tables for features that no longer exist, no data is being
/// preserved, and `AppMigrator` sets `eraseDatabaseOnSchemaChange` under DEBUG —
/// so the local database rebuilds from scratch on next launch.
///
/// Normal forward-only rules resume from here: once anything is worth keeping,
/// edit this file no further and add `M002`.
///
/// See `docs/schema.md`.
enum M001_InitialSchema {
    static let identifier = "001_initial_schema"

    static func register(in migrator: inout DatabaseMigrator) {
        migrator.registerMigration(identifier) { db in

            // A session, identified by its position in the cycle rather than by
            // date. `ordinal` is 1-based and intentionally unbounded: a phase
            // showing 37/30 is valid, so there is no upper CHECK here.
            try db.create(table: "workouts") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("phase", .integer).notNull()
                t.column("ordinal", .integer).notNull()

                // The only date in the schema. NULL means pending.
                // Indexed because the "last time" lookup orders by it.
                t.column("completed_at", .datetime).indexed()

                t.uniqueKey(["phase", "ordinal"])

                // Phase is an enum in Swift; this catches anything that reaches
                // SQL by another route.
                t.check(sql: "phase BETWEEN 1 AND 3")
                t.check(sql: "ordinal >= 1")
            }

            // Canonical movement names, cues stripped. UNIQUE(name) is what
            // makes cross-phase history work — see Exercise.swift.
            try db.create(table: "exercises") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull().unique()
                t.check(sql: "length(trim(name)) > 0")
            }

            // One row per (session, exercise). No set_number: one weight and one
            // rep count cover every round.
            try db.create(table: "exercise_logs") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("workout_id", .integer)
                    .notNull()
                    .indexed()
                    .references("workouts", onDelete: .cascade)
                t.column("exercise_id", .integer)
                    .notNull()
                    .indexed()
                    .references("exercises", onDelete: .restrict)
                t.column("weight_lb", .double)
                t.column("reps", .integer)

                t.uniqueKey(["workout_id", "exercise_id"])

                // Guard against sign errors from text fields. Zero is allowed:
                // bodyweight work legitimately logs 0 lb, and a 0-rep entry is a
                // meaningful "attempted, got nothing".
                t.check(sql: "weight_lb IS NULL OR weight_lb >= 0")
                t.check(sql: "reps IS NULL OR reps >= 0")
            }
        }
    }
}
