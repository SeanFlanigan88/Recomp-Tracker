import Foundation

/// One of the three 30-session blocks of the cycle.
///
/// Stored as its raw `Int` so the database column stays readable, and so
/// `phase` sorts naturally. The enum exists so that "phase 4" and "phase 0"
/// are not expressible in Swift; the schema carries a matching CHECK for
/// anything that reaches SQL by another route.
public enum Phase: Int, Codable, Hashable, Sendable, CaseIterable, Identifiable {
    case one = 1
    case two = 2
    case three = 3

    public var id: Int { rawValue }

    /// Display title, e.g. "Phase 2".
    public var title: String { "Phase \(rawValue)" }

    /// Nominal length of a phase, used as the denominator in the
    /// `x/30` counter on the home screen.
    ///
    /// This is a label, not a limit. `ordinal` is unbounded and a phase
    /// showing `37/30` is a valid, expected state — it means the block has
    /// run past its nominal length, which is fine.
    public static let nominalSessionCount = 30

    /// Number of distinct sessions in the repeating rotation.
    public static let rotationLength = 7

    /// 1-based slot in the rotation for a given 1-based ordinal.
    ///
    /// Session 1 is slot 1, session 8 is slot 1 again, and so on. Slot is
    /// always derived, never stored.
    public static func slot(forOrdinal ordinal: Int) -> Int {
        precondition(ordinal >= 1, "ordinal is 1-based, got \(ordinal)")
        return ((ordinal - 1) % rotationLength) + 1
    }
}
