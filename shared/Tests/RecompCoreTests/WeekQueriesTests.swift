import XCTest
import GRDB
@testable import RecompCore

final class WeekQueriesTests: XCTestCase {

    private let cal = Calendar.mondayFirst

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
        var comps = DateComponents()
        comps.year = y; comps.month = m; comps.day = d; comps.hour = h
        return cal.date(from: comps)!
    }

    // MARK: - bodyMetrics range

    func testBodyMetricsFiltersToRange() async throws {
        let db = try AppDatabase.inMemory()
        let mon = date(2026, 8, 3)
        let wed = date(2026, 8, 5)
        let priorSun = date(2026, 8, 2)

        try await insertMetric(db, timestamp: priorSun, weight: 180.0)
        try await insertMetric(db, timestamp: mon, weight: 181.0)
        try await insertMetric(db, timestamp: wed, weight: 179.5)

        let results = try await db.bodyMetrics(from: mon, through: wed)
        XCTAssertEqual(results.map(\.weightLb), [181.0, 179.5])
    }

    func testBodyMetricsOrderedAscendingByTimestamp() async throws {
        let db = try AppDatabase.inMemory()
        try await insertMetric(db, timestamp: date(2026, 8, 5), weight: 179.5)
        try await insertMetric(db, timestamp: date(2026, 8, 3), weight: 181.0)

        let results = try await db.bodyMetrics(
            from: date(2026, 8, 3),
            through: date(2026, 8, 9)
        )
        XCTAssertEqual(results.map(\.weightLb), [181.0, 179.5])
    }

    // MARK: - latestWeightBefore

    func testLatestWeightBeforeReturnsNearestPrior() async throws {
        let db = try AppDatabase.inMemory()
        let mon = date(2026, 8, 3)
        try await insertMetric(db, timestamp: date(2026, 7, 27), weight: 182.0)
        try await insertMetric(db, timestamp: date(2026, 7, 30), weight: 181.5)
        try await insertMetric(db, timestamp: mon, weight: 181.0)

        let prior = try await db.latestWeightBefore(mon)
        XCTAssertEqual(prior?.weightLb, 181.5, "the Monday-of-week reading itself is excluded")
    }

    func testLatestWeightBeforeIgnoresRowsWithNullWeight() async throws {
        let db = try AppDatabase.inMemory()
        let mon = date(2026, 8, 3)
        try await insertMetric(db, timestamp: date(2026, 8, 1), weight: nil, bodyFat: 18.0)
        try await insertMetric(db, timestamp: date(2026, 7, 30), weight: 181.0)

        let prior = try await db.latestWeightBefore(mon)
        XCTAssertEqual(prior?.weightLb, 181.0)
    }

    // MARK: - workouts / sets

    func testWorkoutsRangeAndSetsBulkFetch() async throws {
        let db = try AppDatabase.inMemory()
        let monDay = cal.startOfDay(for: date(2026, 8, 3))
        let wedDay = cal.startOfDay(for: date(2026, 8, 5))
        try await db.write { db in
            var w1 = Workout(date: monDay, sessionType: .push)
            try w1.insert(db)
            var w2 = Workout(date: wedDay, sessionType: .legs)
            try w2.insert(db)

            var ex = Exercise(name: "Bench")
            try ex.insert(db)

            var s1 = ExerciseSet(workoutId: w1.id!, exerciseId: ex.id!, setNumber: 1,
                                 weightLb: 185, reps: 8, isTopSet: true)
            try s1.insert(db)
            var s2 = ExerciseSet(workoutId: w2.id!, exerciseId: ex.id!, setNumber: 1,
                                 weightLb: 225, reps: 5, isTopSet: true)
            try s2.insert(db)
        }

        let workouts = try await db.workouts(
            from: date(2026, 8, 3),
            through: date(2026, 8, 9)
        )
        XCTAssertEqual(workouts.count, 2)

        let sets = try await db.sets(forWorkoutIds: workouts.compactMap(\.id))
        XCTAssertEqual(sets.count, 2)
    }

    func testSetsForEmptyWorkoutIdsReturnsEmpty() async throws {
        let db = try AppDatabase.inMemory()
        let sets = try await db.sets(forWorkoutIds: [])
        XCTAssertTrue(sets.isEmpty)
    }

    // MARK: - Helpers

    private func insertMetric(
        _ db: AppDatabase,
        timestamp: Date,
        weight: Double? = nil,
        bodyFat: Double? = nil
    ) async throws {
        try await db.write { db in
            var m = BodyMetric(
                timestamp: timestamp,
                source: .manual,
                weightLb: weight,
                bodyFatPct: bodyFat
            )
            try m.insert(db)
        }
    }
}
