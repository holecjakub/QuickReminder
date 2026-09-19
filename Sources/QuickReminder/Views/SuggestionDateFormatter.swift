import Foundation

/// "Tomorrow, 2:00 PM" / "zítra 14:00" style labels for date suggestions and chips.
/// `DateFormatter` creation is slow (~44 µs), so two instances are cached; they follow the
/// system locale automatically. Main-actor only (DateFormatter is not Sendable).
@MainActor
struct SuggestionDateFormatter {
    private static let withTime = make(time: true)
    private static let dateOnly = make(time: false)

    func string(from date: Date, hasTime: Bool) -> String {
        (hasTime ? Self.withTime : Self.dateOnly).string(from: date)
    }

    private static func make(time: Bool) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.doesRelativeDateFormatting = true
        formatter.dateStyle = .medium
        formatter.timeStyle = time ? .short : .none
        return formatter
    }
}
