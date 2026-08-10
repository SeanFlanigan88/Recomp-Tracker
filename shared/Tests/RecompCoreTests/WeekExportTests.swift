import XCTest
import GRDB
@testable import RecompCore

final class WeekExportTests: XCTestCase {

    private let cal = Calendar.mondayFirst

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12, _ min: Int = 0) -> Date {
        var comps = DateComponents()
        comps.year = y; comps.month = m; comps.day = d
        comps.hour = h; comps.minute = min
        return cal.date(from: comps)!
    }

    // MARK: - Structural shape

    func testAssembleEmptyWeekProducesSevenDayShellsWhenCompleted() async throws {
        let db = try AppDatabase.inMemory()
        // "Today" = the following Monday, so the week is completed.
        let priorMon = date(2026, 8, 3)
        let now = date(2026, 8, 10, 8)
        let week = Week.containing(priorMon, now: now)

        let assembled = try await WeekExport.assemble(week: week, db: db, now: now)
        XCTAssertEqual(assembled.export.days.count, 7)
        XCTAssertEqual(assembled.export.days.map(\.weekday),
                       ["Monday", "Tuesday", "Wednesday", "Thursday",
                        "Friday", "Saturday", "Sunday"])
        XCTAssertEqual(assembled.export.exportVersion, 1)
        XCTAssertFalse(assembled.export.week.isPartial)
    }

    func testPartialWeekOnlyCoversMondayThroughToday() async throws {
        let db = try AppDatabase.inMemory()
        // "Today" = Wednesday of the current week → 3 days covered.
        let wed = date(2026, 8, 5, 14)
        let week = Week.containing(wed, now: wed)

        let assembled = try await WeekExport.assemble(week: week, db: db, now: wed)
        XCTAssertEqual(assembled.export.days.count, 3)
        XCTAssertEqual(assembled.export.days.map(\.weekday),
                       ["Monday", "Tuesday", "Wednesday"])
        XCTAssertTrue(assembled.export.week.isPartial)
    }

    // MARK: - Day-level assembly

    func testDailyLogAppearsOnCorrectDay() async throws {
        let db = try AppDatabase.inMemory()
        let wedDay = cal.startOfDay(for: date(2026, 8, 5))
        try await db.write { db in
            var log = DailyLog(
                date: wedDay,
                sleepQuality: 8,
                notes: "solid"
            )
            try log.insert(db)
        }
        let now = date(2026, 8, 10, 8)
        let week = Week.containing(date(2026, 8, 3), now: now)
        let assembled = try await WeekExport.assemble(week: week, db: db, now: now)

        let wed = assembled.export.days[2]
        XCTAssertEqual(wed.weekday, "Wednesday")
        XCTAssertEqual(wed.dailyLog?.sleepQuality1to10, 8)
        XCTAssertEqual(wed.dailyLog?.notes, "solid")

        let mon = assembled.export.days[0]
        XCTAssertNil(mon.dailyLog, "days without data get null dailyLog")
    }

    func testWorkoutSetsGroupedByExercise() async throws {
        let db = try AppDatabase.inMemory()
        let mon = cal.startOfDay(for: date(2026, 8, 3))
        try await db.write { db in
            var w = Workout(date: mon, sessionType: .push)
            try w.insert(db)

            var bench = Exercise(name: "Bench press", category: .anchor)
            try bench.insert(db)
            var incline = Exercise(name: "Incline DB")
            try incline.insert(db)

            var s1 = ExerciseSet(workoutId: w.id!, exerciseId: bench.id!,
                                 setNumber: 1, weightLb: 185, reps: 8, isTopSet: true)
            var s2 = ExerciseSet(workoutId: w.id!, exerciseId: bench.id!,
                                 setNumber: 2, weightLb: 185, reps: 7)
            var s3 = ExerciseSet(workoutId: w.id!, exerciseId: incline.id!,
                                 setNumber: 1, weightLb: 60, reps: 10)
            try s1.insert(db)
            try s2.insert(db)
            try s3.insert(db)
        }
        let now = date(2026, 8, 10, 8)
        let week = Week.containing(date(2026, 8, 3), now: now)
        let assembled = try await WeekExport.assemble(week: week, db: db, now: now)

        let monday = assembled.export.days[0]
        let workout = try XCTUnwrap(monday.workout)
        XCTAssertEqual(workout.exercises.count, 2)
        XCTAssertEqual(workout.exercises[0].name, "Bench press")
        XCTAssertEqual(workout.exercises[0].sets.count, 2)
        XCTAssertEqual(workout.exercises[0].sets[0].isTopSet, true)
        XCTAssertNotNil(workout.exercises[0].sets[0].e1rm, "e1RM computed for weighted reps")
        XCTAssertEqual(workout.exercises[1].name, "Incline DB")
    }

    // MARK: - Summary math

    func testWeightDeltaFromPriorWeekAnchor() async throws {
        let db = try AppDatabase.inMemory()
        try await db.write { db in
            // Prior week's Friday scale reading — this anchors weight_start.
            var prior = BodyMetric(
                timestamp: self.date(2026, 7, 31),
                source: .healthkit,
                weightLb: 182.4
            )
            try prior.insert(db)

            // End-of-week reading inside the covered window.
            var recent = BodyMetric(
                timestamp: self.date(2026, 8, 8),
                source: .healthkit,
                weightLb: 180.9
            )
            try recent.insert(db)
        }
        let now = date(2026, 8, 10, 8)
        let week = Week.containing(date(2026, 8, 3), now: now)
        let assembled = try await WeekExport.assemble(week: week, db: db, now: now)

        XCTAssertEqual(assembled.export.summary.weightStartLb, 182.4)
        XCTAssertEqual(assembled.export.summary.weightEndLb, 180.9)
        XCTAssertEqual(assembled.export.summary.weightDeltaLb ?? 0, -1.5, accuracy: 0.001)
    }

    func testAveragesIgnoreNullValues() async throws {
        let db = try AppDatabase.inMemory()
        let monDay = cal.startOfDay(for: date(2026, 8, 3))
        let wedDay = cal.startOfDay(for: date(2026, 8, 5))
        try await db.write { db in
            // Two sleep readings, one day without a log.
            var l1 = DailyLog(date: monDay, sleepQuality: 6)
            var l2 = DailyLog(date: wedDay, sleepQuality: 8)
            try l1.insert(db)
            try l2.insert(db)
        }
        let now = date(2026, 8, 10, 8)
        let week = Week.containing(date(2026, 8, 3), now: now)
        let assembled = try await WeekExport.assemble(week: week, db: db, now: now)

        XCTAssertEqual(assembled.export.summary.avgSleepQuality ?? 0, 7.0, accuracy: 0.001)
    }

    func testWorkoutsCompletedCountsRowsInRange() async throws {
        let db = try AppDatabase.inMemory()
        let workoutDays = [3, 5, 7].map { cal.startOfDay(for: date(2026, 8, $0)) }
        try await db.write { db in
            for day in workoutDays {
                var w = Workout(date: day)
                try w.insert(db)
            }
        }
        let now = date(2026, 8, 10, 8)
        let week = Week.containing(date(2026, 8, 3), now: now)
        let assembled = try await WeekExport.assemble(week: week, db: db, now: now)
        XCTAssertEqual(assembled.export.summary.workoutsCompleted, 3)
    }

    // MARK: - Photos

    func testPhotoFilenameEncodesTimestampAndTags() async throws {
        let db = try AppDatabase.inMemory()
        let ts = date(2026, 8, 3, 8, 15)
        try await db.insertProgressPhoto(
            ProgressPhoto(
                date: cal.startOfDay(for: ts),
                timestamp: ts,
                angle: .front,
                pose: .relaxed,
                photoPath: "progress_photos/abc.heic",
                cadenceTag: .weekly
            )
        )
        let now = date(2026, 8, 10, 8)
        let week = Week.containing(date(2026, 8, 3), now: now)
        let assembled = try await WeekExport.assemble(week: week, db: db, now: now)

        let photo = try XCTUnwrap(assembled.export.days[0].photos.first)
        XCTAssertTrue(photo.fileName.hasPrefix("2026-08-03_"))
        XCTAssertTrue(photo.fileName.contains("_front_relaxed"))
        XCTAssertTrue(photo.fileName.hasSuffix(".heic"))
        XCTAssertEqual(assembled.photoCopyPlan.count, 1)
        XCTAssertEqual(
            assembled.photoCopyPlan[0].sourceRelativePath,
            "progress_photos/abc.heic"
        )
        XCTAssertEqual(
            assembled.photoCopyPlan[0].destinationFileName,
            photo.fileName
        )
    }

    // MARK: - Cycle metadata

    func testCycleWeekNumberComputedFromCycleStart() async throws {
        // Cycle 2 starts Aug 3 2026. Week containing Aug 10 is week 2.
        let db = try AppDatabase.inMemory()
        let now = date(2026, 8, 17)
        let week = Week.containing(date(2026, 8, 10), now: now)
        let assembled = try await WeekExport.assemble(week: week, db: db, now: now)
        XCTAssertEqual(assembled.export.week.cycle, "Cycle 2")
        XCTAssertEqual(assembled.export.week.weekNumberInCycle, 2)
    }

    func testWeekBeforeCycleStartHasNilWeekNumber() async throws {
        let db = try AppDatabase.inMemory()
        let now = date(2026, 7, 28)
        let week = Week.containing(date(2026, 7, 20), now: now)
        let assembled = try await WeekExport.assemble(week: week, db: db, now: now)
        XCTAssertNil(assembled.export.week.weekNumberInCycle,
                     "cycle hadn't started yet")
        XCTAssertNil(assembled.export.week.cycle,
                     "cycle name should also be absent when week predates the cycle")
    }
}
