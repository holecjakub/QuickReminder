import Foundation

/// Set Date's open and commit decisions, kept out of the views so they can be unit-tested and
/// shared by both styles (the popover and the in-notch section).
enum ScheduleCommit {
    /// What Set Date opens on. An existing date wins; then the title's live suggestion (prefilled
    /// into the field, the draft following it when it parses); otherwise tomorrow 9:00, the most
    /// common intent (today is ⌘1 away).
    static func opening(selected: Date?, initialText: String?, now: Date,
                        calendar: Calendar = .current) -> (draft: Date, text: String) {
        if let selected { return (selected, "") }
        let tomorrow = DatePreset.date(for: .tomorrow, now: now, calendar: calendar)
        guard let phrase = initialText?.trimmingCharacters(in: .whitespaces), !phrase.isEmpty else {
            return (tomorrow, "")
        }
        if case let .date(date) = ScheduleInput.resolve(phrase, now: now, calendar: calendar) {
            return (date, phrase)
        }
        return (tomorrow, phrase)
    }

    /// How the popover closed.
    enum Action: Equatable {
        /// Set button, ↩ or ⌘↩, whatever the field / calendar / time chips hold.
        case set
        /// A preset card or ⌘1…⌘6.
        case preset
        /// Cancel, Esc or a click outside: nothing is written.
        case cancel
        /// Clear: the date is removed.
        case clear
    }

    /// The date Set writes: the typed phrase when it parses, otherwise the draft the controls
    /// built. nil = invalid text (beep, stay open).
    static func dateToSet(for result: ScheduleInput.Result, draft: Date) -> Date? {
        switch result {
        case .invalid: return nil
        case let .date(date): return date
        case .empty: return draft
        }
    }

    /// Whether the title's date phrase is stripped (Tab semantics). Once the popover was opened
    /// from a live suggestion, any choice that writes a date replaces what the phrase said, so
    /// the phrase goes — even if the user edited the prefilled text, used the calendar, a time
    /// chip or a preset. Otherwise the title would keep "zítra" while the reminder is due on
    /// another day (the save path only auto-applies a suggestion when no date is set).
    static func consumesSuggestion(initialText: String?, action: Action) -> Bool {
        guard let phrase = initialText?.trimmingCharacters(in: .whitespaces), !phrase.isEmpty else { return false }
        switch action {
        case .set, .preset: return true
        case .cancel, .clear: return false
        }
    }
}
