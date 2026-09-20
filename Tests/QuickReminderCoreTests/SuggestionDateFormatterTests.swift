import Foundation
import Testing

@testable import QuickReminderCore

/// `SuggestionDateFormatter` is main-actor only (wraps a non-Sendable `DateFormatter`),
/// and relies on `doesRelativeDateFormatting` for the "Tomorrow" label.
@MainActor
struct SuggestionDateFormatterTests {

    @Test func relativeTomorrowLabelWithTime() {
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date())!
        let formatter = SuggestionDateFormatter()
        let label = formatter.string(from: tomorrow, hasTime: true)
        // Locale-proof: the contract is "relative day name + short time" in the current locale.
        let reference = DateFormatter()
        reference.locale = .autoupdatingCurrent
        reference.doesRelativeDateFormatting = true
        reference.dateStyle = .medium
        reference.timeStyle = .short
        #expect(label == reference.string(from: tomorrow), "got \"\(label)\"")
        let absolute = DateFormatter()
        absolute.locale = .autoupdatingCurrent
        absolute.dateStyle = .medium
        absolute.timeStyle = .short
        #expect(label != absolute.string(from: tomorrow), "label should be relative (\"Tomorrow …\"), got \"\(label)\"")
    }

    @Test func dateOnlyOmitsTime() {
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date())!
        let formatter = SuggestionDateFormatter()
        let dateOnly = formatter.string(from: tomorrow, hasTime: false)
        let withTime = formatter.string(from: tomorrow, hasTime: true)
        #expect(dateOnly != withTime, "hasTime: false should omit the time component")
    }
}
