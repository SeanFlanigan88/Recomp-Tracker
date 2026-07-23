import Foundation
import GRDB

/// A single body-metric measurement event.
///
/// One row per measurement. Some rows are dense (a full smart-scale reading fills
/// eight columns); some are sparse (a morning HRV reading fills one). Both live in
/// the same table by design — see `docs/schema.md` design principle 3.
///
/// `source` distinguishes HealthKit-sourced rows from manual entry. When
/// `source == .healthkit`, `healthkitUuid` is expected to be set and is used for
/// dedup on re-import.
public struct BodyMetric: Codable, Equatable, Hashable, Identifiable, Sendable {

    /// Where this measurement came from.
    public enum Source: String, Codable, Sendable, CaseIterable {
        case healthkit
        case manual
    }

    public var id: Int64?
    public var timestamp: Date
    public var source: Source
    public var healthkitUuid: String?

    public var weightLb: Double?
    public var bodyFatPct: Double?
    public var leanMassLb: Double?
    public var boneMassLb: Double?
    public var bodyWaterPct: Double?
    public var visceralFatRating: Double?
    public var bmrKcal: Int?

    public var restingHr: Int?
    public var hrvMs: Double?
    public var sleepHours: Double?
    /// Sleep efficiency, 0.0 – 1.0.
    public var sleepEfficiency: Double?

    public init(
        id: Int64? = nil,
        timestamp: Date,
        source: Source,
        healthkitUuid: String? = nil,
        weightLb: Double? = nil,
        bodyFatPct: Double? = nil,
        leanMassLb: Double? = nil,
        boneMassLb: Double? = nil,
        bodyWaterPct: Double? = nil,
        visceralFatRating: Double? = nil,
        bmrKcal: Int? = nil,
        restingHr: Int? = nil,
        hrvMs: Double? = nil,
        sleepHours: Double? = nil,
        sleepEfficiency: Double? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.source = source
        self.healthkitUuid = healthkitUuid
        self.weightLb = weightLb
        self.bodyFatPct = bodyFatPct
        self.leanMassLb = leanMassLb
        self.boneMassLb = boneMassLb
        self.bodyWaterPct = bodyWaterPct
        self.visceralFatRating = visceralFatRating
        self.bmrKcal = bmrKcal
        self.restingHr = restingHr
        self.hrvMs = hrvMs
        self.sleepHours = sleepHours
        self.sleepEfficiency = sleepEfficiency
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case timestamp
        case source
        case healthkitUuid = "healthkit_uuid"
        case weightLb = "weight_lb"
        case bodyFatPct = "body_fat_pct"
        case leanMassLb = "lean_mass_lb"
        case boneMassLb = "bone_mass_lb"
        case bodyWaterPct = "body_water_pct"
        case visceralFatRating = "visceral_fat_rating"
        case bmrKcal = "bmr_kcal"
        case restingHr = "resting_hr"
        case hrvMs = "hrv_ms"
        case sleepHours = "sleep_hours"
        case sleepEfficiency = "sleep_efficiency"
    }
}

extension BodyMetric: FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "body_metrics"

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
