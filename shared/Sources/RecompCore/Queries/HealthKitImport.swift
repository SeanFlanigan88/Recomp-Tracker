import Foundation
import GRDB

extension AppDatabase {

    /// Insert `body_metrics` rows for HK samples not already imported.
    ///
    /// Dedup key is `healthkit_uuid` — a partial unique index on that column
    /// (M003) is the safety net, but we also check-then-insert per sample so
    /// we can return an accurate count of new rows.
    ///
    /// Each HK sample lands in its own row with `source = .healthkit` and
    /// exactly one metric column populated. This matches how HealthKit itself
    /// stores samples — one quantity type per sample, even when a smart scale
    /// publishes weight + body-fat + lean mass in the same weigh-in event.
    /// Grouping samples by weigh-in event is a future concern.
    @discardableResult
    public func importHealthKitSamples(
        _ samples: [QuantitySampleImport]
    ) async throws -> Int {
        guard !samples.isEmpty else { return 0 }

        var inserted = 0
        try await write { db in
            for s in samples {
                let uuidString = s.uuid.uuidString

                let alreadyImported = try Int.fetchOne(
                    db,
                    sql: "SELECT 1 FROM body_metrics WHERE healthkit_uuid = ? LIMIT 1",
                    arguments: [uuidString]
                ) != nil
                if alreadyImported { continue }

                var metric = BodyMetric(
                    timestamp: s.startDate,
                    source: .healthkit,
                    healthkitUuid: uuidString
                )
                switch s.kind {
                case .weightLb:   metric.weightLb = s.value
                case .bodyFatPct: metric.bodyFatPct = s.value
                case .leanMassLb: metric.leanMassLb = s.value
                case .hrvMs:      metric.hrvMs = s.value
                case .restingHr:  metric.restingHr = Int(s.value.rounded())
                }
                try metric.insert(db)
                inserted += 1
            }
        }
        return inserted
    }

    /// The weight to show on the Log tab for a given day, across sources.
    ///
    /// Rule: if a manual weight exists for that day, it wins (Sean's own
    /// entry overrides HK — he types in the number he wants to see for that
    /// day). Otherwise, the latest HK-sourced weight for the day. Nil if
    /// nothing exists.
    ///
    /// Rows without a weight value (e.g., an HRV-only HK sample) are ignored
    /// even if they exist on the same day.
    public func todaysDisplayWeight(
        on date: Date,
        calendar: Calendar = .current
    ) async throws -> Double? {
        let day = calendar.startOfDay(for: date)
        let nextDay = calendar.date(byAdding: .day, value: 1, to: day)!

        return try await read { db in
            // Manual first.
            if let manual = try BodyMetric
                .filter(Column("source") == BodyMetric.Source.manual.rawValue)
                .filter(Column("timestamp") >= day)
                .filter(Column("timestamp") < nextDay)
                .filter(sql: "weight_lb IS NOT NULL")
                .order(Column("timestamp").desc)
                .fetchOne(db),
               let w = manual.weightLb
            {
                return w
            }

            // Fall back to any source (only HK reaches here in practice).
            if let any = try BodyMetric
                .filter(Column("timestamp") >= day)
                .filter(Column("timestamp") < nextDay)
                .filter(sql: "weight_lb IS NOT NULL")
                .order(Column("timestamp").desc)
                .fetchOne(db),
               let w = any.weightLb
            {
                return w
            }

            return nil
        }
    }
}
