import Foundation
import Testing

@testable import QuickReminderCore

// MARK: - Fixtures

/// `now` is pinned to Friday 2026-09-18 10:00 local time so every case is deterministic.
/// Ported 1:1 from the old `Tests/NaturalDateParserTests.swift` assertion runner.

private let ndpCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone.current
    return calendar
}()

private func ndpDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
    var components = DateComponents()
    components.year = year
    components.month = month
    components.day = day
    components.hour = hour
    components.minute = minute
    components.second = 0
    return ndpCalendar.date(from: components)!
}

private let ndpNow = ndpDate(2026, 9, 18, 10, 0)

private func ndpFormat(_ value: Date) -> String {
    let formatter = DateFormatter()
    formatter.calendar = ndpCalendar
    formatter.timeZone = ndpCalendar.timeZone
    formatter.dateFormat = "yyyy-MM-dd HH:mm"
    return formatter.string(from: value)
}

/// A phrase expected to resolve to `year`/`month`/`day`/`hour`/`minute`, with the given
/// `hasTime`; `stripped` (nil = don't care) is what `removingMatch` should leave behind.
struct DateCase: Sendable, CustomTestStringConvertible {
    let text: String
    let year: Int
    let month: Int
    let day: Int
    let hour: Int
    let minute: Int
    let hasTime: Bool
    let stripped: String?

    init(_ text: String, _ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0,
         hasTime: Bool, stripped: String? = nil) {
        self.text = text
        self.year = year
        self.month = month
        self.day = day
        self.hour = hour
        self.minute = minute
        self.hasTime = hasTime
        self.stripped = stripped
    }

    var testDescription: String { "\"\(text)\"" }
}

/// A phrase expected NOT to match.
struct NilCase: Sendable, CustomTestStringConvertible {
    let text: String
    var testDescription: String { "\"\(text)\"" }
}

private func verify(_ c: DateCase) {
    let expected = ndpDate(c.year, c.month, c.day, c.hour, c.minute)
    guard let suggestion = NaturalDateParser.parse(c.text, now: ndpNow, calendar: ndpCalendar) else {
        Issue.record("\"\(c.text)\" should parse, got nil")
        return
    }
    #expect(suggestion.date == expected,
            "\"\(c.text)\" → \(ndpFormat(expected)) (got \(ndpFormat(suggestion.date)), matched \"\(suggestion.matchedText)\")")
    #expect(suggestion.hasTime == c.hasTime, "\"\(c.text)\" hasTime == \(c.hasTime)")
    if let stripped = c.stripped {
        let rest = NaturalDateParser.removingMatch(from: c.text, suggestion: suggestion)
        #expect(rest == stripped, "\"\(c.text)\" strips to \"\(stripped)\" (got \"\(rest)\")")
    }
}

private func verifyNil(_ text: String) {
    let suggestion = NaturalDateParser.parse(text, now: ndpNow, calendar: ndpCalendar)
    #expect(suggestion == nil, "\"\(text)\" should not match (got \(suggestion.map { "\"\($0.matchedText)\"" } ?? "nil"))")
}

// MARK: - Suite

struct NaturalDateParserTests {

    // MARK: day + time

    @Test(arguments: [
        DateCase("Buy milk tomorrow at 2pm", 2026, 9, 19, 14, 0, hasTime: true, stripped: "Buy milk"),
        DateCase("koupit mléko zítra ve 14:00", 2026, 9, 19, 14, 0, hasTime: true, stripped: "koupit mléko"),
        DateCase("zitra v 8 rano", 2026, 9, 19, 8, 0, hasTime: true, stripped: ""),
        DateCase("zítra v 8 ráno", 2026, 9, 19, 8, 0, hasTime: true),
        DateCase("Call mom tomorrow 2pm", 2026, 9, 19, 14, 0, hasTime: true, stripped: "Call mom"),
        DateCase("at 2pm tomorrow", 2026, 9, 19, 14, 0, hasTime: true, stripped: ""),
        DateCase("schůzka v úterý ráno", 2026, 9, 22, 9, 0, hasTime: true, stripped: "schůzka"),
        DateCase("call mom tonight", 2026, 9, 18, 20, 0, hasTime: true, stripped: "call mom"),
    ])
    func dayAndTime(_ c: DateCase) { verify(c) }

    // MARK: relative days

    @Test(arguments: [
        DateCase("zavolat mámě zítra", 2026, 9, 19, hasTime: false, stripped: "zavolat mámě"),
        DateCase("tmrw", 2026, 9, 19, hasTime: false),
        DateCase("day after tomorrow", 2026, 9, 20, hasTime: false),
        DateCase("pozítří", 2026, 9, 20, hasTime: false),
        DateCase("dnes", 2026, 9, 18, hasTime: false),
        DateCase("dneska", 2026, 9, 18, hasTime: false),
        DateCase("next week", 2026, 9, 21, hasTime: false),
        DateCase("příští týden", 2026, 9, 21, hasTime: false),
        DateCase("next month", 2026, 10, 1, hasTime: false),
        DateCase("this weekend", 2026, 9, 19, hasTime: false),
        DateCase("o víkendu", 2026, 9, 19, hasTime: false),
    ])
    func relativeDays(_ c: DateCase) { verify(c) }

    // MARK: weekdays

    @Test(arguments: [
        DateCase("meeting on friday", 2026, 9, 25, hasTime: false, stripped: "meeting"),
        DateCase("next friday", 2026, 9, 25, hasTime: false),
        DateCase("MONDAY", 2026, 9, 21, hasTime: false),
        DateCase("v pondělí", 2026, 9, 21, hasTime: false, stripped: ""),
        DateCase("ve středu", 2026, 9, 23, hasTime: false),
        DateCase("příští pátek", 2026, 9, 25, hasTime: false),
        DateCase("lunch on sat", 2026, 9, 19, hasTime: false, stripped: "lunch"),
    ])
    func weekdays(_ c: DateCase) { verify(c) }

    // MARK: explicit dates

    @Test(arguments: [
        DateCase("12. března", 2027, 3, 12, hasTime: false),
        DateCase("March 12", 2027, 3, 12, hasTime: false),
        DateCase("Mar 12", 2027, 3, 12, hasTime: false),
        DateCase("12 March", 2027, 3, 12, hasTime: false),
        DateCase("12. 3.", 2027, 3, 12, hasTime: false),
        DateCase("12.3.2027", 2027, 3, 12, hasTime: false),
        DateCase("Buy\u{00A0}milk tomorrow", 2026, 9, 19, hasTime: false, stripped: "Buy milk"),
        DateCase("dentist 3/12", 2027, 3, 12, hasTime: false, stripped: "dentist"),
        DateCase("zubař 3.12.", 2026, 12, 3, hasTime: false, stripped: "zubař"),
        DateCase("odevzdat do 5. prosince", 2026, 12, 5, hasTime: false),
    ])
    func explicitDates(_ c: DateCase) { verify(c) }

    @Test(arguments: [
        // Explicit past date is never suggested.
        NilCase(text: "12.3.2026"),
        // Bare weekday abbreviations are ordinary words.
        NilCase(text: "I sat on the bench"),
        NilCase(text: "mon amour"),
    ])
    func explicitDateNegatives(_ c: NilCase) { verifyNil(c.text) }

    @Test
    func foldAlignmentAcrossMixedWidthCharacters() {
        // Mixed shrinking/growing folds must not misalign ranges (ŉ → 2 units, e + U+0301 → 1).
        guard let s = NaturalDateParser.parse("ŉ zítra e\u{301}", now: ndpNow, calendar: ndpCalendar) else {
            Issue.record("fold alignment: \"ŉ zítra é\" should parse")
            return
        }
        #expect(s.matchedText == "zítra", "fold alignment: matched \"\(s.matchedText)\"")
    }

    // MARK: times

    @Test(arguments: [
        DateCase("meeting at 14:00", 2026, 9, 18, 14, 0, hasTime: true, stripped: "meeting"),
        DateCase("at 9", 2026, 9, 19, 9, 0, hasTime: true),
        DateCase("noon", 2026, 9, 18, 12, 0, hasTime: true),
        DateCase("midnight", 2026, 9, 19, 0, 0, hasTime: true),
        DateCase("o půlnoci", 2026, 9, 19, 0, 0, hasTime: true),
        DateCase("v poledne", 2026, 9, 18, 12, 0, hasTime: true),
        DateCase("in the morning", 2026, 9, 19, 9, 0, hasTime: true),
        DateCase("večer", 2026, 9, 18, 19, 0, hasTime: true),
        DateCase("odpoledne", 2026, 9, 18, 15, 0, hasTime: true),
        DateCase("ve 2 odpoledne", 2026, 9, 18, 14, 0, hasTime: true),
        DateCase("v půl třetí", 2026, 9, 18, 14, 30, hasTime: true),
        DateCase("ve 14.30", 2026, 9, 18, 14, 30, hasTime: true),
        DateCase("call at 2:30pm", 2026, 9, 18, 14, 30, hasTime: true, stripped: "call"),
    ])
    func times(_ c: DateCase) { verify(c) }

    // MARK: relative offsets

    @Test(arguments: [
        DateCase("in 2 hours", 2026, 9, 18, 12, 0, hasTime: true),
        DateCase("in an hour", 2026, 9, 18, 11, 0, hasTime: true),
        DateCase("in 30 minutes", 2026, 9, 18, 10, 30, hasTime: true),
        DateCase("in 3 days", 2026, 9, 21, hasTime: false),
        DateCase("in a week", 2026, 9, 25, hasTime: false),
        DateCase("za hodinu", 2026, 9, 18, 11, 0, hasTime: true),
        DateCase("za 2 hodiny", 2026, 9, 18, 12, 0, hasTime: true),
        DateCase("za 5 hodin", 2026, 9, 18, 15, 0, hasTime: true),
        DateCase("za 30 minut", 2026, 9, 18, 10, 30, hasTime: true),
        DateCase("za 3 dny", 2026, 9, 21, hasTime: false),
        DateCase("za týden", 2026, 9, 25, hasTime: false),
        DateCase("za 2 týdny", 2026, 10, 2, hasTime: false),
    ])
    func relativeOffsets(_ c: DateCase) { verify(c) }

    // MARK: invalid dates never roll over

    @Test(arguments: [
        NilCase(text: "30.2."),
        NilCase(text: "31. února"),
        NilCase(text: "31. dubna"),
        NilCase(text: "31 April"),
        // A written-out year further than ±10 years away is not a date at all.
        NilCase(text: "12.3.2040"),
    ])
    func invalidDatesNeverRollOverNegatives(_ c: NilCase) { verifyNil(c.text) }

    @Test(arguments: [
        // No year given → walk forward to the next year in which the date actually exists.
        DateCase("29.2.", 2028, 2, 29, hasTime: false),
        // A stray number is not a year: "1000" stays in the title.
        DateCase("12 March 1000 items", 2027, 3, 12, hasTime: false, stripped: "1000 items"),
    ])
    func invalidDatesNeverRollOverPositives(_ c: DateCase) { verify(c) }

    // MARK: sentence-final period after HH.MM

    @Test(arguments: [
        DateCase("ve 14.30.", 2026, 9, 18, 14, 30, hasTime: true, stripped: ""),
        DateCase("meeting at 14.30.", 2026, 9, 18, 14, 30, hasTime: true, stripped: "meeting"),
    ])
    func sentenceFinalPeriodAfterTime(_ c: DateCase) { verify(c) }

    // MARK: English day parts

    @Test(arguments: [
        DateCase("tomorrow evening", 2026, 9, 19, 19, 0, hasTime: true, stripped: ""),
        DateCase("tomorrow morning", 2026, 9, 19, 9, 0, hasTime: true, stripped: ""),
        DateCase("tomorrow night", 2026, 9, 19, 20, 0, hasTime: true, stripped: ""),
        DateCase("call mom tomorrow evening", 2026, 9, 19, 19, 0, hasTime: true, stripped: "call mom"),
        DateCase("friday afternoon", 2026, 9, 25, 15, 0, hasTime: true, stripped: ""),
    ])
    func englishDayParts(_ c: DateCase) { verify(c) }

    // MARK: hour disambiguation with an evening context

    @Test(arguments: [
        DateCase("tonight at 8", 2026, 9, 18, 20, 0, hasTime: true, stripped: ""),
        DateCase("12am", 2026, 9, 19, 0, 0, hasTime: true),
        DateCase("12pm", 2026, 9, 18, 12, 0, hasTime: true),
        // "12 večer" is genuinely ambiguous (noon? midnight?), so 12 is left as written.
        DateCase("v 12 večer", 2026, 9, 18, 12, 0, hasTime: true, stripped: ""),
        DateCase("půl třetí odpoledne", 2026, 9, 18, 14, 30, hasTime: true, stripped: ""),
    ])
    func hourDisambiguationWithEveningContext(_ c: DateCase) { verify(c) }

    // MARK: offset merged with a time

    @Test(arguments: [
        DateCase("in 2 days at 3pm", 2026, 9, 20, 15, 0, hasTime: true, stripped: ""),
        DateCase("za 3 dny v 9 ráno", 2026, 9, 21, 9, 0, hasTime: true, stripped: ""),
    ])
    func offsetMergedWithTime(_ c: DateCase) { verify(c) }

    // MARK: removingMatch keeps real title words

    @Test(arguments: [
        DateCase("Fix this tomorrow", 2026, 9, 19, hasTime: false, stripped: "Fix this"),
        DateCase("check in tomorrow", 2026, 9, 19, hasTime: false, stripped: "check in"),
        DateCase("Log in at 3pm", 2026, 9, 18, 15, 0, hasTime: true, stripped: "Log in"),
        DateCase("Buy milk, tomorrow", 2026, 9, 19, hasTime: false, stripped: "Buy milk"),
        DateCase("Review this by friday", 2026, 9, 25, hasTime: false, stripped: "Review this"),
        DateCase("The report tomorrow", 2026, 9, 19, hasTime: false, stripped: "The report"),
        DateCase("odevzdat do 5. prosince", 2026, 12, 5, hasTime: false, stripped: "odevzdat"),
    ])
    func removingMatchKeepsRealTitleWords(_ c: DateCase) { verify(c) }

    // MARK: DST spring forward (Europe/Prague)

    @Test
    func dstSpringForwardEuropePrague() {
        var prague = Calendar(identifier: .gregorian)
        prague.timeZone = TimeZone(identifier: "Europe/Prague")!
        var pragueNowComponents = DateComponents()
        pragueNowComponents.year = 2026
        pragueNowComponents.month = 9
        pragueNowComponents.day = 18
        pragueNowComponents.hour = 10
        let pragueNow = prague.date(from: pragueNowComponents)!

        // 2027-03-28 02:30 does not exist in Prague; the parser must move forward to 03:00
        // rather than collapsing back to midnight.
        guard let suggestion = NaturalDateParser.parse("schůzka 28.3.2027 v 2:30 ráno", now: pragueNow, calendar: prague) else {
            Issue.record("\"schůzka 28.3.2027 v 2:30 ráno\" should parse")
            return
        }
        var expected = DateComponents()
        expected.year = 2027
        expected.month = 3
        expected.day = 28
        expected.hour = 3
        let target = prague.date(from: expected)!
        #expect(suggestion.date == target,
                "DST gap time moves forward to 03:00 (got \(prague.dateComponents([.hour, .minute], from: suggestion.date)))")
        #expect(suggestion.hasTime, "DST case has a time")
        #expect(NaturalDateParser.removingMatch(from: "schůzka 28.3.2027 v 2:30 ráno", suggestion: suggestion) == "schůzka",
                "DST case strips to \"schůzka\"")
    }

    // MARK: negatives

    @Test(arguments: [
        NilCase(text: ""),
        NilCase(text: "   "),
        NilCase(text: "buy 2 apples"),
        NilCase(text: "iPhone 17"),
        NilCase(text: "call 5 people"),
        NilCase(text: "zavolat 3 lidem"),
        NilCase(text: "write the summary"),
    ])
    func negatives(_ c: NilCase) { verifyNil(c.text) }

    // MARK: right-most match wins

    @Test
    func rightMostPhraseWins() {
        guard let suggestion = NaturalDateParser.parse("tomorrow report for friday", now: ndpNow, calendar: ndpCalendar) else {
            Issue.record("\"tomorrow report for friday\" should parse")
            return
        }
        #expect(suggestion.matchedText == "for friday" || suggestion.matchedText == "friday",
                "right-most phrase is used, got \"\(suggestion.matchedText)\"")
        #expect(suggestion.date == ndpDate(2026, 9, 25), "right-most phrase resolves to friday")
    }

    @Test
    func dayAndTimeMergeIntoOneRange() {
        guard let suggestion = NaturalDateParser.parse("Buy milk tomorrow at 2pm", now: ndpNow, calendar: ndpCalendar) else {
            Issue.record("merge case should parse")
            return
        }
        #expect(suggestion.matchedText == "tomorrow at 2pm", "day and time merge into one range, got \"\(suggestion.matchedText)\"")
        #expect(String("Buy milk tomorrow at 2pm"[suggestion.matchedRange]) == suggestion.matchedText,
                "matchedRange indexes the original text")
    }
}
