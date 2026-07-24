import Foundation
import GRDB

/// Daily nutrition totals. Per-meal food logging is intentionally out of scope
/// for v1 — see `docs/schema.md`.
public struct NutritionLog: Codable, Equatable, Hashable, Identifiable, Sendable {

    public var id: Int64?
    public var date: Date
    public var kcal: Int?
    public var proteinG: Int?
    public var carbsG: Int?
    public var fatG: Int?
    public var targetKcal: Int?
    public var targetProteinG: Int?
    public var waterOz: Int?
    public var notes: String?

    public init(
        id: Int64? = nil,
        date: Date,
        kcal: Int? = nil,
        proteinG: Int? = nil,
        carbsG: Int? = nil,
        fatG: Int? = nil,
        targetKcal: Int? = nil,
        targetProteinG: Int? = nil,
        waterOz: Int? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.date = date
        self.kcal = kcal
        self.proteinG = proteinG
        self.carbsG = carbsG
        self.fatG = fatG
        self.targetKcal = targetKcal
        self.targetProteinG = targetProteinG
        self.waterOz = waterOz
        self.notes = notes
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case date
        case kcal
        case proteinG = "protein_g"
        case carbsG = "carbs_g"
        case fatG = "fat_g"
        case targetKcal = "target_kcal"
        case targetProteinG = "target_protein_g"
        case waterOz = "water_oz"
        case notes
    }
}

extension NutritionLog: FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "nutrition_log"

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
