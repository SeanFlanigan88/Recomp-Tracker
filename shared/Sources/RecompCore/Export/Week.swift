import Foundation

/// A Monday-through-Sunday week, anchored to a specific date.
///
/// Sean's convention: the week starts Monday, ends Sunday. Reports generated
/// mid-week only cover Monday through today — no look-ahead. `effectiveEnd`
/// captures that: it's the earlier of "end of Sunday" or "end of today."
///
/// Constructed via `Week.containing(_:)`, which snaps any date to its
/// Monday-anchored week.
public struct Week: Sendable, Equatable {

    /// Start of Monday (00:00 local time).
    public let start: Date

    /// End of Sunday (start of next Monday minus 1 nanosecond, effectively).
    /// Callers should use this as an *exclusive* upper bound where possible.
    public let end: Date

    /// The "now" the week was constructed with. Retained so `isPartial` and
    /// `effectiveEnd` are deterministic — a week built at noon Wednesday
    /// stays a Wednesday-clamped week even if the caller holds it into
    /// Thursday. Tests get to control it explicitly.
    public let today: Date

    public var isPartial: Bool {
        today < end
    }

    /// The end date the export should actually cover: today's end-of-day
    /// on a partial week, or end-of-Sunday on a completed one.
    ///
    /// Returned as an *inclusive* last-moment so callers can iterate
    /// `[start, effectiveEnd]` with `<=` and land on exactly 7 days for a
    /// completed week. `week.end` from Calendar's `dateInterval` is the
    /// *exclusive* start of the next Monday, which would cause a
    /// one-day overshoot if used directly.
    public var effectiveEnd: Date {
        let endOfSunday = end.addingTimeInterval(-1)
        return min(endOfDay(for: today), endOfSunday)
    }

    // MARK: - Construction

    public static func containing(
        _ date: Date,
        now: Date = Date(),
        calendar: Calendar = .mondayFirst
    ) -> Week {
        // dateInterval(of: .weekOfYear, ...) returns [start-of-week,
        // start-of-next-week). With firstWeekday = 2 (Monday), start is
        // Monday 00:00.
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: date) else {
            // Degenerate fallback — should never fire for valid Gregorian
            // dates. Return a zero-length week anchored on the input.
            return Week(start: date, end: date, today: now)
        }
        return Week(
            start: interval.start,
            end: interval.end,   // exclusive Monday-of-next-week
            today: now
        )
    }

    // MARK: - Formatting

    /// The Monday date rendered as `yyyy-MM-dd` for use in folder names.
    public var startDateSlug: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: start)
    }

    // MARK: - Private

    private func endOfDay(for date: Date) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone.current
        let sod = cal.startOfDay(for: date)
        return cal.date(byAdding: DateComponents(day: 1, second: -1), to: sod) ?? date
    }
}

// MARK: - Calendar helper

public extension Calendar {

    /// Gregorian calendar with Monday as the first day of the week. Matches
    /// Sean's convention for weekly rollups.
    static var mondayFirst: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone.current
        cal.firstWeekday = 2 // Monday
        return cal
    }
}
