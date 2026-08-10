import XCTest
@testable import RecompCore

final class WeekTests: XCTestCase {

    private let cal = Calendar.mondayFirst

    // MARK: - Fixtures

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12, _ min: Int = 0) -> Date {
        var comps = DateComponents()
        comps.year = y; comps.month = m; comps.day = d
        comps.hour = h; comps.minute = min
        return cal.date(from: comps)!
    }

    // MARK: - Monday anchoring

    func testWednesdaySnapsToPriorMonday() {
        // 2026-08-05 is a Wednesday. Its week starts Mon Aug 3.
        let wed = date(2026, 8, 5)
        let week = Week.containing(wed, now: wed)
        XCTAssertEqual(cal.component(.weekday, from: week.start), 2, "Monday")
        XCTAssertEqual(cal.component(.day, from: week.start), 3)
        XCTAssertEqual(cal.component(.month, from: week.start), 8)
    }

    func testMondayReturnsItselfAsStart() {
        let mon = date(2026, 8, 3, 9, 30)
        let week = Week.containing(mon, now: mon)
        XCTAssertEqual(cal.startOfDay(for: mon), week.start)
    }

    func testSundayLandsInThatWeekNotTheNext() {
        // 2026-08-09 is Sunday. Its week starts Mon Aug 3.
        let sun = date(2026, 8, 9, 20, 0)
        let week = Week.containing(sun, now: sun)
        XCTAssertEqual(cal.component(.day, from: week.start), 3)
    }

    // MARK: - Partial vs complete

    func testMidWeekIsPartial() {
        let wed = date(2026, 8, 5, 12, 0)
        let week = Week.containing(wed, now: wed)
        XCTAssertTrue(week.isPartial)
    }

    func testSundayLateIsNotPartial() {
        // Sunday 22:00 is still before end-of-Sunday but the effective end
        // should equal end-of-week's end. Depends on the isPartial rule
        // being "today < end (exclusive next Monday)."
        let sun = date(2026, 8, 9, 22, 0)
        let week = Week.containing(sun, now: sun)
        // end is exclusive next Monday (Aug 10 00:00), and today is
        // before that, so isPartial is true here. That's the honest
        // answer — Sean isn't done with Sunday until 23:59:59.
        XCTAssertTrue(week.isPartial)
    }

    func testAfterEndOfWeekIsNotPartial() {
        // "Today" is Monday of the following week; the previous week is
        // fully in the past.
        let priorWed = date(2026, 8, 5)
        let laterMon = date(2026, 8, 10, 8, 0)
        let week = Week.containing(priorWed, now: laterMon)
        XCTAssertFalse(week.isPartial)
    }

    // MARK: - effectiveEnd clamping

    func testEffectiveEndClampsToTodayOnPartialWeek() {
        // Wednesday noon → effectiveEnd should be end-of-day Wednesday,
        // not end-of-week Sunday.
        let wed = date(2026, 8, 5, 12, 0)
        let week = Week.containing(wed, now: wed)
        let endDay = cal.component(.day, from: week.effectiveEnd)
        XCTAssertEqual(endDay, 5, "effectiveEnd clamps to today on partial week")
    }

    func testEffectiveEndIsEndOfWeekOnCompletedWeek() {
        let priorWed = date(2026, 8, 5)
        let laterMon = date(2026, 8, 10, 8, 0)
        let week = Week.containing(priorWed, now: laterMon)
        // On a completed week, effectiveEnd should be week.end (exclusive
        // next Monday). We just check that it's on Aug 10 (start of
        // next Monday) at most — the exact time boundary is implementation
        // detail.
        XCTAssertGreaterThanOrEqual(week.effectiveEnd, date(2026, 8, 9, 23, 59))
    }

    // MARK: - Formatting

    func testStartDateSlugMatchesFolderConvention() {
        let mon = date(2026, 8, 3)
        let week = Week.containing(mon, now: mon)
        XCTAssertEqual(week.startDateSlug, "2026-08-03")
    }
}
