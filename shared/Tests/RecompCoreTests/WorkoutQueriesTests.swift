import XCTest
import GRDB
@testable import RecompCore

final class WorkoutQueriesTests: XCTestCase {

    private let program = Program.cycle3

    private func seeded() async throws -> AppDatabase {
        let db = try AppDatabase.inMemory()
        try await db.seedExercises(from: program)
        return db
    }

    /// A date `days` after a fixed epoch, so ordering assertions are explicit
    /// rather than dependent on how fast the test runs.
    private func day(_ days: Int) -> Date {
        Date(timeIntervalSince1970: 1_789_000_000 + Double(days) * 86_400)
    }

    // MARK: - Seeding

    func testSeedingCreatesEveryProgramExercise() async throws {
        let db = try AppDatabase.inMemory()
        let created = try await db.seedExercises(from: program)
        XCTAssertEqual(created, program.allExerciseNames.count)

        let stored = try await db.read { db in try Exercise.fetchCount(db) }
        XCTAssertEqual(stored, program.allExerciseNames.count)
    }

    func testSeedingIsIdempotent() async throws {
        let db = try await seeded()
        let secondPass = try await db.seedExercises(from: program)
        XCTAssertEqual(secondPass, 0)

        let stored = try await db.read { db in try Exercise.fetchCount(db) }
        XCTAssertEqual(stored, program.allExerciseNames.count)
    }

    func testSeedingNeverRemovesAnExercise() async throws {
        let db = try await seeded()
        try await db.write { db in
            var retired = Exercise(name: "Barbell back squat")
            try retired.insert(db)
        }

        try await db.seedExercises(from: program)

        let names = try await db.read { db in try String.fetchSet(db, sql: "SELECT name FROM exercises") }
        XCTAssertTrue(names.contains("Barbell back squat"), "history from an older cycle must survive")
    }

    // MARK: - Phase progress

    func testCountsAndPendingStartEmpty() async throws {
        let db = try await seeded()
        for phase in Phase.allCases {
            let count = try await db.completedCount(phase: phase)
            XCTAssertEqual(count, 0)
            let pending = try await db.pendingOrdinal(phase: phase)
            XCTAssertEqual(pending, 1)
        }
    }

    func testCompletingAdvancesTheCounterAndThePendingOrdinal() async throws {
        let db = try await seeded()
        try await db.setCompleted(phase: .one, ordinal: 1, true, at: day(0))
        try await db.setCompleted(phase: .one, ordinal: 2, true, at: day(1))

        let count = try await db.completedCount(phase: .one)
        XCTAssertEqual(count, 2)
        let pending = try await db.pendingOrdinal(phase: .one)
        XCTAssertEqual(pending, 3)
    }

    func testPendingOrdinalReturnsToTheLowestGap() async throws {
        let db = try await seeded()
        try await db.setCompleted(phase: .one, ordinal: 1, true, at: day(0))
        try await db.setCompleted(phase: .one, ordinal: 3, true, at: day(2))
        try await db.setCompleted(phase: .one, ordinal: 4, true, at: day(3))

        let pending = try await db.pendingOrdinal(phase: .one)
        XCTAssertEqual(pending, 2, "sessions are worked in order; the gap is next")

        let count = try await db.completedCount(phase: .one)
        XCTAssertEqual(count, 3, "the counter reflects work done, not position")
    }

    func testPhasesTrackIndependently() async throws {
        let db = try await seeded()
        try await db.setCompleted(phase: .one, ordinal: 1, true, at: day(0))

        let twoCount = try await db.completedCount(phase: .two)
        XCTAssertEqual(twoCount, 0)
        let twoPending = try await db.pendingOrdinal(phase: .two)
        XCTAssertEqual(twoPending, 1)
    }

    func testCounterIsNotCappedAtNominalLength() async throws {
        let db = try await seeded()
        for ordinal in 1...32 {
            try await db.setCompleted(phase: .one, ordinal: ordinal, true, at: day(ordinal))
        }

        let count = try await db.completedCount(phase: .one)
        XCTAssertEqual(count, 32, "32/30 is a valid reading")
        let pending = try await db.pendingOrdinal(phase: .one)
        XCTAssertEqual(pending, 33)
    }

    func testUncompletingRestoresThePendingOrdinal() async throws {
        let db = try await seeded()
        try await db.setCompleted(phase: .one, ordinal: 1, true, at: day(0))
        try await db.setCompleted(phase: .one, ordinal: 1, false)

        let count = try await db.completedCount(phase: .one)
        XCTAssertEqual(count, 0)
        let pending = try await db.pendingOrdinal(phase: .one)
        XCTAssertEqual(pending, 1)
    }

    // MARK: - Snapshot

    func testViewingASessionCreatesNothing() async throws {
        let db = try await seeded()
        let snapshot = try await db.sessionSnapshot(program: program, phase: .three, ordinal: 1)

        XCTAssertNil(snapshot.workout, "peeking at a phase must not write")
        XCTAssertFalse(snapshot.isComplete)

        let workouts = try await db.read { db in try Workout.fetchCount(db) }
        XCTAssertEqual(workouts, 0)
    }

    func testSnapshotRowsMatchTheProgramInOrder() async throws {
        let db = try await seeded()
        let snapshot = try await db.sessionSnapshot(program: program, phase: .one, ordinal: 5)

        let expected = program.phase(.one).session(slot: 5)
        XCTAssertEqual(snapshot.session, expected)
        XCTAssertEqual(snapshot.rows.map(\.exercise), expected.exercises)
        XCTAssertTrue(snapshot.rows.allSatisfy { $0.logged == nil && $0.lastTime == nil })
    }

    func testRecoverySlotsHaveNoRows() async throws {
        let db = try await seeded()
        for slot in [3, 7] {
            let snapshot = try await db.sessionSnapshot(program: program, phase: .one, ordinal: slot)
            XCTAssertTrue(snapshot.rows.isEmpty, "slot \(slot)")
            XCTAssertFalse(snapshot.session.isLifting)
        }
    }

    func testSnapshotResolvesPastNominalLength() async throws {
        let db = try await seeded()
        let snapshot = try await db.sessionSnapshot(program: program, phase: .one, ordinal: 37)
        XCTAssertEqual(snapshot.ordinal, 37)
        XCTAssertEqual(snapshot.session.slot, 2)
    }

    // MARK: - Logging

    func testLoggingCreatesTheWorkoutAndShowsUpInTheSnapshot() async throws {
        let db = try await seeded()
        try await db.logEntry(
            phase: .one, ordinal: 1,
            exerciseName: "KB goblet squat",
            weightLb: 40, reps: 15
        )

        let snapshot = try await db.sessionSnapshot(program: program, phase: .one, ordinal: 1)
        XCTAssertNotNil(snapshot.workout)
        XCTAssertFalse(snapshot.isComplete, "logging is not completing")

        let row = try XCTUnwrap(snapshot.rows.first { $0.exercise.name == "KB goblet squat" })
        XCTAssertEqual(row.logged?.weightLb, 40)
        XCTAssertEqual(row.logged?.reps, 15)
    }

    func testLoggingTwiceUpdatesOneRow() async throws {
        let db = try await seeded()
        try await db.logEntry(phase: .one, ordinal: 5, exerciseName: "DB row", weightLb: 50, reps: 12)
        try await db.logEntry(phase: .one, ordinal: 5, exerciseName: "DB row", weightLb: 55, reps: 10)

        let logs = try await db.read { db in try ExerciseLog.fetchCount(db) }
        XCTAssertEqual(logs, 1)

        let snapshot = try await db.sessionSnapshot(program: program, phase: .one, ordinal: 5)
        let row = try XCTUnwrap(snapshot.rows.first { $0.exercise.name == "DB row" })
        XCTAssertEqual(row.logged?.weightLb, 55)
        XCTAssertEqual(row.logged?.reps, 10)
    }

    func testClearingAnEntryLeavesItEmptyRatherThanDeleted() async throws {
        let db = try await seeded()
        try await db.logEntry(phase: .one, ordinal: 1, exerciseName: "KB swing", weightLb: 40, reps: 15)
        try await db.logEntry(phase: .one, ordinal: 1, exerciseName: "KB swing", weightLb: nil, reps: nil)

        let snapshot = try await db.sessionSnapshot(program: program, phase: .one, ordinal: 1)
        let row = try XCTUnwrap(snapshot.rows.first { $0.exercise.name == "KB swing" })
        XCTAssertEqual(row.logged?.isEmpty, true)
    }

    func testBodyweightWorkLogsRepsWithoutWeight() async throws {
        let db = try await seeded()
        try await db.logEntry(
            phase: .one, ordinal: 5,
            exerciseName: "Hollow hold",
            weightLb: nil, reps: 45
        )

        let snapshot = try await db.sessionSnapshot(program: program, phase: .one, ordinal: 5)
        let row = try XCTUnwrap(snapshot.rows.first { $0.exercise.name == "Hollow hold" })
        XCTAssertNil(row.logged?.weightLb)
        XCTAssertEqual(row.logged?.reps, 45)
    }

    // MARK: - Last time

    func testLastTimeIsNilWithNoHistory() async throws {
        let db = try await seeded()
        let snapshot = try await db.sessionSnapshot(program: program, phase: .one, ordinal: 1)
        XCTAssertTrue(snapshot.rows.allSatisfy { $0.lastTime == nil })
    }

    func testLastTimeShowsThePreviousCompletedSession() async throws {
        let db = try await seeded()
        try await db.logEntry(phase: .one, ordinal: 1, exerciseName: "KB goblet squat", weightLb: 40, reps: 15)
        try await db.setCompleted(phase: .one, ordinal: 1, true, at: day(0))

        // Ordinal 8 is the same slot one rotation later.
        let snapshot = try await db.sessionSnapshot(program: program, phase: .one, ordinal: 8)
        let row = try XCTUnwrap(snapshot.rows.first { $0.exercise.name == "KB goblet squat" })
        XCTAssertEqual(row.lastTime?.weightLb, 40)
        XCTAssertEqual(row.lastTime?.reps, 15)
        XCTAssertNil(row.logged)
    }

    func testLastTimeTakesTheMostRecentByCompletionDate() async throws {
        let db = try await seeded()
        try await db.logEntry(phase: .one, ordinal: 1, exerciseName: "KB goblet squat", weightLb: 40, reps: 15)
        try await db.setCompleted(phase: .one, ordinal: 1, true, at: day(0))

        try await db.logEntry(phase: .one, ordinal: 8, exerciseName: "KB goblet squat", weightLb: 45, reps: 13)
        try await db.setCompleted(phase: .one, ordinal: 8, true, at: day(7))

        let snapshot = try await db.sessionSnapshot(program: program, phase: .one, ordinal: 15)
        let row = try XCTUnwrap(snapshot.rows.first { $0.exercise.name == "KB goblet squat" })
        XCTAssertEqual(row.lastTime?.weightLb, 45)
    }

    func testLastTimeCarriesAcrossPhases() async throws {
        let db = try await seeded()
        try await db.logEntry(phase: .one, ordinal: 1, exerciseName: "KB goblet squat", weightLb: 40, reps: 15)
        try await db.setCompleted(phase: .one, ordinal: 1, true, at: day(0))

        // Phase 2 slot 1 prescribes the same canonical exercise. This is the
        // whole reason names are canonicalized.
        let snapshot = try await db.sessionSnapshot(program: program, phase: .two, ordinal: 1)
        let row = try XCTUnwrap(snapshot.rows.first { $0.exercise.name == "KB goblet squat" })
        XCTAssertEqual(row.lastTime?.weightLb, 40)
        XCTAssertEqual(row.exercise.cue, "heavier KB", "prescription still comes from phase 2")
    }

    func testLastTimeExcludesTheSessionBeingViewed() async throws {
        let db = try await seeded()
        try await db.logEntry(phase: .one, ordinal: 1, exerciseName: "KB goblet squat", weightLb: 40, reps: 15)
        try await db.setCompleted(phase: .one, ordinal: 1, true, at: day(0))

        let snapshot = try await db.sessionSnapshot(program: program, phase: .one, ordinal: 1)
        let row = try XCTUnwrap(snapshot.rows.first { $0.exercise.name == "KB goblet squat" })
        XCTAssertEqual(row.logged?.weightLb, 40)
        XCTAssertNil(row.lastTime, "a session is not its own history")
    }

    func testLastTimeIgnoresIncompleteSessions() async throws {
        let db = try await seeded()
        try await db.logEntry(phase: .one, ordinal: 1, exerciseName: "KB goblet squat", weightLb: 40, reps: 15)
        // Deliberately not completed.

        let snapshot = try await db.sessionSnapshot(program: program, phase: .one, ordinal: 8)
        let row = try XCTUnwrap(snapshot.rows.first { $0.exercise.name == "KB goblet squat" })
        XCTAssertNil(row.lastTime, "completion is what puts a session in history")
    }

    func testLastTimeIgnoresEmptyEntries() async throws {
        let db = try await seeded()
        try await db.logEntry(phase: .one, ordinal: 1, exerciseName: "KB goblet squat", weightLb: nil, reps: nil)
        try await db.setCompleted(phase: .one, ordinal: 1, true, at: day(0))

        let snapshot = try await db.sessionSnapshot(program: program, phase: .one, ordinal: 8)
        let row = try XCTUnwrap(snapshot.rows.first { $0.exercise.name == "KB goblet squat" })
        XCTAssertNil(row.lastTime)
    }

    func testUncompletingRemovesASessionFromHistory() async throws {
        let db = try await seeded()
        try await db.logEntry(phase: .one, ordinal: 1, exerciseName: "KB goblet squat", weightLb: 40, reps: 15)
        try await db.setCompleted(phase: .one, ordinal: 1, true, at: day(0))
        try await db.setCompleted(phase: .one, ordinal: 1, false)

        let snapshot = try await db.sessionSnapshot(program: program, phase: .one, ordinal: 8)
        let row = try XCTUnwrap(snapshot.rows.first { $0.exercise.name == "KB goblet squat" })
        XCTAssertNil(row.lastTime)
    }
}
