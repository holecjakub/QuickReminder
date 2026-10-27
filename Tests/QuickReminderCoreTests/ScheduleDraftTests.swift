import Foundation
import Testing

@testable import QuickReminderCore

/// The model both Set Date styles share: open rules, typing, controls, commits.
/// Friday 23 Oct 2026 10:00, Europe/Prague.
@MainActor
struct ScheduleDraftTests {
    private let now = prague(2026, 10, 23, 10, 0)

    private func draft(selected: Date? = nil, initialText: String? = nil) -> ScheduleDraft {
        let fixed = now
        return ScheduleDraft(selected: selected, initialText: initialText, calendar: pragueCalendar, clock: { fixed })
    }

    @Test func opensOnTheSharedRules() {
        #expect(pragueString(draft().draft) == "2026-10-24 09:00")
        let fromPhrase = draft(initialText: "zítra 14:00")
        #expect(fromPhrase.text == "zítra 14:00")
        #expect(pragueString(fromPhrase.draft) == "2026-10-24 14:00")
        #expect(fromPhrase.textIsDate)
        let existing = prague(2026, 11, 2, 15, 0)
        #expect(draft(selected: existing, initialText: "zítra").draft == existing)
    }

    @Test func relativeTextResolvesAtSetNotAtTheLastKeystroke() {
        var t = now
        let d = ScheduleDraft(selected: nil, initialText: nil, calendar: pragueCalendar, clock: { t })
        d.text = "+2h"
        t = prague(2026, 10, 23, 10, 30)
        #expect(d.set()?.date == prague(2026, 10, 23, 12, 30))
    }

    @Test func typingParsesOnceAndMovesTheDraft() {
        let d = draft()
        d.text = "fri 2pm"
        #expect(d.parsed == .date(prague(2026, 10, 30, 14, 0)))
        #expect(d.draft == prague(2026, 10, 30, 14, 0))
        d.text = "fri 2pm please"
        #expect(d.isInvalid)
        #expect(d.draft == prague(2026, 10, 30, 14, 0), "an invalid entry leaves the draft where it was")
        d.text = ""
        #expect(d.parsed == .empty)
    }

    @Test func controlsClearTheTypedText() {
        let d = draft(initialText: "zítra")
        d.setTime(hour: 15)
        #expect(d.text == "")
        #expect(pragueString(d.draft) == "2026-10-24 15:00")
        d.pick(day: prague(2026, 10, 28))
        #expect(pragueString(d.draft) == "2026-10-28 15:00", "the day keeps the time")
        #expect(d.applyTypedTime("1430"))
        #expect(pragueString(d.draft) == "2026-10-28 14:30")
        #expect(!d.applyTypedTime("25:00"))
        #expect(pragueString(d.draft) == "2026-10-28 14:30")
    }

    @Test func timeStepsSnapToQuarterHours() {
        let d = draft()
        d.setTime(hour: 9, minute: 7)
        d.stepTime(by: 1)
        #expect(pragueString(d.draft) == "2026-10-24 09:15")
        d.setTime(hour: 9, minute: 7)
        d.stepTime(by: -1)
        #expect(pragueString(d.draft) == "2026-10-24 09:00")
        d.setTime(hour: 23, minute: 50)
        d.stepTime(by: 1)
        #expect(pragueString(d.draft) == "2026-10-24 00:00", "wraps within the day")
    }

    @Test func gridMovementAndPaging() {
        let d = draft()   // Sat 24 Oct 9:00
        #expect(d.moveDay(by: 7))
        #expect(pragueString(d.draft) == "2026-10-31 09:00")
        #expect(!d.moveDay(by: -14), "into the past: blocked")
        d.moveInto(month: prague(2026, 12, 1))
        #expect(pragueString(d.draft) == "2026-12-31 09:00", "same day number in the paged month")
        d.moveInto(month: prague(2026, 11, 1))
        #expect(pragueString(d.draft) == "2026-11-30 09:00", "clamped to a shorter month")
    }

    @Test func setWritesTheTypedDateOnceAndConsumesThePhrase() throws {
        let d = draft(initialText: "zítra")
        d.text = "zítra 16:00"
        let outcome = try #require(d.set())
        #expect(pragueString(try #require(outcome.date)) == "2026-10-24 16:00")
        #expect(outcome.presetPick == nil)
        #expect(outcome.consumesSuggestion)
        #expect(d.committed)
        #expect(d.set() == nil, "a second commit is ignored")
        #expect(d.apply(.tomorrow) == nil)
    }

    @Test func setOnInvalidTextStaysOpen() {
        let d = draft()
        d.text = "not a date"
        #expect(d.set() == nil)
        #expect(!d.committed, "the view beeps and stays open")
    }

    @Test func presetRecordsThePickAndClearKeepsTheTitle() throws {
        let weekend = try #require(draft().apply(.weekend))
        #expect(weekend.presetPick == PresetPick(preset: .weekend, date: prague(2026, 10, 24, 9, 0)))
        #expect(!weekend.consumesSuggestion, "no phrase was prefilled")

        let cleared = try #require(draft(selected: prague(2026, 11, 2, 9, 0), initialText: "zítra").clear())
        #expect(cleared.date == nil && cleared.presetPick == nil)
        #expect(!cleared.consumesSuggestion)
    }

    /// Friday: Tomorrow and This Weekend are both Sat 9:00; only the picked one lights up.
    @Test func singleHighlight() {
        let d = draft()
        #expect(d.highlightedPreset(picked: nil) == .tomorrow)
        #expect(d.highlightedPreset(picked: PresetPick(preset: .weekend, date: prague(2026, 10, 24, 9, 0))) == .weekend)
    }

    // MARK: ✓ while the section is open

    @Test func untouchedSavesAsIs() {
        let d = draft()
        #expect(!d.isDirty)
        #expect(d.prepareSave() == .saveAsIs, "the default tomorrow 9:00 must not sneak into the reminder")
        #expect(!d.committed)
        let prefilled = draft(initialText: "zítra")
        #expect(!prefilled.isDirty, "a prefilled phrase is not an edit (save applies the suggestion anyway)")
        #expect(prefilled.prepareSave() == .saveAsIs)
    }

    @Test func anEditIsCommittedBeforeSaving() throws {
        let typed = draft(initialText: "zítra")
        typed.text = "zítra 16:00"
        guard case let .commitThenSave(outcome) = typed.prepareSave() else {
            Issue.record("expected commitThenSave"); return
        }
        #expect(pragueString(try #require(outcome.date)) == "2026-10-24 16:00")
        #expect(outcome.consumesSuggestion)
        #expect(typed.committed)

        let chip = draft()
        chip.setTime(hour: 15)
        guard case let .commitThenSave(chipOutcome) = chip.prepareSave() else {
            Issue.record("expected commitThenSave"); return
        }
        #expect(pragueString(try #require(chipOutcome.date)) == "2026-10-24 15:00")
    }

    @Test func invalidTextBlocksTheSave() {
        let d = draft()
        d.text = "not a date"
        #expect(d.prepareSave() == .invalid)
        #expect(!d.committed)
    }

    @Test func afterACommitTheSaveGoesThroughAsIs() {
        let d = draft()
        d.setTime(hour: 15)
        _ = d.set()
        #expect(d.committed)
        #expect(d.prepareSave() == .saveAsIs, "the date is already written; never Set twice")
    }
}
