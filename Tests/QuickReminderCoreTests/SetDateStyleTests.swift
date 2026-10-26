import Testing

@testable import QuickReminderCore

/// The A/B switch between the Set Date popover and the in-notch section.
struct DatePickerStyleTests {
    @Test func defaultsToInNotchOnThisBranch() {
        #expect(DatePickerStyle.defaultStyle == .notch)
        #expect(DatePickerStyle.resolve(nil) == .notch)
        #expect(DatePickerStyle.resolve("bogus") == .notch)
        #expect(DatePickerStyle.resolve("popover") == .popover)
        #expect(DatePickerStyle.allCases.map(\.title) == ["Popover", "In notch"])
    }
}
