import Foundation
import GRDB

// MARK: - Return types

/// One anchor lift's top set for a given day, plus whether that top set is a
/// personal record (best e1RM to date for that exercise).
public struct AnchorTopSetSummary: Sendable, Equatable {
    public let exerciseId: Int64
    public let exerciseName: String
    public let weightLb: Double
    public let reps: Int
    public let isPR: Bool

    public init(exerciseId: Int64, exerciseName: String, weightLb: Double, reps: Int, isPR: Bool) {
        self.exerciseId = exerciseId
        self.exerciseName = exerciseName
        self.weightLb = weightLb
        self.reps = reps
        self.isPR = isPR
    }
}

/// Lightweight summary of the day's workout, if any exists.
public struct DailySessionSummary: Sendable, Equatable {
    public let workoutId: Int64
    public let sessionType: Workout.SessionType?
    public let durationMin: Int?

    public init(workoutId: Int64, sessionType: Workout.SessionType?, durationMin: Int?) {
        self.workoutId = workoutId
        self.sessionType = sessionType
        self.durationMin = durationMin
    }
}

// MARK: - PR math

/// Epley one-rep-max estimate: `weight × (1 + reps/30)`.
///
/// Chosen for PR detection because it compares cleanly across rep ranges — a
/// 275×5 and a 285×3 have a defined winner. Not accurate as an absolute 1RM
/// predictor (no formula is), but consistent, which is what PR detection
/// actually needs.
public func epleyOneRepMax(weightLb: Double, reps: Int) -> Double {
    weightLb * (1.0 + Double(reps) / 30.0)
}

// MARK: - Query API

extension AppDatabase {

    // MARK: DailyLog

    /// Read the single `daily_log` row for the given calendar date, if any.
    public func dailyLog(on date: Date, calendar: Calendar = .current) async throws -> DailyLog? {
        let day = calendar.startOfDay(for: date)
        return try await read { db in
            try DailyLog.filter(Column("date") == day).fetchOne(db)
        }
    }

    /// Upsert today's `daily_log` row, mutating whichever fields the caller
    /// cares about. Existing values for other columns are preserved.
    ///
    /// The `date` column is unique in the schema, so at most one row exists
    /// per calendar day.
    public func upsertDailyLog(
        on date: Date,
        calendar: Calendar = .current,
        mutate: @Sendable @escaping (inout DailyLog) -> Void
    ) async throws {
        let day = calendar.startOfDay(for: date)
        try await write { db in
            if var log = try DailyLog.filter(Column("date") == day).fetchOne(db) {
                mutate(&log)
                try log.update(db)
            } else {
                var log = DailyLog(date: day)
                mutate(&log)
                try log.insert(db)
            }
        }
    }

    // MARK: NutritionLog

    /// Read the single `nutrition_log` row for the given calendar date, if any.
    public func nutritionLog(on date: Date, calendar: Calendar = .current) async throws -> NutritionLog? {
        let day = calendar.startOfDay(for: date)
        return try await read { db in
            try NutritionLog.filter(Column("date") == day).fetchOne(db)
        }
    }

    /// Upsert today's `nutrition_log` row, mutating whichever fields the
    /// caller cares about. Existing values for other columns are preserved.
    public func upsertNutritionLog(
        on date: Date,
        calendar: Calendar = .current,
        mutate: @Sendable @escaping (inout NutritionLog) -> Void
    ) async throws {
        let day = calendar.startOfDay(for: date)
        try await write { db in
            if var log = try NutritionLog.filter(Column("date") == day).fetchOne(db) {
                mutate(&log)
                try log.update(db)
            } else {
                var log = NutritionLog(date: day)
                mutate(&log)
                try log.insert(db)
            }
        }
    }

    // MARK: BodyMetric (manual weight for today)

    /// Read the most recent manual-source body_metrics row for today, if any.
    /// HealthKit-sourced rows are ignored here; those flow in on their own.
    public func todaysManualBodyMetric(
        on date: Date,
        calendar: Calendar = .current
    ) async throws -> BodyMetric? {
        let day = calendar.startOfDay(for: date)
        let nextDay = calendar.date(byAdding: .day, value: 1, to: day)!
        return try await read { db in
            try BodyMetric
                .filter(Column("source") == BodyMetric.Source.manual.rawValue)
                .filter(Column("timestamp") >= day)
                .filter(Column("timestamp") < nextDay)
                .order(Column("timestamp").desc)
                .fetchOne(db)
        }
    }

    /// Update today's manual weight if a row already exists for today; else
    /// insert a new manual-source `body_metrics` row.
    ///
    /// Rationale: the Log tab shows one weight per day. Editing throughout
    /// the day overwrites, rather than accumulating near-duplicate rows. Prior
    /// days' entries are never touched.
    public func upsertTodaysManualWeight(
        _ weightLb: Double,
        on date: Date,
        calendar: Calendar = .current
    ) async throws {
        let day = calendar.startOfDay(for: date)
        let nextDay = calendar.date(byAdding: .day, value: 1, to: day)!
        try await write { db in
            if var metric = try BodyMetric
                .filter(Column("source") == BodyMetric.Source.manual.rawValue)
                .filter(Column("timestamp") >= day)
                .filter(Column("timestamp") < nextDay)
                .order(Column("timestamp").desc)
                .fetchOne(db)
            {
                metric.weightLb = weightLb
                metric.timestamp = Date()
                try metric.update(db)
            } else {
                var metric = BodyMetric(
                    timestamp: Date(),
                    source: .manual,
                    weightLb: weightLb
                )
                try metric.insert(db)
            }
        }
    }

    // MARK: Workout summary

    /// Return the first workout logged for the given calendar date, if any.
    /// v1 assumes at most one workout per day; if that ever changes, this
    /// picks the earliest by id.
    public func todaysSession(
        on date: Date,
        calendar: Calendar = .current
    ) async throws -> DailySessionSummary? {
        let day = calendar.startOfDay(for: date)
        return try await read { db in
            guard let workout = try Workout
                .filter(Column("date") == day)
                .order(Column("id"))
                .fetchOne(db)
            else { return nil }

            return DailySessionSummary(
                workoutId: workout.id!,
                sessionType: workout.sessionType,
                durationMin: workout.durationMin
            )
        }
    }

    // MARK: Anchor top sets + PR detection

    /// For each anchor-category exercise touched in today's workout, return
    /// its top set (`is_top_set = 1`) with a flag indicating whether that set
    /// beats every prior top set of the same exercise by Epley e1RM.
    ///
    /// PR rule: `epleyOneRepMax(today) > max(epleyOneRepMax(prior top sets
    /// of same exercise, on days strictly before `date`))`. If no prior top
    /// sets exist for the exercise, today's top set counts as a PR. Warmups
    /// and non-top sets are ignored by definition.
    public func anchorTopSets(
        on date: Date,
        calendar: Calendar = .current
    ) async throws -> [AnchorTopSetSummary] {
        let day = calendar.startOfDay(for: date)
        let nextDay = calendar.date(byAdding: .day, value: 1, to: day)!

        return try await read { db in
            // Row shape for today's anchor top sets. Kept private to the
            // closure — this is just a query decoding target.
            struct Row: Codable, FetchableRecord {
                var exerciseId: Int64
                var exerciseName: String
                var weightLb: Double
                var reps: Int

                enum CodingKeys: String, CodingKey {
                    case exerciseId = "exercise_id"
                    case exerciseName = "exercise_name"
                    case weightLb = "weight_lb"
                    case reps
                }
            }

            let todaysTopSets = try Row.fetchAll(db, sql: """
                SELECT s.exercise_id,
                       e.name AS exercise_name,
                       s.weight_lb,
                       s.reps
                FROM exercise_sets s
                JOIN exercises e ON e.id = s.exercise_id
                JOIN workouts   w ON w.id = s.workout_id
                WHERE w.date  >= ?
                  AND w.date  <  ?
                  AND s.is_top_set = 1
                  AND s.is_warmup  = 0
                  AND e.category   = ?
                  AND s.weight_lb IS NOT NULL
                  AND s.reps      IS NOT NULL
                ORDER BY s.exercise_id, s.id
                """, arguments: [day, nextDay, Exercise.Category.anchor.rawValue])

            var results: [AnchorTopSetSummary] = []
            for row in todaysTopSets {
                let todayE1RM = epleyOneRepMax(weightLb: row.weightLb, reps: row.reps)

                let priorMaxE1RM = try Double.fetchOne(db, sql: """
                    SELECT MAX(s.weight_lb * (1.0 + CAST(s.reps AS REAL) / 30.0))
                    FROM exercise_sets s
                    JOIN workouts w ON w.id = s.workout_id
                    WHERE s.exercise_id = ?
                      AND s.is_top_set  = 1
                      AND s.is_warmup   = 0
                      AND s.weight_lb IS NOT NULL
                      AND s.reps      IS NOT NULL
                      AND w.date       < ?
                    """, arguments: [row.exerciseId, day])

                let isPR = todayE1RM > (priorMaxE1RM ?? 0)

                results.append(AnchorTopSetSummary(
                    exerciseId: row.exerciseId,
                    exerciseName: row.exerciseName,
                    weightLb: row.weightLb,
                    reps: row.reps,
                    isPR: isPR
                ))
            }
            return results
        }
    }
}
