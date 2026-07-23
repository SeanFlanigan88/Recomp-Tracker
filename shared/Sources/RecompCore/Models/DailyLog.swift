import Foundation
import GRDB

/// Subjective daily state — one row per calendar date.
///
/// Never sourced from HealthKit. `trainingReadiness` is a computed field
/// updated on write; the schema treats it as a persisted column so it can be
/// queried and charted without re-computation.
public struct DailyLog: Codable, Equatable, Hashable, Identifiable, Sendable {

    public var id: Int64?
    public var date: Date

    /// Energy level, 1–10 scale.
    public var energy: Int?
    /// Freeform mood tag.
    public var mood: String?
    /// Subjective sleep quality, 1–10 scale. Distinct from `BodyMetric.sleepHours`.
    public var sleepQuality: Int?
    /// Stress level, 1–10 scale.
    public var stress: Int?
    public var notes: String?
    /// Computed at write time.
    public var trainingReadiness: Double?

    public init(
        id: Int64? = nil,
        date: Date,
        energy: Int? = nil,
        mood: String? = nil,
        sleepQuality: Int? = nil,
        stress: Int? = nil,
        notes: String? = nil,
        trainingReadiness: Double? = nil
    ) {
        self.id = id
        self.date = date
        self.energy = energy
        self.mood = mood
        self.sleepQuality = sleepQuality
        self.stress = stress
        self.notes = notes
        self.trainingReadiness = trainingReadiness
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case date
        case energy = "energy_1_10"
        case mood
        case sleepQuality = "sleep_quality_1_10"
        case stress = "stress_1_10"
        case notes
        case trainingReadiness = "training_readiness"
    }
}

extension DailyLog: FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "daily_log"

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
