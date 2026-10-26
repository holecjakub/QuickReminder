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

    @Test func dayTemplateByDistance() {
        let now = prague(2026, 10, 24, 17, 39)   // Saturday
        func template(_ date: Date, spoken: Bool = false) -> String? {
            DatePreset.dayTemplate(for: date, now: now, calendar: pragueCalendar, spoken: spoken)
        }
        #expect(template(prague(2026, 10, 24, 19, 0)) == nil)               // today: time only
        #expect(template(prague(2026, 10, 25, 9, 0)) == "EEE")
        #expect(template(prague(2026, 10, 30, 9, 0)) == "EEE")              // 6 days
        #expect(template(prague(2026, 10, 31, 9, 0)) == "d MMM")            // 7 days
        #expect(template(prague(2026, 10, 31, 9, 0), spoken: true) == "EEEE d MMMM")
        #expect(template(prague(2026, 10, 23, 9, 0)) == "d MMM")            // past day
    }

    /// Friday 23 Oct: Tomorrow and This Weekend are both Sat 9:00.
    @Test func onlyOnePresetIsHighlighted() {
        let now = prague(2026, 10, 23, 10, 0)
        let saturday = prague(2026, 10, 24, 9, 0)
        func pick(_ preset: DatePreset) -> PresetPick { PresetPick(preset: preset, date: DatePreset.date(for: preset, now: now, calendar: pragueCalendar)) }
        #expect(DatePreset.highlighted(for: saturday, picked: nil, now: now, calendar: pragueCalendar) == .tomorrow,
                "typed / manual: the first match in display order")
        #expect(DatePreset.highlighted(for: saturday, picked: pick(.weekend), now: now, calendar: pragueCalendar) == .weekend,
                "the picked one, not both")
        #expect(DatePreset.highlighted(for: saturday, picked: pick(.tomorrow), now: now, calendar: pragueCalendar) == .tomorrow)
        #expect(DatePreset.highlighted(for: prague(2026, 10, 24, 14, 0), picked: pick(.weekend), now: now, calendar: pragueCalendar) == nil,
                "a date no preset lands on highlights nothing; the stale pick is ignored")
        #expect(DatePreset.highlighted(for: prague(2026, 10, 26, 9, 0), picked: pick(.weekend), now: now, calendar: pragueCalendar) == .nextWeek)
    }
}

/// The formatter the menu, the preset cards and the Set button actually use.
@MainActor
struct PresetDetailTests {
    private let cs = SuggestionDateFormatter(locale: Locale(identifier: "cs_CZ"), calendar: pragueCalendar)
    private let en = SuggestionDateFormatter(locale: Locale(identifier: "en_US"), calendar: pragueCalendar)

    private func detail(_ formatter: SuggestionDateFormatter, _ preset: DatePreset, _ now: Date, spoken: Bool = false) -> String {
        plainSpaces(formatter.presetDetail(DatePreset.date(for: preset, now: now, calendar: pragueCalendar), now: now, spoken: spoken))
    }

    @Test func followsLocale() {
        let now = prague(2026, 10, 19, 10, 0)
        #expect(detail(cs, .weekend, now) == "so 9:00")
        #expect(detail(en, .weekend, now) == "Sat 9:00 AM")
        // Lands today → time only.
        #expect(detail(cs, .evening, now) == "19:00")
        #expect(detail(en, .evening, now) == "7:00 PM")
    }

    /// Saturday 24 Oct: Tomorrow (Sun 25) and Next Month (Sun 1 Nov) must not both read
    /// "Sun 9:00", and Next Weekend (Sat 31) must not read "Sat 9:00" (today).
    @Test func aWeekOrMoreAheadShowsTheDate() {
        let now = prague(2026, 10, 24, 17, 39)
        #expect(detail(en, .tomorrow, now) == "Sun 9:00 AM")
        #expect(detail(en, .nextMonth, now) == "Nov 1 9:00 AM")
        #expect(detail(en, .weekend, now) == "Oct 31 9:00 AM")
        #expect(detail(cs, .tomorrow, now) == "ne 9:00")
        #expect(detail(cs, .nextMonth, now) != detail(cs, .tomorrow, now))
        #expect(detail(cs, .nextMonth, now) == "1. 11. 9:00")
        #expect(!detail(cs, .weekend, now).hasPrefix("so"))
        #expect(detail(en, .nextMonth, now, spoken: true) == "Sunday, November 1 9:00 AM")
        #expect(detail(en, .tomorrow, now, spoken: true) == "Sunday 9:00 AM")
    }

    /// English UI, Czech region (`en_US@rg=czzzzz`, the author's setup): no English "at" glued
    /// into Czech-style dates, and the time reads like the chips ("9:00", not "09:00").
    @Test func mixedLocaleReadsAsOneFormat() {
        let mixed = SuggestionDateFormatter(locale: Locale(identifier: "en_US@rg=czzzzz"), calendar: pragueCalendar)
        let now = prague(2026, 10, 23, 10, 0)
        let saturday = prague(2026, 10, 24, 9, 0)
        #expect(plainSpaces(mixed.presetDetail(saturday, now: now)) == "Sat " + plainSpaces(mixed.time(from: saturday)))
        #expect(!mixed.presetDetail(prague(2026, 11, 1, 9, 0), now: now).contains(" at "))
        #expect(!mixed.dayAndTime(saturday).contains(" at "))
        #expect(plainSpaces(mixed.dayAndTime(saturday)).hasSuffix(" " + plainSpaces(mixed.time(from: saturday))))
        #expect(plainSpaces(cs.dayAndTime(saturday)) == "sobota 24. října 9:00")
        #expect(plainSpaces(en.dayAndTime(saturday)) == "Saturday, October 24 9:00 AM")
    }

    @Test func cacheIsPerLocaleAndCanBeDropped() {
        let now = prague(2026, 10, 19, 10, 0)
        #expect(detail(cs, .evening, now) != detail(en, .evening, now))
        SuggestionDateFormatter.invalidateCache()
        #expect(SuggestionDateFormatter.cachedFormatterCount == 0)
        #expect(detail(en, .evening, now) == "7:00 PM")
    }
}
