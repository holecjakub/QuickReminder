import Foundation
import Testing

@testable import QuickReminderCore

/// The A/B switch between the Set Date popover and the in-notch section.
struct SetDateStyleTests {
    @Test func defaultsToInNotch() {
        #expect(SetDateStyle.defaultStyle == .notch)
        #expect(SetDateStyle.allCases.map(\.title) == ["Popover", "In notch"])
    }

    /// The stored values and the key are what existing installs and `-datePickerStyle` use.
    @Test func storedValuesAreStable() {
        #expect(SetDateStyle.defaultsKey == "datePickerStyle")
        #expect(SetDateStyle.popover.rawValue == "popover")
        #expect(SetDateStyle.notch.rawValue == "notch")
        #expect(SetDateStyle(rawValue: "bogus") == nil, "@AppStorage then falls back to defaultStyle")
    }
}
