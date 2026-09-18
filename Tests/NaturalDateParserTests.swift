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
