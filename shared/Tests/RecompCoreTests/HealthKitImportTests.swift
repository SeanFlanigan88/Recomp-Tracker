import XCTest
import GRDB
@testable import RecompCore

final class HealthKitImportTests: XCTestCase {

    // MARK: - M003 index

    func testM003CreatesPartialUniqueIndex() async throws {
        let db = try AppDatabase.inMemory()

        let indexNames = try await db.read { db in
            try String.fetchAll(db, sql: """
                SELECT name FROM sqlite_master
                WHERE type = 'index' AND tbl_name = 'body_metrics'
                """)
        }
        XCTAssertTrue(indexNames.contains("body_metrics_healthkit_uuid_unique"),
                      "M003 should have created the unique index; got: \(indexNames)")
    }

    /// The unique index must be partial (WHERE healthkit_uuid IS NOT NULL) —
    /// otherwise manual entries (all with null uuid) would collide with each
    /// other on the very first duplicate.
    func testUniqueIndexPermitsMultipleNullUuids() async throws {
        let db = try AppDatabase.inMemory()
        let now = Date()

        try await db.write { db in
            for _ in 0..<3 {
                var m = BodyMetric(timestamp: now, source: .manual, weightLb: 180)
                try m.insert(db)
            }
        }

        let count = try await db.read { db in
            try BodyMetric.filter(Column("source") == "manual").fetchCount(db)
        }
        XCTAssertEqual(count, 3, "manual entries with null uuid must not collide")
    }

    func testUniqueIndexRejectsDuplicateNonNullUuid() async throws {
        let db = try AppDatabase.inMemory()
        let uuid = UUID().uuidString

        try await db.write { db in
            var first = BodyMetric(
                timestamp: Date(),
                source: .healthkit,
                healthkitUuid: uuid,
                weightLb: 184.6
            )
            try first.insert(db)
        }

        do {
            try await db.write { db in
                var dupe = BodyMetric(
                    timestamp: Date(),
                    source: .healthkit,
                    healthkitUuid: uuid,
                    weightLb: 184.6
                )
                try dupe.insert(db)
            }
            XCTFail("second insert with same uuid should have thrown a constraint error")
        } catch {
            // Expected — SQLITE_CONSTRAINT_UNIQUE.
        }
    }

    // MARK: - Import idempotency

    func testImportInsertsFreshSamples() async throws {
        let db = try AppDatabase.inMemory()
        let now = Date()

        let samples = [
            QuantitySampleImport(uuid: UUID(), kind: .weightLb,   value: 184.6, startDate: now),
            QuantitySampleImport(uuid: UUID(), kind: .bodyFatPct, value: 22.3,  startDate: now),
            QuantitySampleImport(uuid: UUID(), kind: .leanMassLb, value: 143.5, startDate: now),
            QuantitySampleImport(uuid: UUID(), kind: .hrvMs,      value: 62.0,  startDate: now),
            QuantitySampleImport(uuid: UUID(), kind: .restingHr,  value: 54.7,  startDate: now),
        ]

        let inserted = try await db.importHealthKitSamples(samples)
        XCTAssertEqual(inserted, 5)

        let all = try await db.read { db in
            try BodyMetric.filter(Column("source") == "healthkit").fetchAll(db)
        }
        XCTAssertEqual(all.count, 5)
    }

    func testImportIsIdempotentByUuid() async throws {
        let db = try AppDatabase.inMemory()
        let uuid = UUID()
        let now = Date()

        let sample = QuantitySampleImport(uuid: uuid, kind: .weightLb, value: 184.6, startDate: now)

        let first = try await db.importHealthKitSamples([sample])
        XCTAssertEqual(first, 1)

        let second = try await db.importHealthKitSamples([sample])
        XCTAssertEqual(second, 0, "re-importing the same UUID must be a no-op")

        let count = try await db.read { db in
            try BodyMetric.filter(Column("healthkit_uuid") == uuid.uuidString).fetchCount(db)
        }
        XCTAssertEqual(count, 1)
    }

    func testImportOfMixedNewAndExistingOnlyInsertsNew() async throws {
        let db = try AppDatabase.inMemory()
        let existing = UUID()
        let fresh = UUID()

        _ = try await db.importHealthKitSamples([
            QuantitySampleImport(uuid: existing, kind: .weightLb, value: 180, startDate: Date()),
        ])

        let inserted = try await db.importHealthKitSamples([
            QuantitySampleImport(uuid: existing, kind: .weightLb, value: 180, startDate: Date()),
            QuantitySampleImport(uuid: fresh,    kind: .weightLb, value: 182, startDate: Date()),
        ])
        XCTAssertEqual(inserted, 1, "only the new UUID should insert")
    }

    // MARK: - Kind → column mapping

    func testEachKindLandsInCorrectColumn() async throws {
        let db = try AppDatabase.inMemory()
        let now = Date()

        _ = try await db.importHealthKitSamples([
            QuantitySampleImport(uuid: UUID(), kind: .weightLb,   value: 184.6, startDate: now),
            QuantitySampleImport(uuid: UUID(), kind: .bodyFatPct, value: 22.3,  startDate: now),
            QuantitySampleImport(uuid: UUID(), kind: .leanMassLb, value: 143.5, startDate: now),
            QuantitySampleImport(uuid: UUID(), kind: .hrvMs,      value: 62.0,  startDate: now),
            QuantitySampleImport(uuid: UUID(), kind: .restingHr,  value: 54.7,  startDate: now),
        ])

        let rows = try await db.read { db in
            try BodyMetric.filter(Column("source") == "healthkit").fetchAll(db)
        }

        XCTAssertEqual(rows.first(where: { $0.weightLb != nil })?.weightLb, 184.6)
        XCTAssertEqual(rows.first(where: { $0.bodyFatPct != nil })?.bodyFatPct, 22.3)
        XCTAssertEqual(rows.first(where: { $0.leanMassLb != nil })?.leanMassLb, 143.5)
        XCTAssertEqual(rows.first(where: { $0.hrvMs != nil })?.hrvMs, 62.0)
        // restingHr rounds a fractional bpm to Int per the schema type.
        XCTAssertEqual(rows.first(where: { $0.restingHr != nil })?.restingHr, 55)
    }

    // MARK: - todaysDisplayWeight

    func testDisplayWeightPrefersManualOverHealthKit() async throws {
        let db = try AppDatabase.inMemory()
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let morning = today.addingTimeInterval(6 * 3600)
        let evening = today.addingTimeInterval(19 * 3600)

        // HK weigh-in in the morning (earlier).
        _ = try await db.importHealthKitSamples([
            QuantitySampleImport(uuid: UUID(), kind: .weightLb, value: 184.6, startDate: morning),
        ])

        // Manual entry in the evening (later — but even if earlier, manual
        // should still win by rule).
        try await db.upsertTodaysManualWeight(183.9, on: evening)

        let display = try await db.todaysDisplayWeight(on: today)
        XCTAssertEqual(display, 183.9, "manual entry overrides HK for display")
    }

    func testDisplayWeightFallsBackToHealthKitWhenNoManual() async throws {
        let db = try AppDatabase.inMemory()
        let today = Calendar.current.startOfDay(for: Date())
        let morning = today.addingTimeInterval(6 * 3600)

        _ = try await db.importHealthKitSamples([
            QuantitySampleImport(uuid: UUID(), kind: .weightLb, value: 184.6, startDate: morning),
        ])

        let display = try await db.todaysDisplayWeight(on: today)
        XCTAssertEqual(display, 184.6)
    }

    func testDisplayWeightReturnsNilWithNoData() async throws {
        let db = try AppDatabase.inMemory()
        let display = try await db.todaysDisplayWeight(on: Date())
        XCTAssertNil(display)
    }

    /// A day where the only HK sample is HRV must not surface as a weight.
    func testDisplayWeightIgnoresRowsWithoutWeightValue() async throws {
        let db = try AppDatabase.inMemory()
        let today = Calendar.current.startOfDay(for: Date())
        let morning = today.addingTimeInterval(6 * 3600)

        _ = try await db.importHealthKitSamples([
            QuantitySampleImport(uuid: UUID(), kind: .hrvMs, value: 62, startDate: morning),
        ])

        let display = try await db.todaysDisplayWeight(on: today)
        XCTAssertNil(display, "an HRV-only day must not report a weight")
    }

    func testDisplayWeightPicksLatestHealthKitWhenMultiple() async throws {
        let db = try AppDatabase.inMemory()
        let today = Calendar.current.startOfDay(for: Date())
        let morning = today.addingTimeInterval(6 * 3600)
        let evening = today.addingTimeInterval(19 * 3600)

        _ = try await db.importHealthKitSamples([
            QuantitySampleImport(uuid: UUID(), kind: .weightLb, value: 184.6, startDate: morning),
            QuantitySampleImport(uuid: UUID(), kind: .weightLb, value: 183.9, startDate: evening),
        ])

        let display = try await db.todaysDisplayWeight(on: today)
        XCTAssertEqual(display, 183.9, "latest HK weigh-in of the day should be shown")
    }
}

// MARK: - Fake HK client

/// In-memory HealthKitReading implementation for use in test-side
/// integration tests that want to exercise the full request → sample →
/// import → query loop without touching real HealthKit. Not used above
/// (each test above feeds samples directly to importHealthKitSamples), but
/// available for future workflow-level tests.
final class FakeHealthKitClient: HealthKitReading, @unchecked Sendable {
    var isHealthDataAvailable: Bool = true
    var samplesByKind: [QuantitySampleImport.Kind: [QuantitySampleImport]] = [:]
    var authorizationError: Error? = nil
    var sampleQueryError: Error? = nil

    var authorizationCallCount = 0

    func requestReadAuthorization() async throws {
        authorizationCallCount += 1
        if let error = authorizationError { throw error }
    }

    func quantitySamples(
        kind: QuantitySampleImport.Kind,
        since: Date
    ) async throws -> [QuantitySampleImport] {
        if let error = sampleQueryError { throw error }
        return (samplesByKind[kind] ?? []).filter { $0.startDate >= since }
    }
}

final class FakeHealthKitClientIntegrationTests: XCTestCase {

    func testEndToEndImportFlowViaFake() async throws {
        let db = try AppDatabase.inMemory()
        let hk = FakeHealthKitClient()
        let now = Date()

        hk.samplesByKind = [
            .weightLb: [
                QuantitySampleImport(uuid: UUID(), kind: .weightLb, value: 184.6, startDate: now),
            ],
            .hrvMs: [
                QuantitySampleImport(uuid: UUID(), kind: .hrvMs, value: 58.4, startDate: now),
            ],
        ]

        try await hk.requestReadAuthorization()
        var all: [QuantitySampleImport] = []
        for kind in QuantitySampleImport.Kind.allCases {
            all.append(contentsOf: try await hk.quantitySamples(kind: kind, since: .distantPast))
        }
        let inserted = try await db.importHealthKitSamples(all)
        XCTAssertEqual(inserted, 2)
        XCTAssertEqual(hk.authorizationCallCount, 1)

        let weight = try await db.todaysDisplayWeight(on: now)
        XCTAssertEqual(weight, 184.6)
    }
}
