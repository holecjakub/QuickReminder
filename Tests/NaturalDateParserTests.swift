import Foundation

/// Assertion-based tests for `NaturalDateParser`.
/// `now` is pinned to Friday 2026-09-18 10:00 local time so every case is deterministic.
@MainActor
enum NaturalDateParserTests {

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        return calendar
    }()

    private static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = 0
        return calendar.date(from: components)!
    }

    private static var now: Date { date(2026, 9, 18, 10, 0) }

    private static func format(_ value: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: value)
    }

    static func run(check: (Bool, String) -> Void) {
        // A phrase is expected to resolve to `expected`, with the given `hasTime`,
        // and `removingMatch` is expected to leave `stripped` behind (nil = don't care).
        func expect(_ text: String, _ expected: Date, hasTime: Bool, stripped: String? = nil,
                    file: String = #fileID, line: Int = #line) {
            guard let suggestion = NaturalDateParser.parse(text, now: now, calendar: calendar) else {
                check(false, "\"\(text)\" should parse, got nil")
                return
            }
            check(suggestion.date == expected,
                  "\"\(text)\" → \(format(expected)) (got \(format(suggestion.date)), matched \"\(suggestion.matchedText)\")")
            check(suggestion.hasTime == hasTime, "\"\(text)\" hasTime == \(hasTime)")
            if let stripped {
                let rest = NaturalDateParser.removingMatch(from: text, suggestion: suggestion)
                check(rest == stripped, "\"\(text)\" strips to \"\(stripped)\" (got \"\(rest)\")")
            }
        }

        func expectNil(_ text: String) {
            let suggestion = NaturalDateParser.parse(text, now: now, calendar: calendar)
            check(suggestion == nil, "\"\(text)\" should not match (got \(suggestion.map { "\"\($0.matchedText)\"" } ?? "nil"))")
        }

        print("NaturalDateParser – day + time")
        expect("Buy milk tomorrow at 2pm", date(2026, 9, 19, 14, 0), hasTime: true, stripped: "Buy milk")
        expect("koupit mléko zítra ve 14:00", date(2026, 9, 19, 14, 0), hasTime: true, stripped: "koupit mléko")
        expect("zitra v 8 rano", date(2026, 9, 19, 8, 0), hasTime: true, stripped: "")
        expect("zítra v 8 ráno", date(2026, 9, 19, 8, 0), hasTime: true)
        expect("Call mom tomorrow 2pm", date(2026, 9, 19, 14, 0), hasTime: true, stripped: "Call mom")
        expect("at 2pm tomorrow", date(2026, 9, 19, 14, 0), hasTime: true, stripped: "")
        expect("schůzka v úterý ráno", date(2026, 9, 22, 9, 0), hasTime: true, stripped: "schůzka")
        expect("call mom tonight", date(2026, 9, 18, 20, 0), hasTime: true, stripped: "call mom")

        print("NaturalDateParser – relative days")
        expect("zavolat mámě zítra", date(2026, 9, 19), hasTime: false, stripped: "zavolat mámě")
        expect("tmrw", date(2026, 9, 19), hasTime: false)
        expect("day after tomorrow", date(2026, 9, 20), hasTime: false)
        expect("pozítří", date(2026, 9, 20), hasTime: false)
        expect("dnes", date(2026, 9, 18), hasTime: false)
        expect("dneska", date(2026, 9, 18), hasTime: false)
        expect("next week", date(2026, 9, 21), hasTime: false)
        expect("příští týden", date(2026, 9, 21), hasTime: false)
        expect("next month", date(2026, 10, 1), hasTime: false)
        expect("this weekend", date(2026, 9, 19), hasTime: false)
        expect("o víkendu", date(2026, 9, 19), hasTime: false)

        print("NaturalDateParser – weekdays")
        expect("meeting on friday", date(2026, 9, 25), hasTime: false, stripped: "meeting")
        expect("next friday", date(2026, 9, 25), hasTime: false)
        expect("MONDAY", date(2026, 9, 21), hasTime: false)
        expect("v pondělí", date(2026, 9, 21), hasTime: false, stripped: "")
        expect("ve středu", date(2026, 9, 23), hasTime: false)
        expect("příští pátek", date(2026, 9, 25), hasTime: false)
        expect("lunch on sat", date(2026, 9, 19), hasTime: false, stripped: "lunch")

        print("NaturalDateParser – explicit dates")
        expect("12. března", date(2027, 3, 12), hasTime: false)
        expect("March 12", date(2027, 3, 12), hasTime: false)
        expect("Mar 12", date(2027, 3, 12), hasTime: false)
        expect("12 March", date(2027, 3, 12), hasTime: false)
        expect("12. 3.", date(2027, 3, 12), hasTime: false)
        expect("12.3.2026", date(2026, 3, 12), hasTime: false)
        expect("dentist 3/12", date(2027, 3, 12), hasTime: false, stripped: "dentist")
        expect("zubař 3.12.", date(2026, 12, 3), hasTime: false, stripped: "zubař")
        expect("odevzdat do 5. prosince", date(2026, 12, 5), hasTime: false)

        print("NaturalDateParser – times")
        expect("meeting at 14:00", date(2026, 9, 18, 14, 0), hasTime: true, stripped: "meeting")
        expect("at 9", date(2026, 9, 19, 9, 0), hasTime: true)
        expect("noon", date(2026, 9, 18, 12, 0), hasTime: true)
        expect("midnight", date(2026, 9, 19, 0, 0), hasTime: true)
        expect("o půlnoci", date(2026, 9, 19, 0, 0), hasTime: true)
        expect("v poledne", date(2026, 9, 18, 12, 0), hasTime: true)
        expect("in the morning", date(2026, 9, 19, 9, 0), hasTime: true)
        expect("večer", date(2026, 9, 18, 19, 0), hasTime: true)
        expect("odpoledne", date(2026, 9, 18, 15, 0), hasTime: true)
        expect("ve 2 odpoledne", date(2026, 9, 18, 14, 0), hasTime: true)
        expect("v půl třetí", date(2026, 9, 18, 14, 30), hasTime: true)
        expect("ve 14.30", date(2026, 9, 18, 14, 30), hasTime: true)
        expect("call at 2:30pm", date(2026, 9, 18, 14, 30), hasTime: true, stripped: "call")

        print("NaturalDateParser – relative offsets")
        expect("in 2 hours", date(2026, 9, 18, 12, 0), hasTime: true)
        expect("in an hour", date(2026, 9, 18, 11, 0), hasTime: true)
        expect("in 30 minutes", date(2026, 9, 18, 10, 30), hasTime: true)
        expect("in 3 days", date(2026, 9, 21), hasTime: false)
        expect("in a week", date(2026, 9, 25), hasTime: false)
        expect("za hodinu", date(2026, 9, 18, 11, 0), hasTime: true)
        expect("za 2 hodiny", date(2026, 9, 18, 12, 0), hasTime: true)
        expect("za 5 hodin", date(2026, 9, 18, 15, 0), hasTime: true)
        expect("za 30 minut", date(2026, 9, 18, 10, 30), hasTime: true)
        expect("za 3 dny", date(2026, 9, 21), hasTime: false)
        expect("za týden", date(2026, 9, 25), hasTime: false)
        expect("za 2 týdny", date(2026, 10, 2), hasTime: false)

        print("NaturalDateParser – invalid dates never roll over")
        expectNil("30.2.")
        expectNil("31. února")
        expectNil("31. dubna")
        expectNil("31 April")
        // No year given → walk forward to the next year in which the date actually exists.
        expect("29.2.", date(2028, 2, 29), hasTime: false)
        // A stray number is not a year: "1000" stays in the title.
        expect("12 March 1000 items", date(2027, 3, 12), hasTime: false, stripped: "1000 items")
        // A written-out year further than ±10 years away is not a date at all.
        expectNil("12.3.2040")

        print("NaturalDateParser – sentence-final period after HH.MM")
        expect("ve 14.30.", date(2026, 9, 18, 14, 30), hasTime: true, stripped: "")
        expect("meeting at 14.30.", date(2026, 9, 18, 14, 30), hasTime: true, stripped: "meeting")

        print("NaturalDateParser – English day parts")
        expect("tomorrow evening", date(2026, 9, 19, 19, 0), hasTime: true, stripped: "")
        expect("tomorrow morning", date(2026, 9, 19, 9, 0), hasTime: true, stripped: "")
        expect("tomorrow night", date(2026, 9, 19, 20, 0), hasTime: true, stripped: "")
        expect("call mom tomorrow evening", date(2026, 9, 19, 19, 0), hasTime: true, stripped: "call mom")
        expect("friday afternoon", date(2026, 9, 25, 15, 0), hasTime: true, stripped: "")

        print("NaturalDateParser – hour disambiguation with an evening context")
        expect("tonight at 8", date(2026, 9, 18, 20, 0), hasTime: true, stripped: "")
        expect("12am", date(2026, 9, 19, 0, 0), hasTime: true)
        expect("12pm", date(2026, 9, 18, 12, 0), hasTime: true)
        // "12 večer" is genuinely ambiguous (noon? midnight?), so 12 is left as written.
        expect("v 12 večer", date(2026, 9, 18, 12, 0), hasTime: true, stripped: "")
        expect("půl třetí odpoledne", date(2026, 9, 18, 14, 30), hasTime: true, stripped: "")

        print("NaturalDateParser – offset merged with a time")
        expect("in 2 days at 3pm", date(2026, 9, 20, 15, 0), hasTime: true, stripped: "")
        expect("za 3 dny v 9 ráno", date(2026, 9, 21, 9, 0), hasTime: true, stripped: "")

        print("NaturalDateParser – removingMatch keeps real title words")
        expect("Fix this tomorrow", date(2026, 9, 19), hasTime: false, stripped: "Fix this")
        expect("check in tomorrow", date(2026, 9, 19), hasTime: false, stripped: "check in")
        expect("Log in at 3pm", date(2026, 9, 18, 15, 0), hasTime: true, stripped: "Log in")
        expect("Buy milk, tomorrow", date(2026, 9, 19), hasTime: false, stripped: "Buy milk")
        expect("Review this by friday", date(2026, 9, 25), hasTime: false, stripped: "Review this")
        expect("The report tomorrow", date(2026, 9, 19), hasTime: false, stripped: "The report")
        expect("odevzdat do 5. prosince", date(2026, 12, 5), hasTime: false, stripped: "odevzdat")

        print("NaturalDateParser – DST spring forward (Europe/Prague)")
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
        if let suggestion = NaturalDateParser.parse("schůzka 28.3.2027 v 2:30 ráno", now: pragueNow, calendar: prague) {
            var expected = DateComponents()
            expected.year = 2027
            expected.month = 3
            expected.day = 28
            expected.hour = 3
            let target = prague.date(from: expected)!
            check(suggestion.date == target,
                  "DST gap time moves forward to 03:00 (got \(prague.dateComponents([.hour, .minute], from: suggestion.date)))")
            check(suggestion.hasTime, "DST case has a time")
            check(NaturalDateParser.removingMatch(from: "schůzka 28.3.2027 v 2:30 ráno", suggestion: suggestion) == "schůzka",
                  "DST case strips to \"schůzka\"")
        } else {
            check(false, "\"schůzka 28.3.2027 v 2:30 ráno\" should parse")
        }

        print("NaturalDateParser – negatives")
        expectNil("")
        expectNil("   ")
        expectNil("buy 2 apples")
        expectNil("iPhone 17")
        expectNil("call 5 people")
        expectNil("zavolat 3 lidem")
        expectNil("write the summary")

        print("NaturalDateParser – right-most match wins")
        if let suggestion = NaturalDateParser.parse("tomorrow report for friday", now: now, calendar: calendar) {
            check(suggestion.matchedText == "for friday" || suggestion.matchedText == "friday",
                  "right-most phrase is used, got \"\(suggestion.matchedText)\"")
            check(suggestion.date == date(2026, 9, 25), "right-most phrase resolves to friday")
        } else {
            check(false, "\"tomorrow report for friday\" should parse")
        }

        if let suggestion = NaturalDateParser.parse("Buy milk tomorrow at 2pm", now: now, calendar: calendar) {
            check(suggestion.matchedText == "tomorrow at 2pm", "day and time merge into one range, got \"\(suggestion.matchedText)\"")
            check(String("Buy milk tomorrow at 2pm"[suggestion.matchedRange]) == suggestion.matchedText,
                  "matchedRange indexes the original text")
        } else {
            check(false, "merge case should parse")
        }
    }
}
