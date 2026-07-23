import Foundation
import GRDB

/// Reference row for an exercise. Seeded on first launch; users can add custom
/// entries which will have `isCustom == true`.
///
/// `primaryMuscleGroup` and `movementPattern` are open-ended strings rather than
/// enums because the vocabulary evolves as programming does. Enum-worthy at
/// commit-#2 scope would be premature — revisit once we have a settled taxonomy.
public struct Exercise: Codable, Equatable, Hashable, Identifiable, Sendable {

    /// High-level classification within a program.
    public enum Category: String, Codable, Sendable, CaseIterable {
        case anchor
        case accessory
        case cardio
    }

    public var id: Int64?
    public var name: String
    public var category: Category?
    public var primaryMuscleGroup: String?
    public var movementPattern: String?
    public var isBilateral: Bool
    public var isCustom: Bool

    public init(
        id: Int64? = nil,
        name: String,
        category: Category? = nil,
        primaryMuscleGroup: String? = nil,
        movementPattern: String? = nil,
        isBilateral: Bool = true,
        isCustom: Bool = false
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.primaryMuscleGroup = primaryMuscleGroup
        self.movementPattern = movementPattern
        self.isBilateral = isBilateral
        self.isCustom = isCustom
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case category
        case primaryMuscleGroup = "primary_muscle_group"
        case movementPattern = "movement_pattern"
        case isBilateral = "is_bilateral"
        case isCustom = "is_custom"
    }
}

extension Exercise: FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "exercises"

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
