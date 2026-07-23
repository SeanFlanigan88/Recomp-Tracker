import Foundation
import GRDB

/// A single set within a workout. Highest-volume table in the schema over time.
///
/// - `workoutId` cascades on delete (removing a workout removes its sets).
/// - `exerciseId` restricts on delete (an exercise referenced by sets cannot be
///   deleted; this preserves historical accuracy).
public struct ExerciseSet: Codable, Equatable, Hashable, Identifiable, Sendable {

    public var id: Int64?
    public var workoutId: Int64
    public var exerciseId: Int64
    public var setNumber: Int
    public var weightLb: Double?
    public var reps: Int?
    /// Reps in reserve (0–5+). Optional.
    public var rir: Int?
    /// Flags the working / heaviest set for a lift.
    public var isTopSet: Bool
    public var isWarmup: Bool
    public var notes: String?

    public init(
        id: Int64? = nil,
        workoutId: Int64,
        exerciseId: Int64,
        setNumber: Int,
        weightLb: Double? = nil,
        reps: Int? = nil,
        rir: Int? = nil,
        isTopSet: Bool = false,
        isWarmup: Bool = false,
        notes: String? = nil
    ) {
        self.id = id
        self.workoutId = workoutId
        self.exerciseId = exerciseId
        self.setNumber = setNumber
        self.weightLb = weightLb
        self.reps = reps
        self.rir = rir
        self.isTopSet = isTopSet
        self.isWarmup = isWarmup
        self.notes = notes
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case workoutId = "workout_id"
        case exerciseId = "exercise_id"
        case setNumber = "set_number"
        case weightLb = "weight_lb"
        case reps
        case rir
        case isTopSet = "is_top_set"
        case isWarmup = "is_warmup"
        case notes
    }
}

extension ExerciseSet: FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "exercise_sets"

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
