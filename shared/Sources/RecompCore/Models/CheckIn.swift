import Foundation
import GRDB

/// Periodic review snapshot. Weekly / biweekly / monthly.
///
/// Aggregated metrics are computed at check-in time and stored (rather than
/// recomputed on read) so historical snapshots remain stable — a change to how
/// we compute `totalVolumeLb` today shouldn't rewrite last month's check-ins.
public struct CheckIn: Codable, Equatable, Hashable, Identifiable, Sendable {

    public enum PeriodType: String, Codable, Sendable, CaseIterable {
        case weekly
        case biweekly
        case monthly
    }

    public var id: Int64?
    public var date: Date
    public var periodType: PeriodType
    public var periodStart: Date
    public var periodEnd: Date
    public var avgWeightLb: Double?
    public var avgBodyFatPct: Double?
    public var avgSleepHours: Double?
    public var workoutsCompleted: Int?
    /// Sum of weight × reps across all working sets in the period.
    public var totalVolumeLb: Double?
    public var reflectionNotes: String?
    /// For conversations with Claude / a coach.
    public var coachNotes: String?

    public init(
        id: Int64? = nil,
        date: Date,
        periodType: PeriodType,
        periodStart: Date,
        periodEnd: Date,
        avgWeightLb: Double? = nil,
        avgBodyFatPct: Double? = nil,
        avgSleepHours: Double? = nil,
        workoutsCompleted: Int? = nil,
        totalVolumeLb: Double? = nil,
        reflectionNotes: String? = nil,
        coachNotes: String? = nil
    ) {
        self.id = id
        self.date = date
        self.periodType = periodType
        self.periodStart = periodStart
        self.periodEnd = periodEnd
        self.avgWeightLb = avgWeightLb
        self.avgBodyFatPct = avgBodyFatPct
        self.avgSleepHours = avgSleepHours
        self.workoutsCompleted = workoutsCompleted
        self.totalVolumeLb = totalVolumeLb
        self.reflectionNotes = reflectionNotes
        self.coachNotes = coachNotes
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case date
        case periodType = "period_type"
        case periodStart = "period_start"
        case periodEnd = "period_end"
        case avgWeightLb = "avg_weight_lb"
        case avgBodyFatPct = "avg_body_fat_pct"
        case avgSleepHours = "avg_sleep_hours"
        case workoutsCompleted = "workouts_completed"
        case totalVolumeLb = "total_volume_lb"
        case reflectionNotes = "reflection_notes"
        case coachNotes = "coach_notes"
    }
}

extension CheckIn: FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "check_ins"

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
