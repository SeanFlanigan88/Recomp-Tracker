import Foundation
import GRDB

// MARK: - Return types

/// Snapshot of a workout day for view hydration. `workout` is nil if nothing
/// has been logged yet — the UI still renders the program plan for the day.
public struct WorkoutDaySnapshot: Sendable, Equatable {
    public let workout: Workout?
    /// Sets keyed by `exercise_id`. Each array is in `set_number` order.
    public let setsByExerciseId: [Int64: [ExerciseSet]]

    public init(workout: Workout?, setsByExerciseId: [Int64: [ExerciseSet]]) {
        self.workout = workout
        self.setsByExerciseId = setsByExerciseId
    }
}

// MARK: - Query API

extension AppDatabase {

    // MARK: Exercise get-or-create

    /// Look up an `exercises` row by exact-name match, creating one with the
    /// given category if none exists. Idempotent — repeated calls with the
    /// same name return the same id.
    ///
    /// Called lazily when the user first logs a set of a program exercise.
    /// If an existing row's category is `nil`, we backfill it to the caller's
    /// value; established categories are left alone (someone may have edited
    /// the exercise deliberately).
    public func getOrCreateExercise(
        name: String,
        category: Exercise.Category
    ) async throws -> Int64 {
        try await write { db in
            if var existing = try Exercise
                .filter(Column("name") == name)
                .fetchOne(db),
               let id = existing.id
            {
                if existing.category == nil {
                    existing.category = category
                    try existing.update(db)
                }
                return id
            }

            var new = Exercise(
                name: name,
                category: category,
                isBilateral: true,
                isCustom: false
            )
            try new.insert(db)
            return new.id!
        }
    }

    // MARK: Workout get-or-create

    /// Fetch or create the workout row for the given calendar day. If a row
    /// already exists (regardless of session_type), it's returned — we don't
    /// overwrite the type of an already-started session.
    ///
    /// Sets `started_at` to now on first creation; leaves it alone on later
    /// calls. `ended_at` and `duration_min` are user-editable elsewhere.
    public func getOrCreateWorkout(
        on date: Date,
        sessionType: Workout.SessionType,
        calendar: Calendar = .current
    ) async throws -> Int64 {
        let day = calendar.startOfDay(for: date)
        let nextDay = calendar.date(byAdding: .day, value: 1, to: day)!
        return try await write { db in
            if let existing = try Workout
                .filter(Column("date") >= day)
                .filter(Column("date") < nextDay)
                .order(Column("id"))
                .fetchOne(db),
               let id = existing.id
            {
                return id
            }

            var new = Workout(
                date: day,
                startedAt: Date(),
                sessionType: sessionType
            )
            try new.insert(db)
            return new.id!
        }
    }

    /// Read the workout for the given day, if any exists.
    public func workout(
        on date: Date,
        calendar: Calendar = .current
    ) async throws -> Workout? {
        let day = calendar.startOfDay(for: date)
        let nextDay = calendar.date(byAdding: .day, value: 1, to: day)!
        return try await read { db in
            try Workout
                .filter(Column("date") >= day)
                .filter(Column("date") < nextDay)
                .order(Column("id"))
                .fetchOne(db)
        }
    }

    // MARK: Set upsert with top-set recompute

    /// Upsert a set by `(workout_id, exercise_id, set_number)`, then recompute
    /// `is_top_set` for all non-warmup sets of that exercise in that workout.
    ///
    /// Top set = the non-warmup set with the highest Epley e1RM. Ties are
    /// broken by earliest `set_number` (so if you do 275×5 twice, the first
    /// one wins deterministically). Sets missing weight or reps are ignored
    /// for e1RM purposes but their row still gets `is_top_set = false`.
    public func upsertSet(
        workoutId: Int64,
        exerciseId: Int64,
        setNumber: Int,
        weightLb: Double?,
        reps: Int?
    ) async throws {
        try await write { db in
            // 1. Upsert the target row.
            if var existing = try ExerciseSet
                .filter(Column("workout_id") == workoutId)
                .filter(Column("exercise_id") == exerciseId)
                .filter(Column("set_number") == setNumber)
                .fetchOne(db)
            {
                existing.weightLb = weightLb
                existing.reps = reps
                try existing.update(db)
            } else {
                var new = ExerciseSet(
                    workoutId: workoutId,
                    exerciseId: exerciseId,
                    setNumber: setNumber,
                    weightLb: weightLb,
                    reps: reps,
                    isTopSet: false,
                    isWarmup: false
                )
                try new.insert(db)
            }

            // 2. Recompute top set across all non-warmup sets for this
            //    (workout, exercise). Doing this in Swift instead of SQL —
            //    at most a handful of sets per exercise, and the e1RM logic
            //    stays in one place (Program's `epleyOneRepMax`).
            let allSets = try ExerciseSet
                .filter(Column("workout_id") == workoutId)
                .filter(Column("exercise_id") == exerciseId)
                .filter(Column("is_warmup") == false)
                .order(Column("set_number"))
                .fetchAll(db)

            let scored = allSets.compactMap { set -> (id: Int64, setNumber: Int, e1rm: Double)? in
                guard let id = set.id,
                      let w = set.weightLb,
                      let r = set.reps
                else { return nil }
                return (id: id, setNumber: set.setNumber, e1rm: epleyOneRepMax(weightLb: w, reps: r))
            }
            let topId: Int64? = scored
                .sorted { a, b in
                    if a.e1rm != b.e1rm { return a.e1rm > b.e1rm }
                    return a.setNumber < b.setNumber
                }
                .first?
                .id

            for var s in allSets {
                let shouldBeTop = (s.id == topId)
                if s.isTopSet != shouldBeTop {
                    s.isTopSet = shouldBeTop
                    try s.update(db)
                }
            }
        }
    }

    /// Read all sets for one exercise in one workout, in set-number order.
    public func sets(
        workoutId: Int64,
        exerciseId: Int64
    ) async throws -> [ExerciseSet] {
        try await read { db in
            try ExerciseSet
                .filter(Column("workout_id") == workoutId)
                .filter(Column("exercise_id") == exerciseId)
                .order(Column("set_number"))
                .fetchAll(db)
        }
    }

    // MARK: View hydration

    /// Load everything the Workouts tab needs for a given day in one round
    /// trip: the workout row (if any) plus all its sets grouped by exercise.
    public func workoutDaySnapshot(
        on date: Date,
        calendar: Calendar = .current
    ) async throws -> WorkoutDaySnapshot {
        let day = calendar.startOfDay(for: date)
        let nextDay = calendar.date(byAdding: .day, value: 1, to: day)!
        return try await read { db in
            guard let w = try Workout
                .filter(Column("date") >= day)
                .filter(Column("date") < nextDay)
                .order(Column("id"))
                .fetchOne(db),
                  let wid = w.id
            else {
                return WorkoutDaySnapshot(workout: nil, setsByExerciseId: [:])
            }

            let allSets = try ExerciseSet
                .filter(Column("workout_id") == wid)
                .order(Column("set_number"))
                .fetchAll(db)

            var grouped: [Int64: [ExerciseSet]] = [:]
            for s in allSets {
                grouped[s.exerciseId, default: []].append(s)
            }
            return WorkoutDaySnapshot(workout: w, setsByExerciseId: grouped)
        }
    }

    // MARK: Workout-level field updates

    /// Update duration, HR, and notes on the workout row for the given day.
    /// Creates the workout row if it doesn't exist yet (using `sessionType`
    /// as the initial value). Passing nil for any parameter is a no-op for
    /// that column — pass a value to write, omit to leave alone.
    public func updateWorkoutFields(
        on date: Date,
        sessionType: Workout.SessionType,
        durationMin: Int? = nil,
        avgHr: Int? = nil,
        notes: String? = nil,
        clearNotes: Bool = false,
        calendar: Calendar = .current
    ) async throws {
        let workoutId = try await getOrCreateWorkout(on: date, sessionType: sessionType, calendar: calendar)
        try await write { db in
            guard var w = try Workout.fetchOne(db, key: workoutId) else { return }
            if let d = durationMin { w.durationMin = d }
            if let h = avgHr       { w.avgHr = h }
            if clearNotes {
                w.notes = nil
            } else if let n = notes {
                w.notes = n
            }
            try w.update(db)
        }
    }

    /// Look up an exercise by exact-name match. Read-only counterpart to
    /// `getOrCreateExercise` — for cases where creating a row would be
    /// premature (e.g. hydrating view state before the user has logged
    /// anything).
    public func exercise(named name: String) async throws -> Exercise? {
        try await read { db in
            try Exercise.filter(Column("name") == name).fetchOne(db)
        }
    }
}
