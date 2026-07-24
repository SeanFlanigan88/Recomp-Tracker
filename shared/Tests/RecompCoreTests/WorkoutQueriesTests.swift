import XCTest
import GRDB
@testable import RecompCore

final class ProgramTests: XCTestCase {

    // MARK: - Weekday mapping

    func testWeekdayFromDateMatchesCalendar() {
        // 2026-08-03 is a Monday.
        let comps = DateComponents(year: 2026, month: 8, day: 3)
        let date = Calendar(identifier: .gregorian).date(from: comps)!
        XCTAssertEqual(Weekday.from(date: date, calendar: Calendar(identifier: .gregorian)), .monday)
    }

    // MARK: - Cycle 2 shape

    func testCycle2DefinesAllSevenDays() {
        for day in Weekday.allCases {
            XCTAssertNotNil(Program.cycle2.days[day], "cycle 2 should define \(day)")
        }
    }

    func testCycle2AnchorsMatchProgramDefinition() {
        // The four cycle-2 anchor lifts per the source HTML.
        let expectedAnchorNames: Set<String> = [
            "Barbell bench press",
            "Lat pulldown / weighted pull-up",
            "Barbell back squat",
            "RDL / Deadlift (alternate weekly)",
        ]
        let anchors = Program.cycle2.days.values
            .flatMap(\.exercises)
            .filter(\.isAnchor)
            .map(\.name)
        XCTAssertEqual(Set(anchors), expectedAnchorNames)
    }

    func testCycle2AnchorsMapToAnchorCategory() {
        let anchors = Program.cycle2.days.values
            .flatMap(\.exercises)
            .filter(\.isAnchor)
        XCTAssertFalse(anchors.isEmpty)
        for a in anchors {
            XCTAssertEqual(a.category, .anchor, "\(a.name) should map to .anchor")
        }
    }

    func testCycle2MondayIsPushWithBenchAnchor() {
        let mon = Program.cycle2.days[.monday]
        XCTAssertEqual(mon?.name, "Push")
        XCTAssertEqual(mon?.sessionType, .push)
        XCTAssertEqual(mon?.exercises.count, 7)
        XCTAssertEqual(mon?.exercises.first?.id, "bench")
        XCTAssertEqual(mon?.exercises.first?.isAnchor, true)
    }

    func testCycle2TuesdayIsCardioOnly() {
        let tue = Program.cycle2.days[.tuesday]
        XCTAssertEqual(tue?.sessionType, .cardio)
        XCTAssertTrue(tue?.exercises.isEmpty ?? false, "Tuesday should have no lifts")
        XCTAssertNotNil(tue?.cardioNote)
        XCTAssertFalse(tue?.isRest ?? true)
    }

    func testCycle2SaturdayIsHybrid() {
        let sat = Program.cycle2.days[.saturday]
        XCTAssertNotNil(sat?.cardioNote, "Saturday should have a cardio note")
        XCTAssertFalse(sat?.exercises.isEmpty ?? true, "Saturday should also have accessory lifts")
    }

    func testCycle2SundayIsRest() {
        let sun = Program.cycle2.days[.sunday]
        XCTAssertTrue(sun?.isRest ?? false)
        XCTAssertNil(sun?.sessionType)
        XCTAssertNotNil(sun?.restNote)
    }
}

final class WorkoutQueriesTests: XCTestCase {

    // MARK: - Exercise get-or-create

    func testGetOrCreateExerciseIsIdempotent() async throws {
        let db = try AppDatabase.inMemory()

        let firstId = try await db.getOrCreateExercise(name: "Bench Press", category: .anchor)
        let secondId = try await db.getOrCreateExercise(name: "Bench Press", category: .anchor)
        XCTAssertEqual(firstId, secondId)

        let count = try await db.read { db in
            try Exercise.filter(Column("name") == "Bench Press").fetchCount(db)
        }
        XCTAssertEqual(count, 1, "second call must not create a duplicate row")
    }

    func testGetOrCreateExerciseBackfillsMissingCategory() async throws {
        let db = try AppDatabase.inMemory()

        // Pre-existing row with nil category (e.g. from an old import).
        let id = try await db.write { db -> Int64 in
            var e = Exercise(name: "Foo Press", category: nil)
            try e.insert(db)
            return e.id!
        }

        let returnedId = try await db.getOrCreateExercise(name: "Foo Press", category: .accessory)
        XCTAssertEqual(returnedId, id)

        let refreshed = try await db.read { db in
            try Exercise.fetchOne(db, key: id)
        }
        XCTAssertEqual(refreshed?.category, .accessory)
    }

    // MARK: - Workout get-or-create

    func testGetOrCreateWorkoutIsPerDay() async throws {
        let db = try AppDatabase.inMemory()
        let today = Calendar.current.startOfDay(for: Date())

        let firstId = try await db.getOrCreateWorkout(on: today, sessionType: .push)
        let secondId = try await db.getOrCreateWorkout(on: today, sessionType: .push)
        XCTAssertEqual(firstId, secondId)

        let count = try await db.read { db in
            try Workout.fetchCount(db)
        }
        XCTAssertEqual(count, 1)
    }

    func testGetOrCreateWorkoutDoesNotOverwriteSessionTypeOnRepeatCall() async throws {
        let db = try AppDatabase.inMemory()
        let today = Calendar.current.startOfDay(for: Date())

        _ = try await db.getOrCreateWorkout(on: today, sessionType: .push)
        _ = try await db.getOrCreateWorkout(on: today, sessionType: .cardio) // should be ignored

        let stored = try await db.workout(on: today)
        XCTAssertEqual(stored?.sessionType, .push)
    }

    // MARK: - Set upsert + top set recompute

    private func seedExercise(_ db: AppDatabase, name: String = "Bench") async throws -> Int64 {
        try await db.getOrCreateExercise(name: name, category: .anchor)
    }

    func testUpsertSetInsertsThenUpdatesSameRow() async throws {
        let db = try AppDatabase.inMemory()
        let today = Calendar.current.startOfDay(for: Date())
        let wid = try await db.getOrCreateWorkout(on: today, sessionType: .push)
        let eid = try await seedExercise(db)

        try await db.upsertSet(workoutId: wid, exerciseId: eid, setNumber: 1, weightLb: 225, reps: 5)
        try await db.upsertSet(workoutId: wid, exerciseId: eid, setNumber: 1, weightLb: 230, reps: 5)

        let sets = try await db.sets(workoutId: wid, exerciseId: eid)
        XCTAssertEqual(sets.count, 1, "same (workout, exercise, setNumber) must upsert, not accumulate")
        XCTAssertEqual(sets.first?.weightLb, 230)
    }

    func testTopSetRecomputedByEpleyE1RMAcrossSets() async throws {
        let db = try AppDatabase.inMemory()
        let today = Calendar.current.startOfDay(for: Date())
        let wid = try await db.getOrCreateWorkout(on: today, sessionType: .push)
        let eid = try await seedExercise(db)

        // 225×5 → e1RM 262.5
        // 245×3 → e1RM 269.5   ← top
        // 205×8 → e1RM 259.7
        try await db.upsertSet(workoutId: wid, exerciseId: eid, setNumber: 1, weightLb: 225, reps: 5)
        try await db.upsertSet(workoutId: wid, exerciseId: eid, setNumber: 2, weightLb: 245, reps: 3)
        try await db.upsertSet(workoutId: wid, exerciseId: eid, setNumber: 3, weightLb: 205, reps: 8)

        let sets = try await db.sets(workoutId: wid, exerciseId: eid)
        let topSetNumbers = sets.filter(\.isTopSet).map(\.setNumber)
        XCTAssertEqual(topSetNumbers, [2], "245×3 should be the sole top set")
    }

    func testTopSetTieBrokenByEarliestSetNumber() async throws {
        let db = try AppDatabase.inMemory()
        let today = Calendar.current.startOfDay(for: Date())
        let wid = try await db.getOrCreateWorkout(on: today, sessionType: .push)
        let eid = try await seedExercise(db)

        // Identical weight × reps → identical e1RM. Convention: earliest set
        // number wins so the flag is deterministic.
        try await db.upsertSet(workoutId: wid, exerciseId: eid, setNumber: 1, weightLb: 225, reps: 5)
        try await db.upsertSet(workoutId: wid, exerciseId: eid, setNumber: 2, weightLb: 225, reps: 5)

        let sets = try await db.sets(workoutId: wid, exerciseId: eid)
        XCTAssertEqual(sets.filter(\.isTopSet).map(\.setNumber), [1])
    }

    func testTopSetFlagMigratesWhenLaterSetSurpasses() async throws {
        let db = try AppDatabase.inMemory()
        let today = Calendar.current.startOfDay(for: Date())
        let wid = try await db.getOrCreateWorkout(on: today, sessionType: .push)
        let eid = try await seedExercise(db)

        try await db.upsertSet(workoutId: wid, exerciseId: eid, setNumber: 1, weightLb: 225, reps: 5)
        var sets = try await db.sets(workoutId: wid, exerciseId: eid)
        XCTAssertEqual(sets.filter(\.isTopSet).map(\.setNumber), [1])

        try await db.upsertSet(workoutId: wid, exerciseId: eid, setNumber: 2, weightLb: 250, reps: 5)
        sets = try await db.sets(workoutId: wid, exerciseId: eid)
        XCTAssertEqual(sets.filter(\.isTopSet).map(\.setNumber), [2],
                       "top-set flag must migrate off set 1 when set 2 beats it")
        XCTAssertEqual(sets.filter { !$0.isTopSet }.map(\.setNumber), [1])
    }

    func testSetsWithMissingWeightOrRepsAreIgnoredForTopSet() async throws {
        let db = try AppDatabase.inMemory()
        let today = Calendar.current.startOfDay(for: Date())
        let wid = try await db.getOrCreateWorkout(on: today, sessionType: .push)
        let eid = try await seedExercise(db)

        try await db.upsertSet(workoutId: wid, exerciseId: eid, setNumber: 1, weightLb: nil, reps: 5)
        try await db.upsertSet(workoutId: wid, exerciseId: eid, setNumber: 2, weightLb: 100, reps: nil)
        try await db.upsertSet(workoutId: wid, exerciseId: eid, setNumber: 3, weightLb: 200, reps: 3)

        let sets = try await db.sets(workoutId: wid, exerciseId: eid)
        XCTAssertEqual(sets.filter(\.isTopSet).map(\.setNumber), [3])
    }

    // MARK: - Snapshot

    func testWorkoutDaySnapshotReturnsNilWorkoutWhenNothingLogged() async throws {
        let db = try AppDatabase.inMemory()
        let snapshot = try await db.workoutDaySnapshot(on: Date())
        XCTAssertNil(snapshot.workout)
        XCTAssertTrue(snapshot.setsByExerciseId.isEmpty)
    }

    func testWorkoutDaySnapshotGroupsSetsByExercise() async throws {
        let db = try AppDatabase.inMemory()
        let today = Calendar.current.startOfDay(for: Date())
        let wid = try await db.getOrCreateWorkout(on: today, sessionType: .pull)
        let benchId = try await db.getOrCreateExercise(name: "Bench", category: .anchor)
        let rowId = try await db.getOrCreateExercise(name: "Row", category: .accessory)

        try await db.upsertSet(workoutId: wid, exerciseId: benchId, setNumber: 1, weightLb: 225, reps: 5)
        try await db.upsertSet(workoutId: wid, exerciseId: benchId, setNumber: 2, weightLb: 235, reps: 3)
        try await db.upsertSet(workoutId: wid, exerciseId: rowId,   setNumber: 1, weightLb: 185, reps: 8)

        let snapshot = try await db.workoutDaySnapshot(on: today)
        XCTAssertNotNil(snapshot.workout)
        XCTAssertEqual(snapshot.setsByExerciseId[benchId]?.count, 2)
        XCTAssertEqual(snapshot.setsByExerciseId[rowId]?.count, 1)
        XCTAssertEqual(snapshot.setsByExerciseId[benchId]?.map(\.setNumber), [1, 2],
                       "sets should be in set_number order")
    }

    // MARK: - Workout-level fields

    func testUpdateWorkoutFieldsCreatesAndUpdates() async throws {
        let db = try AppDatabase.inMemory()
        let today = Calendar.current.startOfDay(for: Date())

        try await db.updateWorkoutFields(
            on: today,
            sessionType: .cardio,
            durationMin: 40,
            avgHr: 138,
            notes: "Zone 2 walk"
        )

        let w = try await db.workout(on: today)
        XCTAssertEqual(w?.sessionType, .cardio)
        XCTAssertEqual(w?.durationMin, 40)
        XCTAssertEqual(w?.avgHr, 138)
        XCTAssertEqual(w?.notes, "Zone 2 walk")

        // Second call updates one field, leaves others alone.
        try await db.updateWorkoutFields(on: today, sessionType: .cardio, durationMin: 45)
        let w2 = try await db.workout(on: today)
        XCTAssertEqual(w2?.durationMin, 45)
        XCTAssertEqual(w2?.avgHr, 138, "avgHr should be untouched by a duration-only update")
        XCTAssertEqual(w2?.notes, "Zone 2 walk")
    }

    func testUpdateWorkoutFieldsClearsNotesExplicitly() async throws {
        let db = try AppDatabase.inMemory()
        let today = Calendar.current.startOfDay(for: Date())

        try await db.updateWorkoutFields(on: today, sessionType: .push, notes: "form was rough")
        let afterWrite = try await db.workout(on: today)
        XCTAssertEqual(afterWrite?.notes, "form was rough")

        try await db.updateWorkoutFields(on: today, sessionType: .push, clearNotes: true)
        let afterClear = try await db.workout(on: today)
        XCTAssertNil(afterClear?.notes)
    }
}
