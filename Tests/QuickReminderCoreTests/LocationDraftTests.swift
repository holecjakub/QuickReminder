import Testing

@testable import QuickReminderCore

/// The in-notch Location section's model.
struct LocationDraftTests {
    @Test func opensOnTheCurrentLocation() {
        let d = LocationDraft(original: "Café Slavia")
        #expect(d.text == "Café Slavia")
        #expect(!d.isDirty)
        #expect(d.saveDecision == .saveAsIs)
    }

    @Test func doneWritesTheTrimmedText() {
        var d = LocationDraft(original: "")
        d.text = "  Holešovice, Praha \n"
        #expect(d.isDirty)
        #expect(d.committed == "Holešovice, Praha")
        #expect(d.saveDecision == .applyThenSave("Holešovice, Praha"))
    }

    @Test func emptyingTheFieldRemovesTheLocation() {
        var d = LocationDraft(original: "Office")
        d.text = "   "
        #expect(d.committed == "")
        #expect(d.saveDecision == .applyThenSave(""))
    }

    @Test func typingBackTheOriginalIsNotAnEdit() {
        var d = LocationDraft(original: "Office")
        d.text = "Off"
        d.text = "Office"
        #expect(!d.isDirty)
        #expect(d.saveDecision == .saveAsIs)
    }
}
