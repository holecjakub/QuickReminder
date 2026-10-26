import Foundation
import Testing

@testable import QuickReminderCore

struct ScheduleCommitTests {
    private let draft = prague(2026, 10, 24, 9, 0)

    @Test func setWritesTheParsedDateOrTheDraft() {
        let typed = prague(2026, 10, 25, 16, 0)
        #expect(ScheduleCommit.dateToSet(for: .date(typed), draft: draft) == typed)
        #expect(ScheduleCommit.dateToSet(for: .empty, draft: draft) == draft)
        #expect(ScheduleCommit.dateToSet(for: .invalid, draft: draft) == nil)
    }

    /// "call mom zítra", ⌘D prefills "zítra": refining it to "zítra 16:00", picking a chip,
    /// the calendar or a preset all still strip "zítra" from the title.
    @Test(arguments: [ScheduleCommit.Action.set, .preset])
    func anyDateWriteConsumesThePrefilledPhrase(action: ScheduleCommit.Action) {
        #expect(ScheduleCommit.consumesSuggestion(initialText: "zítra", action: action))
    }

    @Test(arguments: [ScheduleCommit.Action.cancel, .clear])
    func cancelAndClearKeepTheTitle(action: ScheduleCommit.Action) {
        #expect(!ScheduleCommit.consumesSuggestion(initialText: "zítra", action: action))
    }

    @Test(arguments: [nil, "", "  "] as [String?])
    func noSuggestionNothingToConsume(initialText: String?) {
        #expect(!ScheduleCommit.consumesSuggestion(initialText: initialText, action: .set))
        #expect(!ScheduleCommit.consumesSuggestion(initialText: initialText, action: .preset))
    }
}

/// What Set Date opens on — shared by the popover and the in-notch section.
struct ScheduleOpeningTests {
    private let now = prague(2026, 10, 23, 10, 0)

    @Test func anExistingDateWinsAndTheFieldStartsEmpty() {
        let set = prague(2026, 11, 2, 15, 0)
        let opening = ScheduleCommit.opening(selected: set, initialText: "zítra", now: now, calendar: pragueCalendar)
        #expect(opening.draft == set)
        #expect(opening.text == "")
    }

    @Test func aLiveSuggestionIsPrefilledAndDrivesTheDraft() {
        let opening = ScheduleCommit.opening(selected: nil, initialText: " zítra 14:00 ", now: now, calendar: pragueCalendar)
        #expect(pragueString(opening.draft) == "2026-10-24 14:00")
        #expect(opening.text == "zítra 14:00")
    }

    @Test func otherwiseTomorrowMorning() {
        for text in [nil, "", "  "] as [String?] {
            let opening = ScheduleCommit.opening(selected: nil, initialText: text, now: now, calendar: pragueCalendar)
            #expect(pragueString(opening.draft) == "2026-10-24 09:00")
            #expect(opening.text == "")
        }
    }

    @Test func anUnreadablePhraseStaysInTheFieldOverTomorrow() {
        let opening = ScheduleCommit.opening(selected: nil, initialText: "zítra prosím", now: now, calendar: pragueCalendar)
        #expect(pragueString(opening.draft) == "2026-10-24 09:00")
        #expect(opening.text == "zítra prosím")
    }
}

struct TextRowSubmitTests {
    /// With the in-notch section open, ↩ in the title / notes is Set — even with an empty title
    /// (nothing to save) and never a save while a draft is pending.
    @Test func returnInTheTitleIsSetWhileSchedulingInTheNotch() {
        #expect(ScheduleCommit.textRowSubmit(schedulingInNotch: true, canSave: true) == .setSchedule)
        #expect(ScheduleCommit.textRowSubmit(schedulingInNotch: true, canSave: false) == .setSchedule)
        #expect(ScheduleCommit.textRowSubmit(schedulingInNotch: false, canSave: true) == .saveReminder)
        #expect(ScheduleCommit.textRowSubmit(schedulingInNotch: false, canSave: false) == .none)
    }
}
