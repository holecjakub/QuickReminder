import Testing

@testable import QuickReminderCore

let slavia = PickedPlace(name: "Café Slavia", address: "Smetanovo nábřeží 1012/2, Praha",
                         latitude: 50.0815, longitude: 14.4136)

/// The reminder's location: typed vs picked, and Arriving / Leaving.
struct ReminderLocationTests {
    @Test func startsEmptyAndArriving() {
        let l = ReminderLocation()
        #expect(l.isEmpty)
        #expect(l.place == nil)
        #expect(l.proximity == .arriving)
    }

    @Test func pickingWritesTheNameAndKeepsThePlace() {
        var l = ReminderLocation(text: "slav")
        l.pick(slavia)
        #expect(l.text == "Café Slavia")
        #expect(l.place == slavia)
    }

    /// Typing over a picked place turns it back into free text.
    @Test func typingOverAPickDropsIt() {
        var l = ReminderLocation()
        l.pick(slavia)
        l.text = "Café Slavia, 2nd floor"
        #expect(l.place == nil)
        l.text = "Café Slavia"
        #expect(l.place == nil, "retyping the name does not bring the pick back")
    }

    @Test func proximityIsKeptAcrossPicksAndClear() {
        var l = ReminderLocation()
        l.proximity = .leaving
        l.pick(slavia)
        #expect(l.proximity == .leaving)
        l.clear()
        #expect(l.isEmpty && l.place == nil)
        #expect(l.proximity == .leaving)
    }
}

/// The in-notch Location section's model.
struct LocationDraftTests {
    @Test func opensOnTheCurrentLocation() {
        let d = LocationDraft(original: ReminderLocation(text: "Café Slavia"))
        #expect(d.location.text == "Café Slavia")
        #expect(!d.isDirty)
        #expect(d.saveDecision == .saveAsIs)
    }

    /// Done writes the field as typed, like the popover; the save path trims (one place).
    @Test func doneWritesTheFieldAsTyped() {
        var d = LocationDraft(original: ReminderLocation())
        d.location.text = "  Holešovice, Praha \n"
        #expect(d.isDirty)
        #expect(d.committed.text == "  Holešovice, Praha \n")
        #expect(d.saveDecision == .applyThenSave(ReminderLocation(text: "  Holešovice, Praha \n")))
        #expect(LocationSavePlan.plan(for: d.committed) == .noteLine("Holešovice, Praha"))
    }

    @Test func blankingTheFieldRemovesTheLocation() {
        var d = LocationDraft(original: ReminderLocation(text: "Office"))
        d.location.text = "   "
        #expect(d.saveDecision == .applyThenSave(ReminderLocation(text: "   ")))
        #expect(LocationSavePlan.plan(for: d.committed) == .none)
    }

    @Test func aPickIsAnEdit() {
        var d = LocationDraft(original: ReminderLocation())
        d.location.pick(slavia)
        #expect(d.isDirty)
        var expected = ReminderLocation()
        expected.pick(slavia)
        #expect(d.saveDecision == .applyThenSave(expected))
        #expect(expected.place == slavia && expected.text == "Café Slavia")
    }

    /// Changing only Arriving / Leaving is an edit too (✓ and a switch keep it).
    @Test func changingProximityIsAnEdit() {
        var original = ReminderLocation()
        original.pick(slavia)
        var d = LocationDraft(original: original)
        #expect(!d.isDirty)
        d.location.proximity = .leaving
        #expect(d.isDirty)
        #expect(d.locationToKeepOnSwitch?.proximity == .leaving)
    }

    /// Switching to Set Date keeps what was typed; an untouched field writes nothing.
    @Test func switchingKeepsWhatWasTyped() {
        var d = LocationDraft(original: ReminderLocation(text: "Office"))
        #expect(d.locationToKeepOnSwitch == nil)
        d.location.text = "Home"
        #expect(d.locationToKeepOnSwitch?.text == "Home")
    }

    @Test func typingBackTheOriginalIsNotAnEdit() {
        var d = LocationDraft(original: ReminderLocation(text: "Office"))
        d.location.text = "Off"
        d.location.text = "Office"
        #expect(!d.isDirty)
        #expect(d.saveDecision == .saveAsIs)
    }
}

/// The one place the note line is built, shared by both styles.
struct BuildNotesTests {
    @Test func notesAndLocation() {
        #expect(RemindersService.buildNotes(notes: "", location: nil) == nil)
        #expect(RemindersService.buildNotes(notes: "Bring cake", location: nil) == "Bring cake")
        #expect(RemindersService.buildNotes(notes: "Bring cake", location: " Office ") == "Bring cake\n📍 Office")
        #expect(RemindersService.buildNotes(notes: "", location: "\n  \t") == nil, "whitespace-only is no location")
    }
}
