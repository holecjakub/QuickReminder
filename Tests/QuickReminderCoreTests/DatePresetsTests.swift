import Foundation
import Testing

@testable import QuickReminderCore

struct DatePresetsTests {

    private func date(_ preset: DatePreset, _ now: Date) -> String {
        pragueString(DatePreset.date(for: preset, now: now, calendar: pragueCalendar))
    }

    private func title(_ preset: DatePreset, _ now: Date) -> String {
        DatePreset.title(for: preset, now: now, calendar: pragueCalendar)
    }

    @Test func mondayMorningResolvesAllSix() {
        let now = prague(2026, 10, 19, 10, 0)
        #expect(date(.inOneHour, now) == "2026-10-19 11:00")
        #expect(date(.evening, now) == "2026-10-19 19:00")
        #expect(date(.tomorrow, now) == "2026-10-20 09:00")
        #expect(date(.weekend, now) == "2026-10-24 09:00")
        #expect(date(.nextWeek, now) == "2026-10-26 09:00")
        #expect(date(.nextMonth, now) == "2026-11-01 09:00")
        #expect(title(.evening, now) == "This Evening")
        #expect(title(.weekend, now) == "This Weekend")
    }

    @Test func inOneHourKeepsMinutes() {
        #expect(date(.inOneHour, prague(2026, 10, 19, 14, 37)) == "2026-10-19 15:37")
    }

    @Test func eveningSwitchesAtHalfPastSix() {
        let before = prague(2026, 10, 19, 18, 29)
        let after = prague(2026, 10, 19, 18, 30)
        #expect(date(.evening, before) == "2026-10-19 19:00")
        #expect(title(.evening, before) == "This Evening")
        #expect(date(.evening, after) == "2026-10-20 19:00")
        #expect(title(.evening, after) == "Tomorrow Evening")
    }

    @Test func fridayEveningWeekendEqualsTomorrowBothListed() {
        let now = prague(2026, 10, 23, 17, 0)
        #expect(date(.weekend, now) == "2026-10-24 09:00")
        #expect(date(.weekend, now) == date(.tomorrow, now))
        #expect(DatePreset.allCases.count == 6)
    }

    @Test(arguments: [24, 25])
    func onTheWeekendItIsNextWeekend(day: Int) {
        let now = prague(2026, 10, day, 11, 0)
        #expect(title(.weekend, now) == "Next Weekend")
        let expected = DatePreset.nextWeekday(7, after: now, calendar: pragueCalendar)
        #expect(date(.weekend, now) == pragueString(ScheduleDefaults.at(hour: 9, minute: 0, on: expected, calendar: pragueCalendar)))
        #expect(date(.weekend, now) == "2026-10-31 09:00")
    }

    @Test func sundayNextWeekIsTomorrow() {
        #expect(date(.nextWeek, prague(2026, 10, 25, 11, 0)) == "2026-10-26 09:00")
    }

    @Test func nextMonthRollsOver() {
        #expect(date(.nextMonth, prague(2026, 1, 31, 12, 0)) == "2026-02-01 09:00")
        #expect(date(.nextMonth, prague(2026, 12, 15, 12, 0)) == "2027-01-01 09:00")
    }

    @Test func detailFollowsLocale() {
        let now = prague(2026, 10, 19, 10, 0)
        let cs = Locale(identifier: "cs_CZ"), en = Locale(identifier: "en_US")
        #expect(plainSpaces(DatePreset.detail(for: .weekend, now: now, calendar: pragueCalendar, locale: cs)) == "so 9:00")
        #expect(plainSpaces(DatePreset.detail(for: .weekend, now: now, calendar: pragueCalendar, locale: en)) == "Sat 9:00 AM")
        // Lands today → time only.
        #expect(plainSpaces(DatePreset.detail(for: .evening, now: now, calendar: pragueCalendar, locale: cs)) == "19:00")
        #expect(plainSpaces(DatePreset.detail(for: .evening, now: now, calendar: pragueCalendar, locale: en)) == "7:00 PM")
    }

    @Test func menuTitlesKeepTheRemindMeRows() {
        let now = prague(2026, 10, 19, 10, 0)
        #expect(DatePreset.menuTitle(for: .inOneHour, now: now, calendar: pragueCalendar) == "Remind Me In 1 Hour")
        #expect(DatePreset.menuTitle(for: .tomorrow, now: now, calendar: pragueCalendar) == "Remind Me Tomorrow")
        #expect(DatePreset.menuTitle(for: .nextWeek, now: now, calendar: pragueCalendar) == "Next Week")
    }

    /// A typed phrase and its preset can never disagree: both go through the same weekday
    /// helper and the same day-only rule.
    @Test(arguments: [
        ("next week", DatePreset.nextWeek),
        ("weekend", DatePreset.weekend),
        ("this weekend", DatePreset.weekend),
        ("tomorrow", DatePreset.tomorrow),
        ("zítra", DatePreset.tomorrow),
        ("příští týden", DatePreset.nextWeek),
        ("next month", DatePreset.nextMonth),
    ])
    func parity(phrase: String, preset: DatePreset) throws {
        for now in [prague(2026, 10, 19, 10, 0), prague(2026, 10, 23, 17, 0), prague(2026, 10, 25, 11, 0)] {
            let parsed = try #require(NaturalDateParser.parse(phrase, now: now, calendar: pragueCalendar))
            #expect(!parsed.hasTime)
            let typed = ScheduleDefaults.resolveDayOnly(parsed.date, now: now, calendar: pragueCalendar)
            #expect(pragueString(typed) == date(preset, now), "\(phrase) at \(pragueString(now))")
        }
    }

    /// "tonight" is the parser's 20:00; the Evening preset is 19:00 (documented difference).
    @Test func tonightVersusEvening() throws {
        let now = prague(2026, 10, 19, 10, 0)
        let tonight = try #require(NaturalDateParser.parse("tonight", now: now, calendar: pragueCalendar))
        #expect(pragueString(tonight.date) == "2026-10-19 20:00")
        #expect(date(.evening, now) == "2026-10-19 19:00")
    }
}
