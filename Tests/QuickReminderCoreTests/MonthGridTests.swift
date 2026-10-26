import Foundation
import Testing

@testable import QuickReminderCore

/// The in-notch month grid model: always six weeks, locale first weekday, keyboard movement.
struct MonthGridTests {
    /// cs_CZ weeks start on Monday.
    @Test func octoberStartsOnThursdayInAMondayFirstLocale() {
        let cells = MonthGrid.cells(for: prague(2026, 10, 23, 10), calendar: pragueCalendar)
        #expect(cells.count == 42)
        #expect(cells[0..<3].allSatisfy { $0 == nil }, "Mon–Wed blank")
        #expect(cells[3] == prague(2026, 10, 1))
        #expect(cells[3 + 30] == prague(2026, 10, 31))
        #expect(cells[34...].allSatisfy { $0 == nil })
        #expect(cells.compactMap { $0 }.count == 31)
    }

    @Test func sundayFirstLocaleShiftsTheColumns() {
        var us = pragueCalendar
        us.locale = Locale(identifier: "en_US")
        us.firstWeekday = 1
        let cells = MonthGrid.cells(for: prague(2026, 10, 5), calendar: us)
        #expect(cells[4] == prague(2026, 10, 1), "Thu is the 5th column when weeks start on Sunday")
        #expect(MonthGrid.weekdaySymbols(calendar: us).first == "S")
        #expect(MonthGrid.weekdaySymbols(calendar: pragueCalendar).count == 7)
    }

    /// A 31-day month starting on Sunday (Monday-first) needs all six rows.
    @Test func sixRowsAlwaysFit() {
        let cells = MonthGrid.cells(for: prague(2026, 3, 10), calendar: pragueCalendar)   // 1 Mar 2026 = Sunday
        #expect(cells[6] == prague(2026, 3, 1))
        #expect(cells[36] == prague(2026, 3, 31), "31st lands in the sixth row")
    }

    @Test func arrowMovementKeepsTheTimeAndNeverEntersThePast() {
        let now = prague(2026, 10, 23, 10)
        let draft = prague(2026, 10, 24, 14, 30)
        #expect(MonthGrid.moving(draft, byDays: 7, earliest: now, calendar: pragueCalendar) == prague(2026, 10, 31, 14, 30))
        #expect(MonthGrid.moving(draft, byDays: -1, earliest: now, calendar: pragueCalendar) == prague(2026, 10, 23, 14, 30),
                "today is selectable")
        #expect(MonthGrid.moving(draft, byDays: -7, earliest: now, calendar: pragueCalendar) == draft, "past: stays put")
    }

    @Test func movementCrossesDSTOnWallClockTime() {
        // DST ends Sun 25 Oct 2026 in Prague; 9:00 stays 9:00.
        let draft = prague(2026, 10, 24, 9)
        #expect(pragueString(MonthGrid.moving(draft, byDays: 2, earliest: draft, calendar: pragueCalendar)) == "2026-10-26 09:00")
    }

    @Test func paging() {
        let now = prague(2026, 10, 23, 10)
        #expect(MonthGrid.shiftMonth(prague(2026, 10, 31), by: 1, calendar: pragueCalendar) == prague(2026, 11, 1))
        #expect(MonthGrid.shiftMonth(prague(2026, 12, 15), by: 1, calendar: pragueCalendar) == prague(2027, 1, 1))
        #expect(!MonthGrid.canGoBack(from: prague(2026, 10, 1), now: now, calendar: pragueCalendar))
        #expect(MonthGrid.canGoBack(from: prague(2026, 11, 1), now: now, calendar: pragueCalendar))
        #expect(MonthGrid.isSelectable(prague(2026, 10, 23, 0), now: now, calendar: pragueCalendar))
        #expect(!MonthGrid.isSelectable(prague(2026, 10, 22, 23, 59), now: now, calendar: pragueCalendar))
    }
}
