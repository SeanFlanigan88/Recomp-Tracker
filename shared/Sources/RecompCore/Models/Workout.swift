import Foundation
import GRDB

/// One session of the cycle, identified by its position rather than its date.
///
/// Identity is `(phase, ordinal)`. `ordinal` is 1-based and unbounded — it does
/// not stop at 30 — and the session's content is derived from it via
/// `Phase.slot(forOrdinal:)`. Nothing here is keyed by calendar day, so doing
/// the "Monday" session on a Thursday is a non-event.
///
/// `completedAt` is the only date in the schema. It is nil until the session is
/// marked complete, and is what orders the "what did I lift last time" lookup.
public struct Workout: Codable, Equatable, Hashable, Identifiable, Sendable {

    public var id: Int64?
    public var phase: Phase

    /// 1-based position within the phase. Unbounded.
    public var ordinal: Int

    /// Set when the session is marked complete; nil while pending.
    public var completedAt: Date?

    public init(
        id: Int64? = nil,
        phase: Phase,
        ordinal: Int,
        completedAt: Date? = nil
    ) {
        self.id = id
        self.phase = phase
        self.ordinal = ordinal
        self.completedAt = completedAt
    }

    /// 1-based slot in the 7-session rotation.
    public var slot: Int { Phase.slot(forOrdinal: ordinal) }

    public var isComplete: Bool { completedAt != nil }

    private enum CodingKeys: String, CodingKey {
        case id
        case phase
        case ordinal
        case completedAt = "completed_at"
    }
}

extension Workout: FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "workouts"

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
