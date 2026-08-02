import Foundation
import GRDB

// MARK: - Query API

extension AppDatabase {

    // MARK: Nearest-in-time snapshot lookups
    //
    // These support the progress-photos flow: when a photo lands at time T,
    // we want the closest body-composition reading within a ±24hr window to
    // stamp onto `weight_lb_at_capture` / `bf_pct_at_capture`. Weight and
    // body fat are looked up independently because `body_metrics` rows are
    // sparse — a manual weight entry has weight but no body fat, and a
    // morning HRV reading has neither.
    //
    // Distance is absolute time delta (|timestamp - target|). Ties break by
    // earlier `timestamp`, then by lower `id`; both are deterministic so
    // tests can pin behavior on the boundary.

    /// The `weight_lb` value from the `body_metrics` row closest to `target`,
    /// but only if that row falls within `±within` seconds of `target`.
    /// Returns nil when no row qualifies.
    ///
    /// Rows with `weight_lb IS NULL` are ignored — they cannot contribute a
    /// weight snapshot.
    public func nearestWeightReading(
        to target: Date,
        within: TimeInterval
    ) async throws -> Double? {
        try await nearestReading(
            notNullSQL: "weight_lb IS NOT NULL",
            valueOf: { $0.weightLb },
            to: target,
            within: within
        )
    }

    /// The `body_fat_pct` value from the `body_metrics` row closest to
    /// `target`, but only if that row falls within `±within` seconds of
    /// `target`. Returns nil when no row qualifies.
    ///
    /// Rows with `body_fat_pct IS NULL` are ignored. Note: since weight and
    /// body fat are looked up independently, a single photo can honestly get
    /// a weight snapshot but no body-fat snapshot (e.g. when the nearest
    /// in-window row is a manual weight entry without body fat).
    public func nearestBodyFatReading(
        to target: Date,
        within: TimeInterval
    ) async throws -> Double? {
        try await nearestReading(
            notNullSQL: "body_fat_pct IS NOT NULL",
            valueOf: { $0.bodyFatPct },
            to: target,
            within: within
        )
    }

    // MARK: Private

    /// Nearest-in-time single-column lookup with tie-break.
    ///
    /// Server-side filter (`notNullSQL`) excludes rows that can't contribute
    /// the target value — matches the `.filter(sql: "col IS NOT NULL")`
    /// convention used elsewhere in the module. `valueOf` extracts the
    /// column from the winning row in Swift, so the caller stays type-safe.
    private func nearestReading(
        notNullSQL: String,
        valueOf: @Sendable @escaping (BodyMetric) -> Double?,
        to target: Date,
        within: TimeInterval
    ) async throws -> Double? {
        let earliest = target.addingTimeInterval(-within)
        let latest = target.addingTimeInterval(within)

        // Pull the (typically tiny) in-window candidate set from SQLite,
        // then rank in Swift. SQLite has no first-class abs(datetime diff)
        // that respects our storage encoding, and the candidate set inside
        // ±24hrs is normally 0–3 rows.
        return try await read { db in
            let candidates = try BodyMetric
                .filter(sql: notNullSQL)
                .filter(Column("timestamp") >= earliest)
                .filter(Column("timestamp") <= latest)
                .fetchAll(db)

            guard !candidates.isEmpty else { return nil }

            // Tie-break: smaller delta wins; on equal delta, earlier
            // timestamp wins; on equal timestamp, lower id wins.
            let winner = candidates
                .map { row -> (row: BodyMetric, delta: TimeInterval) in
                    (row, abs(row.timestamp.timeIntervalSince(target)))
                }
                .min { lhs, rhs in
                    if lhs.delta != rhs.delta { return lhs.delta < rhs.delta }
                    if lhs.row.timestamp != rhs.row.timestamp {
                        return lhs.row.timestamp < rhs.row.timestamp
                    }
                    return (lhs.row.id ?? 0) < (rhs.row.id ?? 0)
                }?.row

            return winner.flatMap(valueOf)
        }
    }
}
