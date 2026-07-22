import Foundation
import GRDB

/// Migration 001: Initial schema.
///
/// Creates all core tables: body_metrics, daily_log, workouts, exercise_sets,
/// exercises, nutrition_log, progress_photos, check_ins. Also creates indices
/// on frequently-queried columns.
///
/// See `docs/schema.md` for full schema documentation and rationale.
enum M001_InitialSchema {
    static let identifier = "001_initial_schema"

    static func register(in migrator: inout DatabaseMigrator) {
        migrator.registerMigration(identifier) { db in
            try db.create(table: "body_metrics") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("timestamp", .datetime).notNull().indexed()
                t.column("source", .text).notNull()
                t.column("healthkit_uuid", .text).indexed()
                t.column("weight_lb", .double)
                t.column("body_fat_pct", .double)
                t.column("lean_mass_lb", .double)
                t.column("bone_mass_lb", .double)
                t.column("body_water_pct", .double)
                t.column("visceral_fat_rating", .double)
                t.column("bmr_kcal", .integer)
                t.column("resting_hr", .integer)
                t.column("hrv_ms", .double)
                t.column("sleep_hours", .double)
                t.column("sleep_efficiency", .double)
            }

            try db.create(table: "daily_log") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("date", .date).notNull().unique()
                t.column("energy_1_10", .integer)
                t.column("mood", .text)
                t.column("sleep_quality_1_10", .integer)
                t.column("stress_1_10", .integer)
                t.column("notes", .text)
                t.column("training_readiness", .double)
            }

            try db.create(table: "exercises") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull().unique()
                t.column("category", .text)
                t.column("primary_muscle_group", .text)
                t.column("movement_pattern", .text)
                t.column("is_bilateral", .boolean).defaults(to: true)
                t.column("is_custom", .boolean).defaults(to: false)
            }

            try db.create(table: "workouts") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("date", .date).notNull().indexed()
                t.column("started_at", .datetime)
                t.column("ended_at", .datetime)
                t.column("session_type", .text)
                t.column("duration_min", .integer)
                t.column("healthkit_workout_uuid", .text).indexed()
                t.column("active_kcal", .integer)
                t.column("avg_hr", .integer)
                t.column("notes", .text)
            }

            try db.create(table: "exercise_sets") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("workout_id", .integer)
                    .notNull()
                    .indexed()
                    .references("workouts", onDelete: .cascade)
                t.column("exercise_id", .integer)
                    .notNull()
                    .indexed()
                    .references("exercises", onDelete: .restrict)
                t.column("set_number", .integer).notNull()
                t.column("weight_lb", .double)
                t.column("reps", .integer)
                t.column("rir", .integer)
                t.column("is_top_set", .boolean).defaults(to: false)
                t.column("is_warmup", .boolean).defaults(to: false)
                t.column("notes", .text)
            }

            try db.create(table: "nutrition_log") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("date", .date).notNull().unique()
                t.column("kcal", .integer)
                t.column("protein_g", .integer)
                t.column("carbs_g", .integer)
                t.column("fat_g", .integer)
                t.column("target_kcal", .integer)
                t.column("target_protein_g", .integer)
                t.column("notes", .text)
            }

            try db.create(table: "progress_photos") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("date", .date).notNull().indexed()
                t.column("timestamp", .datetime).notNull()
                t.column("angle", .text).notNull()
                t.column("pose", .text).notNull()
                t.column("photo_path", .text).notNull()
                t.column("weight_lb_at_capture", .double)
                t.column("bf_pct_at_capture", .double)
                t.column("cadence_tag", .text)
                t.column("notes", .text)
            }

            try db.create(table: "check_ins") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("date", .date).notNull()
                t.column("period_type", .text).notNull()
                t.column("period_start", .date).notNull()
                t.column("period_end", .date).notNull()
                t.column("avg_weight_lb", .double)
                t.column("avg_body_fat_pct", .double)
                t.column("avg_sleep_hours", .double)
                t.column("workouts_completed", .integer)
                t.column("total_volume_lb", .double)
                t.column("reflection_notes", .text)
                t.column("coach_notes", .text)
            }
        }
    }
}
