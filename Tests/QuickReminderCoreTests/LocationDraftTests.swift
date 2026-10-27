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

    /// Done writes the field as typed, like the popover; the save path trims (one place).
    @Test func doneWritesTheFieldAsTyped() {
        var d = LocationDraft(original: "")
        d.text = "  Holešovice, Praha \n"
        #expect(d.isDirty)
        #expect(d.committed == "  Holešovice, Praha \n")
        #expect(d.saveDecision == .applyThenSave("  Holešovice, Praha \n"))
        #expect(RemindersService.buildNotes(notes: "", location: d.committed) == "📍 Holešovice, Praha")
    }

    @Test func blankingTheFieldRemovesTheLocation() {
        var d = LocationDraft(original: "Office")
        d.text = "   "
        #expect(d.saveDecision == .applyThenSave("   "))
        #expect(RemindersService.buildNotes(notes: "", location: d.committed) == nil)
    }

    /// Switching to Set Date keeps what was typed; an untouched field writes nothing.
    @Test func switchingKeepsWhatWasTyped() {
        var d = LocationDraft(original: "Office")
        #expect(d.textToKeepOnSwitch == nil)
        d.text = "Home"
        #expect(d.textToKeepOnSwitch == "Home")
    }

    @Test func typingBackTheOriginalIsNotAnEdit() {
        var d = LocationDraft(original: "Office")
        d.text = "Off"
        d.text = "Office"
        #expect(!d.isDirty)
        #expect(d.saveDecision == .saveAsIs)
    }
}

/// The one place the location is normalised, shared by both styles.
struct BuildNotesTests {
    @Test func notesAndLocation() {
        #expect(RemindersService.buildNotes(notes: "", location: nil) == nil)
        #expect(RemindersService.buildNotes(notes: "Bring cake", location: nil) == "Bring cake")
        #expect(RemindersService.buildNotes(notes: "Bring cake", location: " Office ") == "Bring cake\n📍 Office")
        #expect(RemindersService.buildNotes(notes: "", location: "\n  \t") == nil, "whitespace-only is no location")
    }
}
