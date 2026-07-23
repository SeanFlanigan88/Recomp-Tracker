import XCTest
import GRDB
@testable import RecompCore

/// Sanity check for the whole data stack.
///
/// If this test passes, we know:
///  - `Package.swift` resolves GRDB and builds RecompCore
///  - `AppMigrator` runs M001 cleanly
///  - Every model's `Codable` / `CodingKeys` mapping round-trips through SQLite
///  - FK relationships between `exercise_sets`, `workouts`, and `exercises` work
///
/// When we add CI, this is the first test to run.
final class DatabaseIntegrationTests: XCTestCase {

    // MARK: - Migrations

    func testMigrationsCreateAllExpectedTables() async throws {
        let db = try AppDatabase.inMemory()

        let tables = try await db.read { db in
            try String.fetchAll(
                db,
                sql: """
                    SELECT name FROM sqlite_master
                    WHERE type = 'table'
                      AND name NOT LIKE 'sqlite_%'
                      AND name NOT LIKE 'grdb_%'
                    ORDER BY name
                    """
            )
        }

        let expected: Set<String> = [
            "body_metrics",
            "check_ins",
            "daily_log",
            "exercise_sets",
            "exercises",
            "nutrition_log",
            "progress_photos",
            "workouts",
        ]

        XCTAssertEqual(Set(tables), expected)
    }

    // MARK: - Round-trip

    /// Insert one row of every type, read them all back, and verify the values
    /// that flow through GRDB's `Codable` machinery (including snake_case
    /// `CodingKeys`, enum rawValues, and Bool defaults) survive intact.
    func testInsertAndReadOneRowOfEachType() async throws {
        let db = try AppDatabase.inMemory()

        let now = Date()

        // 1. body_metrics
        let insertedMetric = try await db.write { db -> BodyMetric in
            var m = BodyMetric(
                timestamp: now,
                source: .manual,
                weightLb: 180.5,
                bodyFatPct: 18.2,
                leanMassLb: 147.6,
                restingHr: 54,
                hrvMs: 62.0,
                sleepHours: 7.4,
                sleepEfficiency: 0.91
            )
            try m.insert(db)
            return m
        }
        XCTAssertNotNil(insertedMetric.id)

        // 2. daily_log
        let insertedLog = try await db.write { db -> DailyLog in
            var l = DailyLog(
                date: now,
                energy: 8,
                mood: "good",
                sleepQuality: 7,
                stress: 3,
                notes: "solid morning",
                trainingReadiness: 0.82
            )
            try l.insert(db)
            return l
        }
        XCTAssertNotNil(insertedLog.id)

        // 3. exercises (parent for exercise_sets FK)
        let insertedExercise = try await db.write { db -> Exercise in
            var e = Exercise(
                name: "Bench Press",
                category: .anchor,
                primaryMuscleGroup: "chest",
                movementPattern: "push_horizontal",
                isBilateral: true,
                isCustom: false
            )
            try e.insert(db)
            return e
        }
        XCTAssertNotNil(insertedExercise.id)

        // 4. workouts (parent for exercise_sets FK)
        let insertedWorkout = try await db.write { db -> Workout in
            var w = Workout(
                date: now,
                startedAt: now,
                endedAt: now.addingTimeInterval(3600),
                sessionType: .push,
                durationMin: 60,
                activeKcal: 320,
                avgHr: 128,
                notes: "cycle 2 day 1"
            )
            try w.insert(db)
            return w
        }
        XCTAssertNotNil(insertedWorkout.id)

        // 5. exercise_sets (FKs to workouts + exercises)
        let workoutId = try XCTUnwrap(insertedWorkout.id)
        let exerciseId = try XCTUnwrap(insertedExercise.id)
        let insertedSet = try await db.write { db -> ExerciseSet in
            var s = ExerciseSet(
                workoutId: workoutId,
                exerciseId: exerciseId,
                setNumber: 1,
                weightLb: 185.0,
                reps: 8,
                rir: 2,
                isTopSet: true,
                isWarmup: false,
                notes: "felt strong"
            )
            try s.insert(db)
            return s
        }
        XCTAssertNotNil(insertedSet.id)

        // 6. nutrition_log
        let insertedNutrition = try await db.write { db -> NutritionLog in
            var n = NutritionLog(
                date: now,
                kcal: 2400,
                proteinG: 180,
                carbsG: 260,
                fatG: 70,
                targetKcal: 2400,
                targetProteinG: 180,
                notes: "hit targets"
            )
            try n.insert(db)
            return n
        }
        XCTAssertNotNil(insertedNutrition.id)

        // 7. progress_photos
        let insertedPhoto = try await db.write { db -> ProgressPhoto in
            var p = ProgressPhoto(
                date: now,
                timestamp: now,
                angle: .sideLeft,
                pose: .relaxed,
                photoPath: "photos/2026-08-03_side_left_relaxed.jpg",
                weightLbAtCapture: 180.5,
                bfPctAtCapture: 18.2,
                cadenceTag: .weekly,
                notes: nil
            )
            try p.insert(db)
            return p
        }
        XCTAssertNotNil(insertedPhoto.id)

        // 8. check_ins
        let insertedCheckIn = try await db.write { db -> CheckIn in
            var c = CheckIn(
                date: now,
                periodType: .weekly,
                periodStart: now.addingTimeInterval(-7 * 24 * 3600),
                periodEnd: now,
                avgWeightLb: 180.7,
                avgBodyFatPct: 18.3,
                avgSleepHours: 7.3,
                workoutsCompleted: 4,
                totalVolumeLb: 42_500,
                reflectionNotes: "week 1 baseline",
                coachNotes: "adjust volume next week"
            )
            try c.insert(db)
            return c
        }
        XCTAssertNotNil(insertedCheckIn.id)

        // ---- Read back and compare ----

        let readMetrics: [BodyMetric] = try await db.read { db in
            try BodyMetric.fetchAll(db)
        }
        XCTAssertEqual(readMetrics.count, 1)
        let readMetric = try XCTUnwrap(readMetrics.first)
        XCTAssertEqual(readMetric.source, .manual)
        XCTAssertEqual(readMetric.weightLb, 180.5)
        XCTAssertEqual(readMetric.sleepEfficiency, 0.91)

        let readLogs: [DailyLog] = try await db.read { db in
            try DailyLog.fetchAll(db)
        }
        XCTAssertEqual(readLogs.count, 1)
        let readLog = try XCTUnwrap(readLogs.first)
        XCTAssertEqual(readLog.energy, 8)
        XCTAssertEqual(readLog.sleepQuality, 7)
        XCTAssertEqual(readLog.trainingReadiness, 0.82)

        let readExercises: [Exercise] = try await db.read { db in
            try Exercise.fetchAll(db)
        }
        XCTAssertEqual(readExercises.count, 1)
        let readExercise = try XCTUnwrap(readExercises.first)
        XCTAssertEqual(readExercise.category, .anchor)
        XCTAssertEqual(readExercise.isBilateral, true)
        XCTAssertEqual(readExercise.isCustom, false)

        let readWorkouts: [Workout] = try await db.read { db in
            try Workout.fetchAll(db)
        }
        XCTAssertEqual(readWorkouts.count, 1)
        let readWorkout = try XCTUnwrap(readWorkouts.first)
        XCTAssertEqual(readWorkout.sessionType, .push)
        XCTAssertEqual(readWorkout.durationMin, 60)

        let readSets: [ExerciseSet] = try await db.read { db in
            try ExerciseSet.fetchAll(db)
        }
        XCTAssertEqual(readSets.count, 1)
        let readSet = try XCTUnwrap(readSets.first)
        XCTAssertEqual(readSet.workoutId, workoutId)
        XCTAssertEqual(readSet.exerciseId, exerciseId)
        XCTAssertEqual(readSet.reps, 8)
        XCTAssertEqual(readSet.rir, 2)
        XCTAssertEqual(readSet.isTopSet, true)
        XCTAssertEqual(readSet.isWarmup, false)

        let readNutrition: [NutritionLog] = try await db.read { db in
            try NutritionLog.fetchAll(db)
        }
        XCTAssertEqual(readNutrition.count, 1)
        let readNutritionRow = try XCTUnwrap(readNutrition.first)
        XCTAssertEqual(readNutritionRow.kcal, 2400)
        XCTAssertEqual(readNutritionRow.proteinG, 180)

        let readPhotos: [ProgressPhoto] = try await db.read { db in
            try ProgressPhoto.fetchAll(db)
        }
        XCTAssertEqual(readPhotos.count, 1)
        let readPhoto = try XCTUnwrap(readPhotos.first)
        XCTAssertEqual(readPhoto.angle, .sideLeft)
        XCTAssertEqual(readPhoto.pose, .relaxed)
        XCTAssertEqual(readPhoto.cadenceTag, .weekly)

        let readCheckIns: [CheckIn] = try await db.read { db in
            try CheckIn.fetchAll(db)
        }
        XCTAssertEqual(readCheckIns.count, 1)
        let readCheckIn = try XCTUnwrap(readCheckIns.first)
        XCTAssertEqual(readCheckIn.periodType, .weekly)
        XCTAssertEqual(readCheckIn.workoutsCompleted, 4)
        XCTAssertEqual(readCheckIn.totalVolumeLb, 42_500)
    }

    // MARK: - FK enforcement

    /// Inserting a set that references a non-existent workout should fail.
    /// Guards against regressions where FK enforcement gets turned off silently.
    func testForeignKeyConstraintOnExerciseSets() async throws {
        let db = try AppDatabase.inMemory()

        // Seed a valid exercise so only the workout FK is bad.
        let exerciseId = try await db.write { db -> Int64 in
            var e = Exercise(name: "Squat", category: .anchor)
            try e.insert(db)
            return e.id!
        }

        do {
            _ = try await db.write { db -> ExerciseSet in
                var s = ExerciseSet(
                    workoutId: 999_999, // does not exist
                    exerciseId: exerciseId,
                    setNumber: 1,
                    weightLb: 225.0,
                    reps: 5
                )
                try s.insert(db)
                return s
            }
            XCTFail("Expected FK violation, but insert succeeded")
        } catch {
            // Expected — GRDB surfaces a DatabaseError with the FK violation.
        }
    }

    /// Deleting a workout should cascade to its sets.
    func testDeletingWorkoutCascadesToSets() async throws {
        let db = try AppDatabase.inMemory()

        let (workoutId, _) = try await db.write { db -> (Int64, Int64) in
            var e = Exercise(name: "Deadlift", category: .anchor)
            try e.insert(db)
            var w = Workout(date: Date(), sessionType: .pull)
            try w.insert(db)
            var s = ExerciseSet(
                workoutId: w.id!,
                exerciseId: e.id!,
                setNumber: 1,
                weightLb: 315.0,
                reps: 5
            )
            try s.insert(db)
            return (w.id!, e.id!)
        }

        try await db.write { db in
            _ = try Workout.deleteOne(db, key: workoutId)
        }

        let remainingSets: Int = try await db.read { db in
            try ExerciseSet.fetchCount(db)
        }
        XCTAssertEqual(remainingSets, 0, "Cascade delete should have removed the set")
    }
}
