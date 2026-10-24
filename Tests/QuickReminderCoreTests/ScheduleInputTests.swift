import Foundation
import Testing

@testable import QuickReminderCore

/// `now` = Friday 23 Oct 2026, 10:00 Europe/Prague.
struct ScheduleInputTests {
    private let now = prague(2026, 10, 23, 10, 0)

    private func resolve(_ text: String, at now: Date? = nil) -> String {
        switch ScheduleInput.resolve(text, now: now ?? self.now, calendar: pragueCalendar) {
        case .empty: return "empty"
        case .invalid: return "invalid"
        case let .date(date): return pragueString(date)
        }
    }

    @Test(arguments: [
        ("zítra 14:00", "2026-10-24 14:00"),
        ("zitra 14:00", "2026-10-24 14:00"),
        ("next fri 9am", "2026-10-30 09:00"),
        ("fri 2pm", "2026-10-30 14:00"),
        ("sat", "2026-10-24 09:00"),
        ("v pátek", "2026-10-30 09:00"),
        ("next week", "2026-10-26 09:00"),
        ("tonight", "2026-10-23 20:00"),
        ("14", "2026-10-23 14:00"),
        ("3", "2026-10-23 15:00"),
        ("930", "2026-10-24 09:30"),          // 9:30 already past → tomorrow
        ("1430", "2026-10-23 14:30"),
        ("14:30", "2026-10-23 14:30"),
        ("14.30", "2026-10-23 14:30"),
        ("+90m", "2026-10-23 11:30"),
        ("+2h", "2026-10-23 12:00"),
        ("+2 H", "2026-10-23 12:00"),
        ("+3d", "2026-10-26 09:00"),
        ("15.11.", "2026-11-15 09:00"),
        ("  zítra 14:00  ", "2026-10-24 14:00"),
    ])
    func valid(text: String, expected: String) {
        #expect(resolve(text) == expected, "\(text)")
    }

    @Test func offsetKeepsMinutes() {
        #expect(resolve("za 2 hodiny", at: prague(2026, 10, 23, 10, 17)) == "2026-10-23 12:17")
    }

    @Test func bareHourAlreadyPastRollsToTomorrow() {
        #expect(resolve("14", at: prague(2026, 10, 23, 15, 0)) == "2026-10-24 14:00")
    }

    /// "today" after 9:00 → next :00/:30 at least 15 min ahead.
    @Test func todayAfterNineIsNextSlot() {
        #expect(resolve("today", at: prague(2026, 10, 23, 10, 5)) == "2026-10-23 10:30")
        #expect(resolve("dnes", at: prague(2026, 10, 23, 8, 0)) == "2026-10-23 09:00")
    }

    @Test(arguments: ["buy milk tomorrow", "2500", "25:00", "14:75", "abc", "tomorrow please", "+5y"])
    func invalid(text: String) {
        #expect(resolve(text) == "invalid", "\(text)")
    }

    @Test(arguments: ["", "   ", "\n\t"])
    func empty(text: String) {
        #expect(resolve(text) == "empty")
    }

    /// The shorthands live only here; the title parser still ignores bare numbers.
    @Test func leniencyStaysOutOfTheTitleParser() {
        #expect(NaturalDateParser.parse("buy 2 apples", now: now, calendar: pragueCalendar) == nil)
        #expect(NaturalDateParser.parse("1430", now: now, calendar: pragueCalendar) == nil)
        #expect(NaturalDateParser.parse("+2h", now: now, calendar: pragueCalendar) == nil)
    }
}
