import Foundation

@testable import QuickReminderCore

/// Shared fixtures for the scheduling tests: a fixed Europe/Prague calendar (so the DST cases
/// are real) and a compact date builder. Week of 19 Oct 2026: Mon 19 … Sun 25 (DST ends Sun 25).
let pragueCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Prague")!
    calendar.locale = Locale(identifier: "cs_CZ")
    return calendar
}()

func prague(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
    pragueCalendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}

func pragueString(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = pragueCalendar.timeZone
    formatter.dateFormat = "yyyy-MM-dd HH:mm"
    return formatter.string(from: date)
}

/// en_US puts a narrow no-break space before AM/PM; compare on plain spaces.
func plainSpaces(_ text: String) -> String {
    text.replacingOccurrences(of: "\u{202F}", with: " ").replacingOccurrences(of: "\u{00A0}", with: " ")
}
