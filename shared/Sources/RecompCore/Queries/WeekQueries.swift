import Foundation
import GRDB

// MARK: - Query API

extension AppDatabase {

    // MARK: Range-scoped fetches
    //
    // Every method here returns rows whose primary date/timestamp falls
    // within [from, through] inclusive. `through` is treated as inclusive
    // for callers that pass "end of day" or "end of week." Ordering is
    // ascending by timestamp/date so consumers can iterate chronologically
    // without re-sorting.

    public func bodyMetrics(
        from: Date,
        through: Date
    ) async throws -> [BodyMetric] {
        try await read { db in
            try BodyMetric
                .filter(Column("timestamp") >= from)
                .filter(Column("timestamp") <= through)
                .order(Column("timestamp"))
                .fetchAll(db)
        }
    }

    /// Latest `body_metrics` row with `weight_lb NOT NULL` before `date`.
    /// Feeds the "weight at start of week" summary field — we look before
    /// the window opens so a Monday-morning weigh-in from the prior Sunday
    /// still anchors the delta calculation.
    public func latestWeightBefore(
        _ date: Date
    ) async throws -> BodyMetric? {
        try await read { db in
            try BodyMetric
                .filter(sql: "weight_lb IS NOT NULL")
                .filter(Column("timestamp") < date)
                .order(Column("timestamp").desc)
                .limit(1)
                .fetchOne(db)
        }
    }

    public func dailyLogs(
        from: Date,
        through: Date
    ) async throws -> [DailyLog] {
        try await read { db in
            try DailyLog
                .filter(Column("date") >= Calendar.current.startOfDay(for: from))
                .filter(Column("date") <= Calendar.current.startOfDay(for: through))
                .order(Column("date"))
                .fetchAll(db)
        }
    }

    public func nutritionLogs(
        from: Date,
        through: Date
    ) async throws -> [NutritionLog] {
        try await read { db in
            try NutritionLog
                .filter(Column("date") >= Calendar.current.startOfDay(for: from))
                .filter(Column("date") <= Calendar.current.startOfDay(for: through))
                .order(Column("date"))
                .fetchAll(db)
        }
    }

    public func workouts(
        from: Date,
        through: Date
    ) async throws -> [Workout] {
        try await read { db in
            try Workout
                .filter(Column("date") >= Calendar.current.startOfDay(for: from))
                .filter(Column("date") <= Calendar.current.startOfDay(for: through))
                .order(Column("date"), Column("id"))
                .fetchAll(db)
        }
    }

    public func progressPhotos(
        from: Date,
        through: Date
    ) async throws -> [ProgressPhoto] {
        try await read { db in
            try ProgressPhoto
                .filter(Column("timestamp") >= from)
                .filter(Column("timestamp") <= through)
                .order(Column("timestamp"))
                .fetchAll(db)
        }
    }

    /// All exercises, ordered by name. Small enough that we always fetch
    /// the full set for the export — no need to filter to "exercises that
    /// appear in this week's sets."
    public func allExercises() async throws -> [Exercise] {
        try await read { db in
            try Exercise
                .order(Column("name"))
                .fetchAll(db)
        }
    }

    /// All sets for a set of workout ids, ordered by workout then set number.
    /// One query per week rather than one per workout — a workout typically
    /// has 12–30 sets; fetching all in one query keeps the export
    /// assembler under a fixed ~10 async round trips regardless of week
    /// volume.
    public func sets(
        forWorkoutIds ids: [Int64]
    ) async throws -> [ExerciseSet] {
        guard !ids.isEmpty else { return [] }
        return try await read { db in
            try ExerciseSet
                .filter(ids.contains(Column("workout_id")))
                .order(Column("workout_id"), Column("set_number"))
                .fetchAll(db)
        }
    }
}
