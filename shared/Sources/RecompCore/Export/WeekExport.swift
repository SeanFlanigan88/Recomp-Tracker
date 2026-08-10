import Foundation

// MARK: - Top-level export

/// The full weekly export payload, serialized to `week.json` in the export
/// folder. Bumped in lockstep with `exportVersion` when the shape changes;
/// the agent can key off it to know which fields to expect.
public struct WeekExport: Codable, Sendable, Equatable {

    public let exportVersion: Int
    public let generatedAt: Date
    public let week: WeekInfo
    public let summary: Summary
    public let days: [DayExport]

    public struct WeekInfo: Codable, Sendable, Equatable {
        public let startDate: Date
        public let endDate: Date
        public let isPartial: Bool
        public let cycle: String?
        public let weekNumberInCycle: Int?
    }

    public struct Summary: Codable, Sendable, Equatable {
        public let workoutsCompleted: Int
        public let avgSleepQuality: Double?
        public let weightStartLb: Double?
        public let weightEndLb: Double?
        public let weightDeltaLb: Double?
        public let avgCalories: Double?
        public let avgWaterOz: Double?
        public let photosCount: Int
    }

    public struct DayExport: Codable, Sendable, Equatable {
        public let date: Date
        public let weekday: String
        public let programDay: String?
        public let dailyLog: DailyLogExport?
        public let nutrition: NutritionExport?
        public let bodyMetrics: [BodyMetricExport]
        public let workout: WorkoutExport?
        public let photos: [PhotoExport]
    }

    public struct DailyLogExport: Codable, Sendable, Equatable {
        public let sleepQuality1to10: Int?
        public let notes: String?
    }

    public struct NutritionExport: Codable, Sendable, Equatable {
        public let kcal: Int?
        public let waterOz: Int?
    }

    public struct BodyMetricExport: Codable, Sendable, Equatable {
        public let timestamp: Date
        public let source: String
        public let weightLb: Double?
        public let bodyFatPct: Double?
        public let leanMassLb: Double?
        public let hrvMs: Double?
        public let restingHr: Int?
    }

    public struct WorkoutExport: Codable, Sendable, Equatable {
        public let sessionType: String?
        public let durationMin: Int?
        public let activeKcal: Int?
        public let avgHr: Int?
        public let notes: String?
        public let exercises: [ExerciseGrouping]
    }

    public struct ExerciseGrouping: Codable, Sendable, Equatable {
        public let name: String
        public let isAnchor: Bool
        public let sets: [SetExport]
    }

    public struct SetExport: Codable, Sendable, Equatable {
        public let setNumber: Int
        public let reps: Int?
        public let weightLb: Double?
        public let rir: Int?
        public let isWarmup: Bool
        public let isTopSet: Bool
        public let e1rm: Double?
        public let notes: String?
    }

    public struct PhotoExport: Codable, Sendable, Equatable {
        public let timestamp: Date
        public let angle: String
        public let pose: String
        public let cadence: String?
        public let weightLbAtCapture: Double?
        public let bfPctAtCapture: Double?
        public let notes: String?
        /// The file name inside the `photos/` subfolder of the export
        /// folder, e.g. `2026-08-03_08-15-42_front_relaxed.heic`.
        public let fileName: String
    }
}

// MARK: - Photo copy plan

/// Instructions for the iOS writer to copy source photo files into the
/// export folder. Kept separate from the `WeekExport` Codable so the
/// JSON payload doesn't leak internal storage paths.
public struct PhotoCopyPlan: Sendable, Equatable {
    /// DB-relative path (e.g. `progress_photos/{uuid}.heic`) — the writer
    /// resolves via `PhotoStore.absoluteURL(for:)`.
    public let sourceRelativePath: String
    /// Human-readable file name inside the export's `photos/` folder.
    public let destinationFileName: String
}

/// Result of `WeekExport.assemble(...)`. Bundles the serializable payload
/// with the copy plan the writer needs.
public struct AssembledWeek: Sendable {
    public let export: WeekExport
    public let photoCopyPlan: [PhotoCopyPlan]
}

// MARK: - Assembler

public extension WeekExport {

    /// Build a `WeekExport` from the given `Week` and database.
    ///
    /// Days after `week.today` on a partial week are omitted from `days`
    /// entirely — Sean's "no look-ahead" rule. Empty days within the
    /// covered range are still emitted, with null fields, so the agent
    /// sees the shape of the week including gaps.
    static func assemble(
        week: Week,
        db: AppDatabase,
        program: Program = .cycle2,
        now: Date = Date()
    ) async throws -> AssembledWeek {
        let cal = Calendar.mondayFirst
        let effectiveEnd = week.effectiveEnd

        // MARK: Range fetches
        let metrics = try await db.bodyMetrics(from: week.start, through: effectiveEnd)
        let logs = try await db.dailyLogs(from: week.start, through: effectiveEnd)
        let nutrition = try await db.nutritionLogs(from: week.start, through: effectiveEnd)
        let workouts = try await db.workouts(from: week.start, through: effectiveEnd)
        let photos = try await db.progressPhotos(from: week.start, through: effectiveEnd)
        let exercises = try await db.allExercises()
        let sets = try await db.sets(forWorkoutIds: workouts.compactMap(\.id))
        let priorWeightRow = try await db.latestWeightBefore(week.start)

        // MARK: Index lookups
        let exercisesById = Dictionary(uniqueKeysWithValues: exercises.compactMap { e in
            e.id.map { ($0, e) }
        })
        let logsByDay = Dictionary(grouping: logs) { cal.startOfDay(for: $0.date) }
        let nutritionByDay = Dictionary(grouping: nutrition) { cal.startOfDay(for: $0.date) }
        let workoutsByDay = Dictionary(grouping: workouts) { cal.startOfDay(for: $0.date) }
        let metricsByDay = Dictionary(grouping: metrics) { cal.startOfDay(for: $0.timestamp) }
        let photosByDay = Dictionary(grouping: photos) { cal.startOfDay(for: $0.timestamp) }
        let setsByWorkoutId = Dictionary(grouping: sets, by: { $0.workoutId })

        // MARK: Per-day assembly
        var dayExports: [DayExport] = []
        var copyPlan: [PhotoCopyPlan] = []
        var filenameCounters: [String: Int] = [:]

        // Iterate Monday through the last day we're covering.
        let days = daysBetween(week.start, and: effectiveEnd, calendar: cal)
        for dayStart in days {
            let weekday = Weekday.from(date: dayStart, calendar: cal)
            let programDay = program.days[weekday].map { formatProgramDay($0) }

            let dayLogs = logsByDay[dayStart] ?? []
            let dayNutrition = nutritionByDay[dayStart] ?? []
            let dayMetrics = metricsByDay[dayStart] ?? []
            let dayWorkouts = workoutsByDay[dayStart] ?? []
            let dayPhotos = photosByDay[dayStart] ?? []

            let dailyLogExport = dayLogs.first.map {
                DailyLogExport(
                    sleepQuality1to10: $0.sleepQuality,
                    notes: $0.notes
                )
            }
            let nutritionExport = dayNutrition.first.map {
                NutritionExport(kcal: $0.kcal, waterOz: $0.waterOz)
            }
            let metricExports = dayMetrics.map { m in
                BodyMetricExport(
                    timestamp: m.timestamp,
                    source: m.source.rawValue,
                    weightLb: m.weightLb,
                    bodyFatPct: m.bodyFatPct,
                    leanMassLb: m.leanMassLb,
                    hrvMs: m.hrvMs,
                    restingHr: m.restingHr
                )
            }
            let workoutExport = dayWorkouts.first.map { w in
                buildWorkoutExport(
                    workout: w,
                    sets: setsByWorkoutId[w.id ?? -1] ?? [],
                    exercisesById: exercisesById,
                    programDay: program.days[weekday]
                )
            }

            var photoExports: [PhotoExport] = []
            for photo in dayPhotos {
                let (fileName, plan) = photoFilenamePlan(
                    for: photo,
                    counters: &filenameCounters
                )
                copyPlan.append(plan)
                photoExports.append(
                    PhotoExport(
                        timestamp: photo.timestamp,
                        angle: photo.angle.rawValue,
                        pose: photo.pose.rawValue,
                        cadence: photo.cadenceTag?.rawValue,
                        weightLbAtCapture: photo.weightLbAtCapture,
                        bfPctAtCapture: photo.bfPctAtCapture,
                        notes: photo.notes,
                        fileName: fileName
                    )
                )
            }

            dayExports.append(
                DayExport(
                    date: dayStart,
                    weekday: weekday.longName,
                    programDay: programDay,
                    dailyLog: dailyLogExport,
                    nutrition: nutritionExport,
                    bodyMetrics: metricExports,
                    workout: workoutExport,
                    photos: photoExports
                )
            )
        }

        // MARK: Summary
        let summary = buildSummary(
            workouts: workouts,
            logs: logs,
            nutrition: nutrition,
            metrics: metrics,
            priorWeight: priorWeightRow?.weightLb,
            photosCount: photos.count
        )

        let weekNumber = program.weekNumber(for: week.start)
        let weekInfo = WeekInfo(
            startDate: week.start,
            endDate: effectiveEnd,
            isPartial: week.isPartial,
            cycle: weekNumber == nil ? nil : program.name,
            weekNumberInCycle: weekNumber
        )

        let export = WeekExport(
            exportVersion: 1,
            generatedAt: now,
            week: weekInfo,
            summary: summary,
            days: dayExports
        )
        return AssembledWeek(export: export, photoCopyPlan: copyPlan)
    }

    // MARK: - Private helpers

    private static func daysBetween(_ start: Date, and end: Date, calendar: Calendar) -> [Date] {
        var out: [Date] = []
        var cursor = calendar.startOfDay(for: start)
        let endDay = calendar.startOfDay(for: end)
        while cursor <= endDay {
            out.append(cursor)
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return out
    }

    private static func formatProgramDay(_ day: ProgramDay) -> String {
        if day.subtitle.isEmpty {
            return day.name
        }
        return "\(day.name) · \(day.subtitle)"
    }

    private static func buildWorkoutExport(
        workout: Workout,
        sets: [ExerciseSet],
        exercisesById: [Int64: Exercise],
        programDay: ProgramDay?
    ) -> WorkoutExport {
        let programExerciseNames = programExerciseNames(from: programDay)

        // Group sets by exercise, preserving order of first appearance in
        // the sets array (which is already ordered by set_number).
        var groupedIds: [Int64] = []
        var groups: [Int64: [ExerciseSet]] = [:]
        for set in sets {
            if groups[set.exerciseId] == nil {
                groupedIds.append(set.exerciseId)
                groups[set.exerciseId] = []
            }
            groups[set.exerciseId]?.append(set)
        }

        let exerciseGroupings: [ExerciseGrouping] = groupedIds.compactMap { eid in
            guard let exercise = exercisesById[eid] else { return nil }
            let setsForExercise = groups[eid] ?? []
            return ExerciseGrouping(
                name: exercise.name,
                isAnchor: exercise.category == .anchor
                    || programExerciseNames.contains(exercise.name),
                sets: setsForExercise.map { set in
                    SetExport(
                        setNumber: set.setNumber,
                        reps: set.reps,
                        weightLb: set.weightLb,
                        rir: set.rir,
                        isWarmup: set.isWarmup,
                        isTopSet: set.isTopSet,
                        e1rm: computeE1RM(set),
                        notes: set.notes
                    )
                }
            )
        }

        return WorkoutExport(
            sessionType: workout.sessionType?.rawValue,
            durationMin: workout.durationMin,
            activeKcal: workout.activeKcal,
            avgHr: workout.avgHr,
            notes: workout.notes,
            exercises: exerciseGroupings
        )
    }

    private static func programExerciseNames(from day: ProgramDay?) -> Set<String> {
        guard let day else { return [] }
        switch day.kind {
        case .lifting(let exercises): return Set(exercises.map(\.name))
        case .hybrid(_, let exercises): return Set(exercises.map(\.name))
        case .rest, .cardio: return []
        }
    }

    private static func computeE1RM(_ set: ExerciseSet) -> Double? {
        guard
            let w = set.weightLb,
            let r = set.reps,
            r > 0
        else { return nil }
        return epleyOneRepMax(weightLb: w, reps: r)
    }

    private static func photoFilenamePlan(
        for photo: ProgressPhoto,
        counters: inout [String: Int]
    ) -> (fileName: String, plan: PhotoCopyPlan) {
        let ext = (photo.photoPath as NSString).pathExtension.lowercased()
        let safeExt = ext.isEmpty ? "img" : ext
        let base = "\(dateSlug(photo.timestamp))_\(photo.angle.rawValue)_\(photo.pose.rawValue)"
        let count = (counters[base] ?? 0) + 1
        counters[base] = count
        let fileName = count == 1
            ? "\(base).\(safeExt)"
            : "\(base)_\(count).\(safeExt)"
        return (
            fileName,
            PhotoCopyPlan(
                sourceRelativePath: photo.photoPath,
                destinationFileName: fileName
            )
        )
    }

    private static func dateSlug(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return f.string(from: date)
    }

    private static func buildSummary(
        workouts: [Workout],
        logs: [DailyLog],
        nutrition: [NutritionLog],
        metrics: [BodyMetric],
        priorWeight: Double?,
        photosCount: Int
    ) -> Summary {
        let sleepValues = logs.compactMap(\.sleepQuality).map(Double.init)
        let avgSleep = sleepValues.isEmpty ? nil : sleepValues.reduce(0, +) / Double(sleepValues.count)

        let calorieValues = nutrition.compactMap(\.kcal).map(Double.init)
        let avgCal = calorieValues.isEmpty ? nil : calorieValues.reduce(0, +) / Double(calorieValues.count)

        let waterValues = nutrition.compactMap(\.waterOz).map(Double.init)
        let avgWater = waterValues.isEmpty ? nil : waterValues.reduce(0, +) / Double(waterValues.count)

        let weightsWithinWeek = metrics.compactMap(\.weightLb)
        let weightEnd = weightsWithinWeek.last
        let weightStart = priorWeight ?? weightsWithinWeek.first
        let weightDelta: Double? = {
            guard let s = weightStart, let e = weightEnd else { return nil }
            return e - s
        }()

        return Summary(
            workoutsCompleted: workouts.count,
            avgSleepQuality: avgSleep,
            weightStartLb: weightStart,
            weightEndLb: weightEnd,
            weightDeltaLb: weightDelta,
            avgCalories: avgCal,
            avgWaterOz: avgWater,
            photosCount: photosCount
        )
    }
}
