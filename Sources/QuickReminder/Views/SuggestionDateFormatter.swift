import AppKit
import Foundation

/// "Tomorrow, 2:00 PM" / "zítra 14:00" style labels for date suggestions and chips.
/// `DateFormatter` creation is slow (~44 µs), so formatters are cached per template + locale +
/// time zone. The cache is dropped when the system locale, the 12/24-hour setting or the time
/// zone changes (`setLocalizedDateFormatFromTemplate` resolves "j:mm" only once), so a long-lived
/// panel never keeps an old clock format. Main-actor only (DateFormatter is not Sendable).
@MainActor
struct SuggestionDateFormatter {
    let locale: Locale
    let calendar: Calendar

    /// Production uses the autoupdating locale and calendar; tests inject fixed ones.
    init(locale: Locale = .autoupdatingCurrent, calendar: Calendar = .autoupdatingCurrent) {
        self.locale = locale
        self.calendar = calendar
    }

    func string(from date: Date, hasTime: Bool) -> String {
        formatter(key: hasTime ? "relative+time" : "relative") { formatter in
            formatter.doesRelativeDateFormatting = true
            formatter.dateStyle = .medium
            formatter.timeStyle = hasTime ? .short : .none
        }.string(from: date)
    }

    /// "19:00" / "7:00 PM" (time chips).
    func time(from date: Date) -> String { string(from: date, template: "j:mm") }

    /// Time today, weekday + time this week, day + month + time beyond (presets, the Set
    /// button). `spoken` is the VoiceOver wording.
    func presetDetail(_ date: Date, now: Date, spoken: Bool = false) -> String {
        string(from: date, template: DatePreset.detailTemplate(for: date, now: now, calendar: calendar, spoken: spoken))
    }

    /// Any locale template ("EEE d MMM", "EEEE j:mm"), cached per template.
    func string(from date: Date, template: String) -> String {
        formatter(key: "t:" + template) { $0.setLocalizedDateFormatFromTemplate(template) }.string(from: date)
    }

    // MARK: Cache

    private static var cache: [String: DateFormatter] = [:]
    private static var observing = false

    /// Drops every cached formatter; the next label rebuilds from the current settings.
    static func invalidateCache() { cache.removeAll() }

    static var cachedFormatterCount: Int { cache.count }

    private func formatter(key: String, configure: (DateFormatter) -> Void) -> DateFormatter {
        Self.observeSystemChanges()
        let fullKey = "\(key)|\(locale.identifier)|\(calendar.timeZone.identifier)"
        if let cached = Self.cache[fullKey] { return cached }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        configure(formatter)
        Self.cache[fullKey] = formatter
        return formatter
    }

    private static func observeSystemChanges() {
        guard !observing else { return }
        observing = true
        // The 24-hour toggle posts the locale notification without changing the identifier.
        for name in [NSLocale.currentLocaleDidChangeNotification, .NSSystemTimeZoneDidChange] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { invalidateCache() }
            }
        }
    }
}
