import XCTest
import GRDB
@testable import RecompCore

/// Coverage for the "closest reading within N seconds" lookups that feed the
/// progress-photo snapshot columns. The 24-hour window is the load-bearing
/// business rule (Sean: "anything after 24 hours really isn't relevant
/// anymore") — the boundary tests pin it.
final class BodyMetricsSnapshotQueriesTests: XCTestCase {

    private let day: TimeInterval = 86_400

    // MARK: - Fixtures

    private func insert(
        into db: AppDatabase,
        timestamp: Date,
        weightLb: Double? = nil,
        bodyFatPct: Double? = nil,
        source: BodyMetric.Source = .healthkit
    ) async throws {
        try await db.write { db in
            var m = BodyMetric(
                timestamp: timestamp,
                source: source,
                weightLb: weightLb,
                bodyFatPct: bodyFatPct
            )
            try m.insert(db)
        }
    }

    // MARK: - Empty table

    func testNearestWeightReturnsNilWhenNoRows() async throws {
        let db = try AppDatabase.inMemory()
        let value = try await db.nearestWeightReading(to: Date(), within: day)
        XCTAssertNil(value)
    }

    func testNearestBodyFatReturnsNilWhenNoRows() async throws {
        let db = try AppDatabase.inMemory()
        let value = try await db.nearestBodyFatReading(to: Date(), within: day)
        XCTAssertNil(value)
    }

    // MARK: - Independence: sparse rows

    func testWeightAndBodyFatLookedUpIndependently() async throws {
        // The scenario: a manual weight entry (weight only) is closer to the
        // target than a scale reading (weight + BF). The weight snapshot
        // should come from the manual entry; the BF snapshot should come
        // from the scale reading. Two independent nearest-in-window lookups.
        let db = try AppDatabase.inMemory()
        let target = Date(timeIntervalSince1970: 1_720_000_000)

        // Scale reading 20 hours before target: weight + BF both populated.
        try await insert(into: db,
                         timestamp: target.addingTimeInterval(-20 * 3600),
                         weightLb: 180.0,
                         bodyFatPct: 18.5)

        // Manual weight 2 hours before target: weight only, no BF.
        try await insert(into: db,
                         timestamp: target.addingTimeInterval(-2 * 3600),
                         weightLb: 181.2,
                         bodyFatPct: nil,
                         source: .manual)

        let w = try await db.nearestWeightReading(to: target, within: day)
        let bf = try await db.nearestBodyFatReading(to: target, within: day)

        XCTAssertEqual(w, 181.2, "closest row with weight_lb NOT NULL wins")
        XCTAssertEqual(bf, 18.5, "sparse manual row is invisible to BF lookup")
    }

    func testRowsWithNullTargetColumnAreIgnored() async throws {
        // A row whose target column is NULL should not be considered a
        // candidate, even if it is the closest row by time.
        let db = try AppDatabase.inMemory()
        let target = Date(timeIntervalSince1970: 1_720_000_000)

        // Very close but no weight.
        try await insert(into: db,
                         timestamp: target.addingTimeInterval(-60),
                         weightLb: nil,
                         bodyFatPct: 22.0)

        // Farther but has weight.
        try await insert(into: db,
                         timestamp: target.addingTimeInterval(-6 * 3600),
                         weightLb: 175.0)

        let w = try await db.nearestWeightReading(to: target, within: day)
        XCTAssertEqual(w, 175.0)
    }

    // MARK: - 24-hour window boundary

    func testExactlyAt24HoursIsInsideWindow() async throws {
        // Sean's rule is ±24hrs inclusive. A reading exactly 24hrs away
        // should qualify — off-by-one on the boundary should not silently
        // discard it.
        let db = try AppDatabase.inMemory()
        let target = Date(timeIntervalSince1970: 1_720_000_000)

        try await insert(into: db,
                         timestamp: target.addingTimeInterval(-day),
                         weightLb: 180.0)

        let w = try await db.nearestWeightReading(to: target, within: day)
        XCTAssertEqual(w, 180.0)
    }

    func testJustOutside24HoursIsExcluded() async throws {
        let db = try AppDatabase.inMemory()
        let target = Date(timeIntervalSince1970: 1_720_000_000)

        // 24 hours + 1 second before target.
        try await insert(into: db,
                         timestamp: target.addingTimeInterval(-(day + 1)),
                         weightLb: 180.0)

        let w = try await db.nearestWeightReading(to: target, within: day)
        XCTAssertNil(w, "reading outside the ±24hr window must not be returned")
    }

    func testFutureWithinWindowQualifies() async throws {
        // Bidirectional: a reading *after* the photo also qualifies. A
        // Sunday-morning photo can validly match Sunday-evening's scale.
        let db = try AppDatabase.inMemory()
        let target = Date(timeIntervalSince1970: 1_720_000_000)

        try await insert(into: db,
                         timestamp: target.addingTimeInterval(6 * 3600),
                         weightLb: 179.5)

        let w = try await db.nearestWeightReading(to: target, within: day)
        XCTAssertEqual(w, 179.5)
    }

    // MARK: - Closest wins

    func testClosestOfMultipleCandidatesWins() async throws {
        let db = try AppDatabase.inMemory()
        let target = Date(timeIntervalSince1970: 1_720_000_000)

        try await insert(into: db,
                         timestamp: target.addingTimeInterval(-18 * 3600),
                         weightLb: 170.0)
        try await insert(into: db,
                         timestamp: target.addingTimeInterval(-3 * 3600),
                         weightLb: 180.0)
        try await insert(into: db,
                         timestamp: target.addingTimeInterval(10 * 3600),
                         weightLb: 175.0)

        let w = try await db.nearestWeightReading(to: target, within: day)
        XCTAssertEqual(w, 180.0, "the -3h reading is closest")
    }

    // MARK: - Tie-breaking

    func testEqualDistanceTiesBreakToEarlierTimestamp() async throws {
        // Two rows equidistant from the target. The earlier one wins —
        // documented deterministic tie-break, and morning-side readings are
        // more likely to reflect a canonical fasted state anyway.
        let db = try AppDatabase.inMemory()
        let target = Date(timeIntervalSince1970: 1_720_000_000)

        try await insert(into: db,
                         timestamp: target.addingTimeInterval(-4 * 3600),
                         weightLb: 180.0)
        try await insert(into: db,
                         timestamp: target.addingTimeInterval(4 * 3600),
                         weightLb: 182.0)

        let w = try await db.nearestWeightReading(to: target, within: day)
        XCTAssertEqual(w, 180.0, "earlier row wins on tied distance")
    }
}
