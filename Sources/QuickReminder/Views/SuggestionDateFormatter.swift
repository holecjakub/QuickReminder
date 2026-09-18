import Foundation

/// "Tomorrow, 2:00 PM" / "zítra 14:00" style labels for date suggestions and chips.
/// Uses the system locale; relative day names come from Foundation.
struct SuggestionDateFormatter: Sendable {
    func string(from date: Date, hasTime: Bool) -> String {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.doesRelativeDateFormatting = true
        formatter.dateStyle = .medium
        formatter.timeStyle = hasTime ? .short : .none
        return formatter.string(from: date)
    }
}
