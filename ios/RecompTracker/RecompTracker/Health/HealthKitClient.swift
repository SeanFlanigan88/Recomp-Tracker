import Foundation
import HealthKit
import RecompCore

/// Production `HealthKitReading` implementation backed by `HKHealthStore`.
///
/// Lives in the iOS app target — RecompCore stays platform-agnostic and
/// depends only on the protocol.
///
/// `@unchecked Sendable` because `HKHealthStore` isn't formally Sendable, but
/// its `execute(_:)` and `requestAuthorization` methods are documented as
/// thread-safe. The rest of this type is stateless.
public final class HealthKitClient: HealthKitReading, @unchecked Sendable {

    private let store = HKHealthStore()

    public init() {}

    // MARK: - Availability

    public var isHealthDataAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    // MARK: - Authorization

    /// Read types matching commit-5 scope (b): weight + body-fat + lean mass
    /// + HRV + resting HR. Sleep intentionally omitted per design decision.
    private var readTypes: Set<HKObjectType> {
        Set([
            HKQuantityType(.bodyMass),
            HKQuantityType(.bodyFatPercentage),
            HKQuantityType(.leanBodyMass),
            HKQuantityType(.heartRateVariabilitySDNN),
            HKQuantityType(.restingHeartRate),
        ])
    }

    public func requestReadAuthorization() async throws {
        // HK returns success regardless of the user's actual grant/deny per
        // read type — that's by design to prevent apps from inferring
        // sensitive info. We only throw on a genuine OS-level failure.
        try await store.requestAuthorization(toShare: [], read: readTypes)
    }

    // MARK: - Sample queries

    public func quantitySamples(
        kind: QuantitySampleImport.Kind,
        since: Date
    ) async throws -> [QuantitySampleImport] {
        let (typeId, unit, scaleToStorage): (HKQuantityTypeIdentifier, HKUnit, (Double) -> Double)
        switch kind {
        case .weightLb:
            typeId = .bodyMass
            unit = .pound()
            scaleToStorage = { $0 }

        case .bodyFatPct:
            // HKUnit.percent() gives 0.0–1.0 where 1.0 = 100%. Our schema
            // stores 0.0–100.0 (22.5 = 22.5%), so scale up.
            typeId = .bodyFatPercentage
            unit = .percent()
            scaleToStorage = { $0 * 100.0 }

        case .leanMassLb:
            typeId = .leanBodyMass
            unit = .pound()
            scaleToStorage = { $0 }

        case .hrvMs:
            typeId = .heartRateVariabilitySDNN
            unit = .secondUnit(with: .milli)
            scaleToStorage = { $0 }

        case .restingHr:
            typeId = .restingHeartRate
            unit = HKUnit.count().unitDivided(by: .minute())
            scaleToStorage = { $0 }
        }

        let sampleType = HKQuantityType(typeId)
        let predicate = HKQuery.predicateForSamples(withStart: since, end: nil, options: .strictStartDate)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sampleType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(keyPath: \HKSample.startDate, ascending: false)]
            ) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                let quantities = (samples as? [HKQuantitySample]) ?? []
                let mapped: [QuantitySampleImport] = quantities.map { sample in
                    let raw = sample.quantity.doubleValue(for: unit)
                    return QuantitySampleImport(
                        uuid: sample.uuid,
                        kind: kind,
                        value: scaleToStorage(raw),
                        startDate: sample.startDate
                    )
                }
                continuation.resume(returning: mapped)
            }
            self.store.execute(query)
        }
    }
}
