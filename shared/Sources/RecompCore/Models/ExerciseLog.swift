import Foundation
import GRDB

/// What was actually lifted for one exercise in one session.
///
/// There is deliberately no `set_number`. One weight and one rep count cover
/// every round of an exercise in a session: the weight does not change
/// mid-session, and only moves between weeks. A session's prescribed set count
/// (`4 x 12-15`) is a display label from the program, never stored here.
///
/// `reps` carries whatever unit the prescription implies — reps, reps per side,
/// seconds, or yards — with no discriminator column. That is safe only because
/// nothing computes on the number; e1RM and PR detection were removed with the
/// rest of the old app. If any math over `reps` is ever reintroduced, this
/// decision has to be reopened first.
public struct ExerciseLog: Codable, Equatable, Hashable, Identifiable, Sendable {

    public var id: Int64?
    public var workoutId: Int64
    public var exerciseId: Int64

    /// Nil for bodyweight and unloaded work (hollow hold, bear crawl, push-ups).
    public var weightLb: Double?

    /// Nil until entered. Unit comes from the prescription shown beside the field.
    public var reps: Int?

    public init(
        id: Int64? = nil,
        workoutId: Int64,
        exerciseId: Int64,
        weightLb: Double? = nil,
        reps: Int? = nil
    ) {
        self.id = id
        self.workoutId = workoutId
        self.exerciseId = exerciseId
        self.weightLb = weightLb
        self.reps = reps
    }

    /// True when neither field has been filled in — the row exists but the
    /// exercise has not been logged yet.
    public var isEmpty: Bool { weightLb == nil && reps == nil }

    private enum CodingKeys: String, CodingKey {
        case id
        case workoutId = "workout_id"
        case exerciseId = "exercise_id"
        case weightLb = "weight_lb"
        case reps
    }
}

extension ExerciseLog: FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "exercise_logs"

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
