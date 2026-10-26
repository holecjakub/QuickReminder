import Foundation
import Testing

@testable import QuickReminderCore

struct ScheduleDefaultsTests {

    @Test(arguments: [
        // now → expected slot (≥ 15 min ahead, on :00 / :30)
        ((14, 0), "2026-10-20 14:30"),
        ((14, 12), "2026-10-20 14:30"),
        ((14, 15), "2026-10-20 14:30"),
        ((14, 20), "2026-10-20 15:00"),
        ((23, 50), "2026-10-21 00:30"),
    ])
    func nextSlot(now: (Int, Int), expected: String) {
        let slot = ScheduleDefaults.nextSlot(after: prague(2026, 10, 20, now.0, now.1), calendar: pragueCalendar)
        #expect(pragueString(slot) == expected)
    }

    @Test func nextSlotIgnoresSeconds() {
        let now = prague(2026, 10, 20, 14, 15).addingTimeInterval(1)   // 14:15:01 → lead ends 14:30:01
        #expect(pragueString(ScheduleDefaults.nextSlot(after: now, calendar: pragueCalendar)) == "2026-10-20 15:00")
    }

    @Test func resolveDayOnlyFutureDayIsNine() {
        let date = ScheduleDefaults.resolveDayOnly(prague(2026, 10, 23), now: prague(2026, 10, 20, 15, 0), calendar: pragueCalendar)
        #expect(pragueString(date) == "2026-10-23 09:00")
    }

    @Test(arguments: [
        ((8, 0), "2026-10-20 09:00"),
        ((10, 5), "2026-10-20 10:30"),
        ((23, 40), "2026-10-21 09:00"),
    ])
    func resolveDayOnlyToday(now: (Int, Int), expected: String) {
        let date = ScheduleDefaults.resolveDayOnly(prague(2026, 10, 20), now: prague(2026, 10, 20, now.0, now.1), calendar: pragueCalendar)
        #expect(pragueString(date) == expected)
    }

    @Test func composeKeepsDayAndTime() {
        let date = ScheduleDefaults.compose(day: prague(2026, 11, 3, 18, 45), time: prague(2026, 10, 20, 7, 15), calendar: pragueCalendar)
        #expect(pragueString(date) == "2026-11-03 07:15")
    }

    /// Spring forward, 29 Mar 2026: 02:00–03:00 does not exist; 02:30 shifts by the gap.
    @Test func composeSkippedTimeMovesForward() {
        let date = ScheduleDefaults.compose(day: prague(2026, 3, 29), time: prague(2026, 3, 28, 2, 30), calendar: pragueCalendar)
        #expect(pragueString(date) == "2026-03-29 03:30")
    }

    /// Fall back, 25 Oct 2026: 02:30 happens twice; the first (CEST, UTC+2) occurrence wins.
    @Test func composeRepeatedTimeTakesFirst() {
        let date = ScheduleDefaults.compose(day: prague(2026, 10, 25), time: prague(2026, 10, 24, 2, 30), calendar: pragueCalendar)
        #expect(pragueString(date) == "2026-10-25 02:30")
        #expect(pragueCalendar.timeZone.secondsFromGMT(for: date) == 2 * 3600)
    }

    @Test func appClockParsesLocalAndISO() {
        let zone = TimeZone(identifier: "Europe/Prague")!
        #expect(AppClock.parse("2026-10-23T10:00", timeZone: zone) == prague(2026, 10, 23, 10, 0))
        #expect(AppClock.parse("2026-10-23T08:00:00Z") == prague(2026, 10, 23, 10, 0))
        #expect(AppClock.parse("tomorrow") == nil)
    }
}
