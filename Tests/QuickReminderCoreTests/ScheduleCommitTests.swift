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
