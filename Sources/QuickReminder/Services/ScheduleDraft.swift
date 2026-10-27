import Foundation
import Observation
import SwiftUI

/// Set Date's working state, shared by both styles (`SchedulePopover`, `ScheduleNotchSection`) so
/// their behaviour cannot drift: what it opens on, the typed field (parsed once per change), the
/// date the controls build, and the commit decisions.
///
/// One source of truth, `draft`. Typing resolves on every change and moves `draft` one-way; the
/// calendar, time field and chips write `draft` and clear the text, so the two inputs never
/// ping-pong. Nothing leaves the draft until `set()`, `apply(_:)` or `clear()` returns an
/// `Outcome` for the view to write; each of them works once (`committed`).
@MainActor @Observable
final class ScheduleDraft {
    /// The date being built; what Set writes when the field is empty.
    private(set) var draft: Date
    /// The type field. A change is parsed once (`parsed`); a date moves `draft` with it.
    var text: String {
        didSet { if text != oldValue { isDirty = true; reparse() } }
    }
    /// The user typed or used a control since Set Date opened (prefilled text does not count).
    private(set) var isDirty = false
    /// `ScheduleInput.resolve(text)` as of the last change.
    private(set) var parsed: ScheduleInput.Result
    /// Set, a preset or Clear already ran: further commits are ignored.
    private(set) var committed = false
    /// The title's live suggestion phrase this session was opened with (prefilled into `text`).
    let initialText: String?

    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private let clock: () -> Date
    @ObservationIgnored private var announcement: Task<Void, Never>?

    init(selected: Date?, initialText: String?, calendar: Calendar = .current,
         clock: @escaping () -> Date = { AppClock.now }) {
        self.calendar = calendar
        self.clock = clock
        self.initialText = initialText
        let opening = ScheduleCommit.opening(selected: selected, initialText: initialText, now: clock(), calendar: calendar)
        draft = opening.draft
        text = opening.text
        parsed = ScheduleInput.resolve(opening.text, now: clock(), calendar: calendar)
    }

    var now: Date { clock() }
    var isInvalid: Bool { parsed == .invalid }
    /// The typed text resolves to a date (the field shows its ⏎ hint).
    var textIsDate: Bool { if case .date = parsed { return true } else { return false } }

    private func reparse() {
        parsed = ScheduleInput.resolve(text, now: clock(), calendar: calendar)
        if case let .date(date) = parsed { draft = date }
    }

    // MARK: Controls (each clears the typed text)

    func setFromControls(_ date: Date) {
        isDirty = true
        draft = date
        text = ""
    }

    /// The calendar: the picked day, keeping the draft's time.
    func pick(day: Date) {
        setFromControls(ScheduleDefaults.compose(day: day, time: draft, calendar: calendar))
    }

    /// A time chip: `hour`:00 on the draft's day.
    func setTime(hour: Int, minute: Int = 0) {
        setFromControls(ScheduleDefaults.at(hour: hour, minute: minute, on: draft, calendar: calendar))
    }

    /// The typed time field ("14", "1430", "14:30", "2pm", read by `ScheduleInput`): its time part
    /// on the draft's day. false (draft unchanged) when it does not read as a time.
    @discardableResult
    func applyTypedTime(_ typed: String) -> Bool {
        guard case let .date(time) = ScheduleInput.resolve(typed, now: clock(), calendar: calendar) else { return false }
        setFromControls(ScheduleDefaults.compose(day: draft, time: time, calendar: calendar))
        return true
    }

    /// ↑ / ↓ in the time field: snap to the 15-minute grid, then step; wraps within the day.
    func stepTime(by steps: Int) {
        let parts = calendar.dateComponents([.hour, .minute], from: draft)
        let minutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        let snapped = steps > 0 ? (minutes / 15 + steps) * 15 : ((minutes + 14) / 15 + steps) * 15
        let wrapped = (snapped % 1440 + 1440) % 1440
        setTime(hour: wrapped / 60, minute: wrapped % 60)
    }

    /// Arrow keys in the month grid: ±1 / ±7 days, never into the past. false = blocked (beep).
    @discardableResult
    func moveDay(by days: Int) -> Bool {
        let moved = MonthGrid.moving(draft, byDays: days, earliest: clock(), calendar: calendar)
        guard moved != draft else { return false }
        setFromControls(moved)
        return true
    }

    /// The month grid was paged away from the draft's month and an arrow key was pressed: land on
    /// the same day number in the visible month (clamped to its length and to today).
    func moveInto(month: Date) {
        let first = MonthGrid.startOfMonth(month, calendar: calendar)
        let length = calendar.range(of: .day, in: .month, for: first)?.count ?? 28
        let dayNumber = min(calendar.component(.day, from: draft), length)
        var day = calendar.date(byAdding: .day, value: dayNumber - 1, to: first) ?? first
        if !MonthGrid.isSelectable(day, now: clock(), calendar: calendar) { day = calendar.startOfDay(for: clock()) }
        pick(day: day)
    }

    // MARK: Commit

    /// What a commit writes back to the reminder.
    struct Outcome: Equatable {
        /// The reminder's new date (nil = Clear).
        let date: Date?
        /// The preset that wrote it, for the single highlight (`DatePreset.highlighted`).
        let presetPick: PresetPick?
        /// Strip the title's date phrase (`ScheduleCommit.consumesSuggestion`).
        let consumesSuggestion: Bool
    }

    /// Set / ↩ / ⌘↩: the typed date when it parses, otherwise the draft. nil when the text is not a
    /// date (the view beeps and stays open) or a commit already ran.
    func set() -> Outcome? {
        // Relative phrases (“+2h”, “today”) count from the moment of Set, not the last keystroke.
        if !text.isEmpty { parsed = ScheduleInput.resolve(text, now: clock(), calendar: calendar) }
        guard !committed, let date = ScheduleCommit.dateToSet(for: parsed, draft: draft) else { return nil }
        draft = date
        return finish(Outcome(date: date, presetPick: nil,
                              consumesSuggestion: ScheduleCommit.consumesSuggestion(initialText: initialText, action: .set)))
    }

    /// A preset card / ⌘1…⌘6: one click commits.
    func apply(_ preset: DatePreset) -> Outcome? {
        guard !committed else { return nil }
        let date = DatePreset.date(for: preset, now: clock(), calendar: calendar)
        return finish(Outcome(date: date, presetPick: PresetPick(preset: preset, date: date),
                              consumesSuggestion: ScheduleCommit.consumesSuggestion(initialText: initialText, action: .preset)))
    }

    /// Clear: the reminder loses its date; the title keeps its phrase.
    func clear() -> Outcome? {
        guard !committed else { return nil }
        return finish(Outcome(date: nil, presetPick: nil,
                              consumesSuggestion: ScheduleCommit.consumesSuggestion(initialText: initialText, action: .clear)))
    }

    private func finish(_ outcome: Outcome) -> Outcome {
        committed = true
        announcement?.cancel()
        return outcome
    }

    /// What ✓ (save the reminder) does while the in-notch section is open.
    enum SaveDecision: Equatable {
        /// Nothing was touched: close the section, save with the reminder's current date (an
        /// untouched default such as tomorrow 9:00 never sneaks into a reminder).
        case saveAsIs
        /// The user changed the draft: what they see is what gets saved — Set, then save.
        case commitThenSave(Outcome)
        /// The typed text is not a date: beep, keep the section open, save nothing.
        case invalid
    }

    func prepareSave() -> SaveDecision {
        guard isDirty, !committed else { return .saveAsIs }
        guard let outcome = set() else { return .invalid }
        return .commitThenSave(outcome)
    }

    /// The one preset card to highlight for the current draft.
    func highlightedPreset(picked: PresetPick?) -> DatePreset? {
        DatePreset.highlighted(for: draft, picked: picked, now: clock(), calendar: calendar)
    }

    // MARK: VoiceOver

    /// VoiceOver does not read value changes of an element it is not focused on, so the preview is
    /// announced ~400 ms after typing pauses (once per pause, not per character).
    func announceAfterPause(_ message: @escaping @MainActor () -> String) {
        announcement?.cancel()
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        announcement = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard let self, !Task.isCancelled, !self.committed else { return }
            AccessibilityNotification.Announcement(message()).post()
        }
    }

    func cancelAnnouncement() { announcement?.cancel() }
}
