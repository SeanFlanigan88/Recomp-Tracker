import Foundation
import GRDB

/// A progress photo with pose modifiers for accurate comparison.
///
/// `weightLbAtCapture` and `bfPctAtCapture` are denormalized snapshots — see
/// `docs/schema.md` design principle 2. Historical comparisons stay stable even
/// if HealthKit later revises the underlying scale reading.
public struct ProgressPhoto: Codable, Equatable, Hashable, Identifiable, Sendable {

    public enum Angle: String, Codable, Sendable, CaseIterable {
        case front
        case sideLeft = "side_left"
        case sideRight = "side_right"
        case back
    }

    public enum Pose: String, Codable, Sendable, CaseIterable {
        case relaxed
        case flexed
    }

    /// Cadence at which this photo was intended to be captured. Optional —
    /// ad-hoc photos can leave this nil.
    public enum CadenceTag: String, Codable, Sendable, CaseIterable {
        case weekly
        case biweekly
        case monthly
    }

    public var id: Int64?
    public var date: Date
    public var timestamp: Date
    public var angle: Angle
    public var pose: Pose
    /// Path to the image on local disk, stored *relative* to the app's
    /// Documents directory (e.g. `progress_photos/{uuid}.heic`). Relative
    /// storage is required because iOS may relocate the app container across
    /// installs — absolute paths silently break on restore.
    public var photoPath: String
    public var weightLbAtCapture: Double?
    public var bfPctAtCapture: Double?
    public var cadenceTag: CadenceTag?
    public var notes: String?

    public init(
        id: Int64? = nil,
        date: Date,
        timestamp: Date,
        angle: Angle,
        pose: Pose,
        photoPath: String,
        weightLbAtCapture: Double? = nil,
        bfPctAtCapture: Double? = nil,
        cadenceTag: CadenceTag? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.date = date
        self.timestamp = timestamp
        self.angle = angle
        self.pose = pose
        self.photoPath = photoPath
        self.weightLbAtCapture = weightLbAtCapture
        self.bfPctAtCapture = bfPctAtCapture
        self.cadenceTag = cadenceTag
        self.notes = notes
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case date
        case timestamp
        case angle
        case pose
        case photoPath = "photo_path"
        case weightLbAtCapture = "weight_lb_at_capture"
        case bfPctAtCapture = "bf_pct_at_capture"
        case cadenceTag = "cadence_tag"
        case notes
    }
}

extension ProgressPhoto: FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "progress_photos"

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
