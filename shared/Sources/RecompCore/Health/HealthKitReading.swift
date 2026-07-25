import Foundation

/// One HealthKit quantity sample, normalized into the units the app stores.
///
/// Deliberately pure Swift — no `import HealthKit` — so RecompCore stays
/// platform-agnostic and testable on macOS. The iOS client converts raw HK
/// samples into this shape at the boundary.
public struct QuantitySampleImport: Sendable, Equatable, Hashable {

    /// Which body-metric field the sample maps to. Cases correspond one-to-one
    /// with the columns on `body_metrics` that HealthKit currently populates.
    public enum Kind: String, Sendable, CaseIterable, Hashable {
        case weightLb
        case bodyFatPct
        case leanMassLb
        case hrvMs
        case restingHr
    }

    /// The HK sample's stable identifier. Used verbatim as
    /// `body_metrics.healthkit_uuid` for dedup — re-importing the same UUID is
    /// a no-op.
    public let uuid: UUID
    public let kind: Kind
    /// Value expressed in the unit the schema stores:
    /// pounds for weight/lean mass, percent (0–100) for body fat,
    /// milliseconds for HRV, bpm for resting HR.
    public let value: Double
    public let startDate: Date

    public init(uuid: UUID, kind: Kind, value: Double, startDate: Date) {
        self.uuid = uuid
        self.kind = kind
        self.value = value
        self.startDate = startDate
    }
}

/// Abstraction over HealthKit reads. The iOS app provides an `HKHealthStore`-
/// backed implementation; tests provide a canned-samples fake. Neither
/// implementation is required to talk to HealthKit — see `isHealthDataAvailable`.
///
/// Sendable so it can be captured by async work spawned from SwiftUI views.
public protocol HealthKitReading: Sendable {

    /// False on platforms/devices where HealthKit isn't present (e.g., the
    /// iOS simulator's HealthKit availability varies by version, and macOS
    /// test targets never see it). Callers use this to silently skip the
    /// whole HK bootstrap rather than treat absence as a failure.
    var isHealthDataAvailable: Bool { get }

    /// Ask the user to grant read access to the types this app cares about.
    /// Throws only on a genuine handshake failure (the OS couldn't process
    /// the request). A user "deny" is *not* an error — HealthKit hides the
    /// distinction to protect user privacy, and the app is expected to
    /// degrade gracefully to empty read results.
    func requestReadAuthorization() async throws

    /// Fetch all samples of the given kind whose start date is at or after
    /// `since`. Empty result if the user hasn't granted access (or has no
    /// data) — callers must not treat empty as an error.
    func quantitySamples(
        kind: QuantitySampleImport.Kind,
        since: Date
    ) async throws -> [QuantitySampleImport]
}
