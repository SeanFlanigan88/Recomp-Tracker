import XCTest
import GRDB
@testable import RecompCore

/// Coverage for the Log tab's read/write helpers on `AppDatabase`, and for
/// the M002 water_oz migration.
final class LogQueriesTests: XCTestCase {

    // MARK: - M002 migration

    func testM002AddsWaterOzColumn() async throws {
        let db = try AppDatabase.inMemory()

        // pragma_table_info(name) is the table-valued function form of
        // PRAGMA table_info — lets us SELECT a single column cleanly.
        let columnNames = try await db.read { db in
            try String.fetchAll(db, sql: """
                SELECT name FROM pragma_table_info('nutrition_log')
                """)
        }

        XCTAssertTrue(columnNames.contains("water_oz"),
                      "M002 should have added water_oz column; got: \(columnNames)")
    }

    func testNutritionLogRoundTripsWaterOz() async throws {
        let db = try AppDatabase.inMemory()
        let day = Calendar.current.startOfDay(for: Date())

        try await db.upsertNutritionLog(on: day) { $0.waterOz = 96 }

        let loaded = try await db.nutritionLog(on: day)
        XCTAssertEqual(loaded?.waterOz, 96)
    }

    // MARK: - DailyLog upsert

    func testUpsertDailyLogCreatesRowThenUpdatesInPlace() async throws {
        let db = try AppDatabase.inMemory()
        let day = Calendar.current.startOfDay(for: Date())

        // First write inserts.
        try await db.upsertDailyLog(on: day) { $0.sleepQuality = 7 }
        let afterInsert = try await db.dailyLog(on: day)
        XCTAssertEqual(afterInsert?.sleepQuality, 7)
        XCTAssertNil(afterInsert?.notes)

        // Second write for the same date updates the same row.
        try await db.upsertDailyLog(on: day) { $0.notes = "solid morning" }
        let afterUpdate = try await db.dailyLog(on: day)
        XCTAssertEqual(afterUpdate?.id, afterInsert?.id, "should be the same row")
        XCTAssertEqual(afterUpdate?.sleepQuality, 7, "prior column preserved")
        XCTAssertEqual(afterUpdate?.notes, "solid morning")
    }

    // MARK: - BodyMetric manual weight

    func testUpsertTodaysManualWeightIgnoresHealthKitRows() async throws {
        let db = try AppDatabase.inMemory()
        let day = Calendar.current.startOfDay(for: Date())
        let noonToday = day.addingTimeInterval(12 * 3600)

        // Pre-existing HealthKit-source row at noon today — should be ignored.
        try await db.write { db in
            var hk = BodyMetric(timestamp: noonToday, source: .healthkit, weightLb: 999.0)
            try hk.insert(db)
        }

        // Manual write should insert (not overwrite the HK row).
        try await db.upsertTodaysManualWeight(184.6, on: day)

        let latestManual = try await db.todaysManualBodyMetric(on: day)
        XCTAssertEqual(latestManual?.weightLb, 184.6)
        XCTAssertEqual(latestManual?.source, .manual)

        // Second manual edit updates the same manual row, not a new one.
        try await db.upsertTodaysManualWeight(184.2, on: day)
        let manualCount = try await db.read { db in
            try BodyMetric
                .filter(Column("source") == BodyMetric.Source.manual.rawValue)
                .fetchCount(db)
        }
        XCTAssertEqual(manualCount, 1, "manual weight edits should upsert, not accumulate")

        let refreshed = try await db.todaysManualBodyMetric(on: day)
        XCTAssertEqual(refreshed?.weightLb, 184.2)
    }

    // MARK: - Anchor top sets + PR detection

    /// Helper: build a workout with one top set for `exercise`.
    private func addWorkout(
        db: AppDatabase,
        date: Date,
        exerciseId: Int64,
        topSet: (weightLb: Double, reps: Int)
    ) async throws {
        try await db.write { db in
            var w = Workout(date: date, sessionType: .push)
            try w.insert(db)

            var s = ExerciseSet(
                workoutId: w.id!,
                exerciseId: exerciseId,
                setNumber: 1,
                weightLb: topSet.weightLb,
                reps: topSet.reps,
                rir: 1,
                isTopSet: true,
                isWarmup: false
            )
            try s.insert(db)
        }
    }

    private func makeExercise(
        db: AppDatabase,
        name: String,
        category: Exercise.Category = .anchor
    ) async throws -> Int64 {
        try await db.write { db in
            var e = Exercise(
                name: name,
                category: category,
                primaryMuscleGroup: "chest",
                movementPattern: "push_horizontal",
                isBilateral: true,
                isCustom: false
            )
            try e.insert(db)
            return e.id!
        }
    }

    func testAnchorTopSetIsPRWhenNoPriorHistory() async throws {
        let db = try AppDatabase.inMemory()
        let today = Calendar.current.startOfDay(for: Date())

        let bench = try await makeExercise(db: db, name: "Bench Press")
        try await addWorkout(db: db, date: today, exerciseId: bench,
                             topSet: (weightLb: 225, reps: 5))

        let sets = try await db.anchorTopSets(on: today)
        XCTAssertEqual(sets.count, 1)
        XCTAssertEqual(sets[0].exerciseName, "Bench Press")
        XCTAssertEqual(sets[0].weightLb, 225)
        XCTAssertEqual(sets[0].reps, 5)
        XCTAssertTrue(sets[0].isPR, "first-ever top set should register as a PR")
    }

    func testAnchorTopSetIsPRWhenBeatingPriorE1RMAcrossRepRanges() async throws {
        let db = try AppDatabase.inMemory()
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let lastWeek = cal.date(byAdding: .day, value: -7, to: today)!

        let bench = try await makeExercise(db: db, name: "Bench Press")

        // Last week: 225 × 5 → e1RM = 225 × (1 + 5/30) = 262.5
        try await addWorkout(db: db, date: lastWeek, exerciseId: bench,
                             topSet: (weightLb: 225, reps: 5))

        // Today: 245 × 3 → e1RM = 245 × (1 + 3/30) = 269.5 → PR
        try await addWorkout(db: db, date: today, exerciseId: bench,
                             topSet: (weightLb: 245, reps: 3))

        let sets = try await db.anchorTopSets(on: today)
        XCTAssertEqual(sets.count, 1)
        XCTAssertTrue(sets[0].isPR,
                      "245×3 (e1RM ~269.5) should beat 225×5 (e1RM 262.5)")
    }

    func testAnchorTopSetIsNotPRWhenBelowPriorE1RM() async throws {
        let db = try AppDatabase.inMemory()
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let lastWeek = cal.date(byAdding: .day, value: -7, to: today)!

        let bench = try await makeExercise(db: db, name: "Bench Press")

        // Last week: 275 × 5 → e1RM = 320.83
        try await addWorkout(db: db, date: lastWeek, exerciseId: bench,
                             topSet: (weightLb: 275, reps: 5))

        // Today: 245 × 3 → e1RM = 269.5 → NOT a PR
        try await addWorkout(db: db, date: today, exerciseId: bench,
                             topSet: (weightLb: 245, reps: 3))

        let sets = try await db.anchorTopSets(on: today)
        XCTAssertEqual(sets.count, 1)
        XCTAssertFalse(sets[0].isPR)
    }

    func testAccessoryLiftsAreExcludedFromAnchorTopSets() async throws {
        let db = try AppDatabase.inMemory()
        let today = Calendar.current.startOfDay(for: Date())

        let accessory = try await makeExercise(
            db: db, name: "Lateral Raise", category: .accessory)
        try await addWorkout(db: db, date: today, exerciseId: accessory,
                             topSet: (weightLb: 25, reps: 12))

        let sets = try await db.anchorTopSets(on: today)
        XCTAssertTrue(sets.isEmpty,
                      "accessory-category exercises must not appear in anchor summary")
    }

    func testMultipleAnchorLiftsReturnedInInsertionOrder() async throws {
        let db = try AppDatabase.inMemory()
        let today = Calendar.current.startOfDay(for: Date())

        let bench = try await makeExercise(db: db, name: "Bench Press")
        let ohp   = try await makeExercise(db: db, name: "Overhead Press")

        try await addWorkout(db: db, date: today, exerciseId: bench,
                             topSet: (weightLb: 225, reps: 5))
        try await addWorkout(db: db, date: today, exerciseId: ohp,
                             topSet: (weightLb: 135, reps: 8))

        let sets = try await db.anchorTopSets(on: today)
        XCTAssertEqual(sets.map(\.exerciseName), ["Bench Press", "Overhead Press"])
    }

    // MARK: - Session summary

    func testTodaysSessionReturnsNilWhenNoWorkoutLogged() async throws {
        let db = try AppDatabase.inMemory()
        let session = try await db.todaysSession(on: Date())
        XCTAssertNil(session)
    }

    func testTodaysSessionSurfacesTypeAndDuration() async throws {
        let db = try AppDatabase.inMemory()
        let today = Calendar.current.startOfDay(for: Date())

        try await db.write { db in
            var w = Workout(date: today, sessionType: .pull, durationMin: 62)
            try w.insert(db)
        }

        let session = try await db.todaysSession(on: today)
        XCTAssertEqual(session?.sessionType, .pull)
        XCTAssertEqual(session?.durationMin, 62)
    }

    // MARK: - Epley

    func testEpleyMatchesKnownReferenceValues() {
        // Reference: 275 × 5 → 275 × (1 + 5/30) = 275 × 1.1667 ≈ 320.833
        XCTAssertEqual(epleyOneRepMax(weightLb: 275, reps: 5), 320.833, accuracy: 0.01)
        // 1RM at 1 rep is just the weight.
        XCTAssertEqual(epleyOneRepMax(weightLb: 315, reps: 1), 315 * (1 + 1.0/30.0), accuracy: 0.0001)
    }
}
