import Foundation
import GRDB

/// One training session. Sets belong to a workout via `ExerciseSet.workoutId`.
///
/// `healthkitWorkoutUuid` is set when this row was imported from a HealthKit
/// workout, and is the dedup key on re-import.
public struct Workout: Codable, Equatable, Hashable, Identifiable, Sendable {

    /// Broad session category. `.other` is a valid choice for freeform or
    /// experimental sessions that don't fit the split.
    public enum SessionType: String, Codable, Sendable, CaseIterable {
        case push
        case pull
        case legs
        case upper
        case lower
        case full
        case cardio
        case other
    }

    public var id: Int64?
    public var date: Date
    public var startedAt: Date?
    public var endedAt: Date?
    public var sessionType: SessionType?
    public var durationMin: Int?
    public var healthkitWorkoutUuid: String?
    public var activeKcal: Int?
    public var avgHr: Int?
    public var notes: String?

    public init(
        id: Int64? = nil,
        date: Date,
        startedAt: Date? = nil,
        endedAt: Date? = nil,
        sessionType: SessionType? = nil,
        durationMin: Int? = nil,
        healthkitWorkoutUuid: String? = nil,
        activeKcal: Int? = nil,
        avgHr: Int? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.date = date
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.sessionType = sessionType
        self.durationMin = durationMin
        self.healthkitWorkoutUuid = healthkitWorkoutUuid
        self.activeKcal = activeKcal
        self.avgHr = avgHr
        self.notes = notes
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case date
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case sessionType = "session_type"
        case durationMin = "duration_min"
        case healthkitWorkoutUuid = "healthkit_workout_uuid"
        case activeKcal = "active_kcal"
        case avgHr = "avg_hr"
        case notes
    }
}

extension Workout: FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "workouts"

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
