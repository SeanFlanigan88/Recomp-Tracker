import Foundation
import GRDB

/// A movement, identified by its canonical name.
///
/// The name is deliberately free of coaching cues. The program JSON writes
/// "KB goblet squat", "KB goblet squat (heavier KB)" and "KB goblet squat
/// (max KB, pause at bottom)" for what is one movement across three phases;
/// the parenthetical is split off at ingestion and lives on the program's
/// `cue`, not here.
///
/// That split is load-bearing. `name` is UNIQUE and is the join key behind
/// "what did I lift last time", so fragmenting it would silently hide history
/// every time a phase boundary is crossed.
public struct Exercise: Codable, Equatable, Hashable, Identifiable, Sendable {

    public var id: Int64?
    public var name: String

    public init(id: Int64? = nil, name: String) {
        self.id = id
        self.name = name
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
    }
}

extension Exercise: FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "exercises"

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
