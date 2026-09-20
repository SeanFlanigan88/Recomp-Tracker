import XCTest
import GRDB
@testable import RecompCore

/// Behavioral tests for the Cycle 3 schema.
///
/// These describe guarantees the rest of the app leans on, not the shape of the
/// DDL: uniqueness that makes `(phase, ordinal)` a real identity, referential
/// rules that decide what a delete does, and the explicit decision that a phase
/// may run past 30 sessions.
final class SchemaTests: XCTestCase {

    private func makeDB() throws -> AppDatabase {
        try AppDatabase.inMemory()
    }

    @discardableResult
    private func insertWorkout(
        _ db: AppDatabase,
        phase: Phase = .one,
        ordinal: Int = 1,
        completedAt: Date? = nil
    ) async throws -> Int64 {
        try await db.write { db in
            var w = Workout(phase: phase, ordinal: ordinal, completedAt: completedAt)
            try w.insert(db)
            return try XCTUnwrap(w.id)
        }
    }

    @discardableResult
    private func insertExercise(_ db: AppDatabase, name: String) async throws -> Int64 {
        try await db.write { db in
            var e = Exercise(name: name)
            try e.insert(db)
            return try XCTUnwrap(e.id)
        }
    }

    // MARK: - Identity

    func testPhaseAndOrdinalTogetherAreUnique() async throws {
        let db = try makeDB()
        try await insertWorkout(db, phase: .one, ordinal: 5)

        do {
            try await insertWorkout(db, phase: .one, ordinal: 5)
            XCTFail("expected a uniqueness violation on (phase, ordinal)")
        } catch let error as DatabaseError {
            XCTAssertEqual(error.resultCode, .SQLITE_CONSTRAINT)
        }
    }

    func testSameOrdinalInDifferentPhasesCoexist() async throws {
        let db = try makeDB()
        try await insertWorkout(db, phase: .one, ordinal: 1)
        try await insertWorkout(db, phase: .two, ordinal: 1)
        try await insertWorkout(db, phase: .three, ordinal: 1)

        let count = try await db.read { db in try Workout.fetchCount(db) }
        XCTAssertEqual(count, 3, "phases are independent sequences")
    }

    func testOrdinalMayExceedNominalPhaseLength() async throws {
        let db = try makeDB()
        let id = try await insertWorkout(db, phase: .one, ordinal: 37)

        let stored = try await db.read { db in try Workout.fetchOne(db, key: id) }
        XCTAssertEqual(stored?.ordinal, 37, "37/30 is a valid state, not an error")
    }

    func testOrdinalMustBePositive() async throws {
        let db = try makeDB()
        do {
            try await insertWorkout(db, ordinal: 0)
            XCTFail("expected a CHECK violation on ordinal")
        } catch let error as DatabaseError {
            XCTAssertEqual(error.resultCode, .SQLITE_CONSTRAINT)
        }
    }

    func testPhaseOutsideOneToThreeIsRejected() async throws {
        let db = try makeDB()
        do {
            try await db.write { db in
                try db.execute(
                    sql: "INSERT INTO workouts (phase, ordinal) VALUES (?, ?)",
                    arguments: [4, 1]
                )
            }
            XCTFail("expected a CHECK violation on phase")
        } catch let error as DatabaseError {
            XCTAssertEqual(error.resultCode, .SQLITE_CONSTRAINT)
        }
    }

    // MARK: - Completion

    func testCompletedAtIsNilUntilSet() async throws {
        let db = try makeDB()
        let id = try await insertWorkout(db)

        let pending = try await db.read { db in try Workout.fetchOne(db, key: id) }
        XCTAssertNil(pending?.completedAt)
        XCTAssertEqual(pending?.isComplete, false)
    }

    func testCompletedAtRoundTrips() async throws {
        let db = try makeDB()
        let when = Date(timeIntervalSince1970: 1_789_000_000)
        let id = try await insertWorkout(db, completedAt: when)

        let fetched = try await db.read { db in try Workout.fetchOne(db, key: id) }
        let stored = try XCTUnwrap(fetched)
        let completedAt = try XCTUnwrap(stored.completedAt)
        XCTAssertEqual(
            completedAt.timeIntervalSince1970,
            when.timeIntervalSince1970,
            accuracy: 0.001
        )
        XCTAssertTrue(stored.isComplete)
    }

    // MARK: - Exercises

    func testExerciseNameIsUnique() async throws {
        let db = try makeDB()
        try await insertExercise(db, name: "KB goblet squat")

        do {
            try await insertExercise(db, name: "KB goblet squat")
            XCTFail("expected a uniqueness violation on exercises.name")
        } catch let error as DatabaseError {
            XCTAssertEqual(error.resultCode, .SQLITE_CONSTRAINT)
        }
    }

    func testBlankExerciseNameIsRejected() async throws {
        let db = try makeDB()
        do {
            try await insertExercise(db, name: "   ")
            XCTFail("expected a CHECK violation on exercises.name")
        } catch let error as DatabaseError {
            XCTAssertEqual(error.resultCode, .SQLITE_CONSTRAINT)
        }
    }

    // MARK: - Logs

    func testOneLogPerExercisePerWorkout() async throws {
        let db = try makeDB()
        let workoutId = try await insertWorkout(db)
        let exerciseId = try await insertExercise(db, name: "DB row")

        try await db.write { db in
            var log = ExerciseLog(workoutId: workoutId, exerciseId: exerciseId, weightLb: 55, reps: 12)
            try log.insert(db)
        }

        do {
            try await db.write { db in
                var dup = ExerciseLog(workoutId: workoutId, exerciseId: exerciseId, weightLb: 60, reps: 10)
                try dup.insert(db)
            }
            XCTFail("expected a uniqueness violation on (workout_id, exercise_id)")
        } catch let error as DatabaseError {
            XCTAssertEqual(error.resultCode, .SQLITE_CONSTRAINT)
        }
    }

    func testSameExerciseLogsIndependentlyAcrossWorkouts() async throws {
        let db = try makeDB()
        let first = try await insertWorkout(db, phase: .one, ordinal: 1)
        let second = try await insertWorkout(db, phase: .two, ordinal: 1)
        let exerciseId = try await insertExercise(db, name: "KB goblet squat")

        try await db.write { db in
            var a = ExerciseLog(workoutId: first, exerciseId: exerciseId, weightLb: 40, reps: 15)
            try a.insert(db)
            var b = ExerciseLog(workoutId: second, exerciseId: exerciseId, weightLb: 45, reps: 12)
            try b.insert(db)
        }

        let count = try await db.read { db in try ExerciseLog.fetchCount(db) }
        XCTAssertEqual(count, 2, "one exercise carries history across phases")
    }

    func testWeightMayBeNilForBodyweightWork() async throws {
        let db = try makeDB()
        let workoutId = try await insertWorkout(db)
        let exerciseId = try await insertExercise(db, name: "Hollow hold")

        let id: Int64 = try await db.write { db in
            var log = ExerciseLog(workoutId: workoutId, exerciseId: exerciseId, weightLb: nil, reps: 45)
            try log.insert(db)
            return try XCTUnwrap(log.id)
        }

        let stored = try await db.read { db in try ExerciseLog.fetchOne(db, key: id) }
        XCTAssertNil(stored?.weightLb)
        XCTAssertEqual(stored?.reps, 45, "reps carries seconds here; no unit column by design")
    }

    func testNegativeWeightIsRejected() async throws {
        let db = try makeDB()
        let workoutId = try await insertWorkout(db)
        let exerciseId = try await insertExercise(db, name: "DB curl")

        do {
            try await db.write { db in
                var log = ExerciseLog(workoutId: workoutId, exerciseId: exerciseId, weightLb: -5, reps: 10)
                try log.insert(db)
            }
            XCTFail("expected a CHECK violation on weight_lb")
        } catch let error as DatabaseError {
            XCTAssertEqual(error.resultCode, .SQLITE_CONSTRAINT)
        }
    }

    // MARK: - Referential rules

    func testDeletingWorkoutCascadesToLogs() async throws {
        let db = try makeDB()
        let workoutId = try await insertWorkout(db)
        let exerciseId = try await insertExercise(db, name: "KB swing")

        try await db.write { db in
            var log = ExerciseLog(workoutId: workoutId, exerciseId: exerciseId, weightLb: 40, reps: 15)
            try log.insert(db)
            _ = try Workout.deleteOne(db, key: workoutId)
        }

        let remaining = try await db.read { db in try ExerciseLog.fetchCount(db) }
        XCTAssertEqual(remaining, 0)
    }

    func testDeletingExerciseWithLogsIsRefused() async throws {
        let db = try makeDB()
        let workoutId = try await insertWorkout(db)
        let exerciseId = try await insertExercise(db, name: "Renegade row")

        try await db.write { db in
            var log = ExerciseLog(workoutId: workoutId, exerciseId: exerciseId, weightLb: 35, reps: 10)
            try log.insert(db)
        }

        do {
            _ = try await db.write { db in try Exercise.deleteOne(db, key: exerciseId) }
            XCTFail("expected a foreign-key restriction")
        } catch let error as DatabaseError {
            XCTAssertEqual(error.resultCode, .SQLITE_CONSTRAINT)
        }
    }

    func testLogRequiresAnExistingWorkout() async throws {
        let db = try makeDB()
        let exerciseId = try await insertExercise(db, name: "Bear crawl")

        do {
            try await db.write { db in
                var log = ExerciseLog(workoutId: 9_999, exerciseId: exerciseId, reps: 20)
                try log.insert(db)
            }
            XCTFail("expected a foreign-key violation")
        } catch let error as DatabaseError {
            XCTAssertEqual(error.resultCode, .SQLITE_CONSTRAINT)
        }
    }
}

/// Rotation arithmetic. Pure functions, no database.
final class PhaseTests: XCTestCase {

    func testSlotWrapsEverySevenSessions() {
        XCTAssertEqual(Phase.slot(forOrdinal: 1), 1)
        XCTAssertEqual(Phase.slot(forOrdinal: 7), 7)
        XCTAssertEqual(Phase.slot(forOrdinal: 8), 1)
        XCTAssertEqual(Phase.slot(forOrdinal: 14), 7)
        XCTAssertEqual(Phase.slot(forOrdinal: 15), 1)
    }

    func testOrdinalThirtyLandsOnSlotTwo() {
        // 30 = four full rotations plus slots 1 and 2, so a nominal phase ends
        // on its second session type.
        XCTAssertEqual(Phase.slot(forOrdinal: 30), 2)
    }

    func testSlotKeepsCyclingPastNominalLength() {
        XCTAssertEqual(Phase.slot(forOrdinal: 37), 2)
        XCTAssertEqual(Phase.slot(forOrdinal: 100), 2)
    }

    func testSlotIsAlwaysWithinRotation() {
        for ordinal in 1...200 {
            let slot = Phase.slot(forOrdinal: ordinal)
            XCTAssertTrue((1...Phase.rotationLength).contains(slot), "ordinal \(ordinal) gave slot \(slot)")
        }
    }

    func testPhaseRawValuesAreStable() {
        XCTAssertEqual(Phase.allCases.map(\.rawValue), [1, 2, 3])
        XCTAssertEqual(Phase.two.title, "Phase 2")
    }
}
