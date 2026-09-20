import Foundation
import GRDB

/// One exercise row as the session screen needs it: what the program
/// prescribes, what has been entered so far, and what was done last time.
public struct SessionRow: Hashable, Sendable {

    /// Prescription from the program — name, cue, sets, reps.
    public let exercise: ProgramExercise

    public let exerciseId: Int64

    /// What has been entered for this session, if anything.
    public let logged: ExerciseLog?

    /// The most recent completed entry for this exercise in any earlier
    /// session, in any phase. This is the ghost value in the input fields.
    public let lastTime: ExerciseLog?

    public init(
        exercise: ProgramExercise,
        exerciseId: Int64,
        logged: ExerciseLog?,
        lastTime: ExerciseLog?
    ) {
        self.exercise = exercise
        self.exerciseId = exerciseId
        self.logged = logged
        self.lastTime = lastTime
    }
}

/// Everything the session screen renders for one `(phase, ordinal)`.
public struct SessionSnapshot: Hashable, Sendable {
    public let phase: Phase
    public let ordinal: Int

    /// The prescribed session for this ordinal, from the rotation.
    public let session: ProgramSession

    /// Nil until something is logged or the session is marked complete.
    /// Viewing a session does not create a row.
    public let workout: Workout?

    /// Empty for the two recovery slots.
    public let rows: [SessionRow]

    public var isComplete: Bool { workout?.isComplete ?? false }

    public init(
        phase: Phase,
        ordinal: Int,
        session: ProgramSession,
        workout: Workout?,
        rows: [SessionRow]
    ) {
        self.phase = phase
        self.ordinal = ordinal
        self.session = session
        self.workout = workout
        self.rows = rows
    }
}

public extension AppDatabase {

    // MARK: - Seeding

    /// Ensure every exercise named by the program exists in `exercises`.
    ///
    /// Idempotent, and cheap enough to call on every launch. Doing this up
    /// front keeps the session screen a pure read — nothing is created just
    /// by looking at a session.
    ///
    /// Never deletes. An exercise dropped from a future program keeps its row
    /// and its history.
    @discardableResult
    func seedExercises(from program: Program) async throws -> Int {
        let names = program.allExerciseNames
        return try await write { db in
            let existing = try String.fetchSet(db, sql: "SELECT name FROM exercises")
            let missing = names.subtracting(existing).sorted()
            for name in missing {
                var exercise = Exercise(name: name)
                try exercise.insert(db)
            }
            return missing.count
        }
    }

    // MARK: - Phase progress

    /// How many sessions of this phase are marked complete.
    ///
    /// The denominator on the home screen is `Phase.nominalSessionCount`, but
    /// this is not capped by it — 37/30 is a valid reading.
    func completedCount(phase: Phase) async throws -> Int {
        try await read { db in
            try Int.fetchOne(
                db,
                sql: """
                    SELECT COUNT(*) FROM workouts
                    WHERE phase = ? AND completed_at IS NOT NULL
                    """,
                arguments: [phase.rawValue]
            ) ?? 0
        }
    }

    /// The ordinal to open when the phase is tapped.
    ///
    /// The lowest ordinal not yet marked complete. Sessions are worked in
    /// order, so this is the next one due.
    ///
    /// Consequence worth knowing: a session left incomplete holds this value
    /// at that ordinal. Completing sessions 1, 3 and 4 still opens 2. The
    /// session screen's next control steps past it when that is not what you
    /// want.
    func pendingOrdinal(phase: Phase) async throws -> Int {
        try await read { db in
            let completed = try Int.fetchSet(
                db,
                sql: """
                    SELECT ordinal FROM workouts
                    WHERE phase = ? AND completed_at IS NOT NULL
                    """,
                arguments: [phase.rawValue]
            )
            var ordinal = 1
            while completed.contains(ordinal) { ordinal += 1 }
            return ordinal
        }
    }

    // MARK: - Reading a session

    /// Assemble everything the session screen shows for one ordinal.
    ///
    /// Pure read. The workout row is nil until the first log or completion.
    func sessionSnapshot(
        program: Program,
        phase: Phase,
        ordinal: Int
    ) async throws -> SessionSnapshot {
        precondition(ordinal >= 1, "ordinal is 1-based, got \(ordinal)")
        let session = program.session(phase: phase, ordinal: ordinal)

        return try await read { db in
            let workout = try Self.fetchWorkout(db, phase: phase, ordinal: ordinal)

            guard !session.exercises.isEmpty else {
                return SessionSnapshot(
                    phase: phase,
                    ordinal: ordinal,
                    session: session,
                    workout: workout,
                    rows: []
                )
            }

            let idsByName = try Self.exerciseIds(db, names: session.exercises.map(\.name))

            var loggedByExerciseId: [Int64: ExerciseLog] = [:]
            if let workoutId = workout?.id {
                let logs = try ExerciseLog
                    .filter(Column("workout_id") == workoutId)
                    .fetchAll(db)
                loggedByExerciseId = Dictionary(
                    logs.compactMap { log in (log.exerciseId, log) },
                    uniquingKeysWith: { first, _ in first }
                )
            }

            let lastTime = try Self.lastLogs(
                db,
                exerciseIds: Set(idsByName.values),
                excludingWorkoutId: workout?.id
            )

            let rows = session.exercises.compactMap { exercise -> SessionRow? in
                guard let id = idsByName[exercise.name] else { return nil }
                return SessionRow(
                    exercise: exercise,
                    exerciseId: id,
                    logged: loggedByExerciseId[id],
                    lastTime: lastTime[id]
                )
            }

            return SessionSnapshot(
                phase: phase,
                ordinal: ordinal,
                session: session,
                workout: workout,
                rows: rows
            )
        }
    }

    // MARK: - Writing

    /// Record weight and reps for one exercise in one session.
    ///
    /// Creates the workout row on first write. Passing nil for both clears the
    /// entry rather than deleting the row, so the field simply reads empty
    /// again and the ghost value returns.
    func logEntry(
        phase: Phase,
        ordinal: Int,
        exerciseName: String,
        weightLb: Double?,
        reps: Int?
    ) async throws {
        precondition(ordinal >= 1, "ordinal is 1-based, got \(ordinal)")
        try await write { db in
            let workoutId = try Self.workoutId(db, phase: phase, ordinal: ordinal, creating: true)
            let exerciseId = try Self.exerciseId(db, name: exerciseName)

            if var existing = try ExerciseLog
                .filter(Column("workout_id") == workoutId)
                .filter(Column("exercise_id") == exerciseId)
                .fetchOne(db)
            {
                existing.weightLb = weightLb
                existing.reps = reps
                try existing.update(db)
            } else {
                var new = ExerciseLog(
                    workoutId: workoutId,
                    exerciseId: exerciseId,
                    weightLb: weightLb,
                    reps: reps
                )
                try new.insert(db)
            }
        }
    }

    /// Mark a session complete or pending.
    ///
    /// `completedAt` is the only date the app records, so completing is what
    /// gives a session a position in history — and therefore what makes its
    /// numbers eligible as a future "last time".
    @discardableResult
    func setCompleted(
        phase: Phase,
        ordinal: Int,
        _ complete: Bool,
        at date: Date = Date()
    ) async throws -> Workout {
        precondition(ordinal >= 1, "ordinal is 1-based, got \(ordinal)")
        return try await write { db in
            let id = try Self.workoutId(db, phase: phase, ordinal: ordinal, creating: true)
            guard var workout = try Workout.fetchOne(db, key: id) else {
                throw DatabaseError(message: "workout \(id) vanished between create and read")
            }
            workout.completedAt = complete ? date : nil
            try workout.update(db)
            return workout
        }
    }

    // MARK: - Internals

    private static func fetchWorkout(
        _ db: Database,
        phase: Phase,
        ordinal: Int
    ) throws -> Workout? {
        try Workout
            .filter(Column("phase") == phase.rawValue)
            .filter(Column("ordinal") == ordinal)
            .fetchOne(db)
    }

    private static func workoutId(
        _ db: Database,
        phase: Phase,
        ordinal: Int,
        creating: Bool
    ) throws -> Int64 {
        if let existing = try fetchWorkout(db, phase: phase, ordinal: ordinal), let id = existing.id {
            return id
        }
        guard creating else {
            throw DatabaseError(message: "no workout for phase \(phase.rawValue) ordinal \(ordinal)")
        }
        var workout = Workout(phase: phase, ordinal: ordinal)
        try workout.insert(db)
        guard let id = workout.id else {
            throw DatabaseError(message: "insert did not yield a workout id")
        }
        return id
    }

    private static func exerciseId(_ db: Database, name: String) throws -> Int64 {
        if let existing = try Exercise.filter(Column("name") == name).fetchOne(db),
           let id = existing.id {
            return id
        }
        // Seeding should have covered this, but a program change between
        // launches would otherwise fail a write the user just made.
        var exercise = Exercise(name: name)
        try exercise.insert(db)
        guard let id = exercise.id else {
            throw DatabaseError(message: "insert did not yield an exercise id")
        }
        return id
    }

    private static func exerciseIds(_ db: Database, names: [String]) throws -> [String: Int64] {
        let rows = try Exercise.filter(names.contains(Column("name"))).fetchAll(db)
        return Dictionary(
            rows.compactMap { exercise in exercise.id.map { (exercise.name, $0) } },
            uniquingKeysWith: { first, _ in first }
        )
    }

    /// Most recent completed entry per exercise.
    ///
    /// Only completed sessions are considered: `completed_at` is the sole date
    /// in the schema, so an unfinished session has no position in history to be
    /// ordered by.
    ///
    /// Fetches the matching history and reduces in Swift rather than reaching
    /// for a window function. A full 90-session cycle produces on the order of
    /// 800 rows, so the simpler query is not worth optimising away.
    private static func lastLogs(
        _ db: Database,
        exerciseIds: Set<Int64>,
        excludingWorkoutId: Int64?
    ) throws -> [Int64: ExerciseLog] {
        guard !exerciseIds.isEmpty else { return [:] }

        let logs = try ExerciseLog.fetchAll(
            db,
            sql: """
                SELECT el.id, el.workout_id, el.exercise_id, el.weight_lb, el.reps
                FROM exercise_logs el
                JOIN workouts w ON w.id = el.workout_id
                WHERE w.completed_at IS NOT NULL
                  AND (el.weight_lb IS NOT NULL OR el.reps IS NOT NULL)
                ORDER BY w.completed_at DESC, w.id DESC
                """
        )

        var result: [Int64: ExerciseLog] = [:]
        for log in logs {
            guard exerciseIds.contains(log.exerciseId) else { continue }
            guard log.workoutId != excludingWorkoutId else { continue }
            if result[log.exerciseId] == nil {
                result[log.exerciseId] = log
            }
        }
        return result
    }
}
