import Foundation

/// "Tomorrow, 2:00 PM" / "zítra 14:00" style labels for date suggestions and chips.
/// `DateFormatter` creation is slow (~44 µs), so every instance is cached; they follow the
/// system locale automatically. Main-actor only (DateFormatter is not Sendable).
@MainActor
struct SuggestionDateFormatter {
    private static let withTime = make(time: true)
    private static let dateOnly = make(time: false)

    func string(from date: Date, hasTime: Bool) -> String {
        (hasTime ? Self.withTime : Self.dateOnly).string(from: date)
    }

    /// "Sat 9:00" / "so 9:00" / "Sat 9:00 AM" (presets, the Set button).
    func weekdayTime(from date: Date) -> String { Self.templated("EEE j:mm").string(from: date) }

    /// "19:00" / "7:00 PM" (time chips, presets that land today).
    func time(from date: Date) -> String { Self.templated("j:mm").string(from: date) }

    /// Preset detail: time only when `date` is today, weekday + time otherwise.
    func presetDetail(_ date: Date, now: Date) -> String {
        Self.templated(DatePreset.detailTemplate(for: date, now: now)).string(from: date)
    }

    /// Any locale template ("EEE d MMM", "EEEE j:mm"), cached per template.
    func string(from date: Date, template: String) -> String {
        Self.templated(template).string(from: date)
    }

    private static var templateCache: [String: DateFormatter] = [:]

    private static func templated(_ template: String) -> DateFormatter {
        if let cached = templateCache[template] { return cached }
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate(template)
        templateCache[template] = formatter
        return formatter
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
