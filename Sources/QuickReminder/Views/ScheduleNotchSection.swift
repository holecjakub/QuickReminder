import AppKit
import SwiftUI

/// Set Date inside the black notch panel (Settings → Date picker style → In notch).
///
/// Same capabilities and the same model as `SchedulePopover` (`ScheduleDraft`: type field with
/// live preview, six presets on ⌘1…⌘6, day + typed time with 9/12/15/19 chips, date-only calendar
/// on ⌘K, Clear · Cancel · Set), restyled for pure black: white/grey text, white-alpha fills
/// instead of glass, the list's accent for selection and Set (its label colour picked for
/// contrast, `AccentContrast`), corners concentric with the panel (`ScheduleMetrics.controlRadius`).
/// Appended below the plain panel's bottom bar, which stays exactly as it is: the blob only grows
/// downward (`NotchLayout.scheduleContentHeight`, clamped to the screen, only these rows scroll);
/// every row's height comes from `NotchLayout.ScheduleMetrics`.
///
/// Shown while `NotchState.section != .none` (the one source of truth); `onClose` asks the panel
/// to settle back. Nothing reaches `selectedDate` until Set / ↩ / a preset / Clear.
struct ScheduleNotchSection: View {
    @Binding var selectedDate: Date?
    /// Which preset wrote the date; Set Date highlights only that one (`DatePreset.highlighted`).
    @Binding var presetPick: PresetPick?
    let accent: Color
    /// Strips the title's date phrase (`ScheduleCommit.consumesSuggestion`).
    let onConsumeSuggestion: () -> Void
    /// The month grid is shown (the blob is at its tallest).
    let showsCalendar: Bool
    let onToggleCalendar: () -> Void
    /// Cancel or any commit: the panel settles back to its plain height.
    let onClose: () -> Void
    /// ✓ in the bottom bar while the section is open, once the section has decided
    /// (`ScheduleDraft.prepareSave`): save the reminder.
    let onSaveReminder: () -> Void

    private enum Field: Hashable { case text, time, calendar }
    private typealias M = NotchLayout.ScheduleMetrics

    @State private var model: ScheduleDraft
    @State private var timeText: String = ""
    @State private var calendarMonth: Date
    @State private var appeared = false
    @FocusState private var focus: Field?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let formatter = SuggestionDateFormatter()
    private static let relative: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.unitsStyle = .abbreviated
        formatter.dateTimeStyle = .numeric
        return formatter
    }()
    private static let calendarID = "calendar"
    private static let typeFieldID = "typeField"
    private static let dayTimeID = "dayTime"

    /// - Parameter initialText: the title's live, undismissed date phrase, prefilled into the field.
    init(selectedDate: Binding<Date?>, presetPick: Binding<PresetPick?>, accent: Color, initialText: String?,
         onConsumeSuggestion: @escaping () -> Void, showsCalendar: Bool,
         onToggleCalendar: @escaping () -> Void, onClose: @escaping () -> Void,
         onSaveReminder: @escaping () -> Void) {
        _selectedDate = selectedDate
        _presetPick = presetPick
        self.accent = accent
        self.onConsumeSuggestion = onConsumeSuggestion
        self.showsCalendar = showsCalendar
        self.onToggleCalendar = onToggleCalendar
        self.onClose = onClose
        self.onSaveReminder = onSaveReminder
        let model = ScheduleDraft(selected: selectedDate.wrappedValue, initialText: initialText)
        _model = State(initialValue: model)
        _calendarMonth = State(initialValue: MonthGrid.startOfMonth(model.draft))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The rows scroll only when the screen clamps the panel (`NotchLayout.maxPanelHeight`);
            // otherwise the panel is exactly as tall as they are and nothing moves. Footer pinned.
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    rows
                }
                .scrollBounceBehavior(.basedOnSize)
                // Clamped (large text, short screen): keep what has the keyboard in view — the
                // picked day's week while the grid is focused, the field / time row on focus.
                .onChange(of: model.draft) { _, draft in
                    guard focus == .calendar, let week = MonthGrid.week(of: draft) else { return }
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                        proxy.scrollTo(ScheduleMonthGrid.weekID(week), anchor: nil)
                    }
                }
                .onChange(of: focus) { _, field in
                    let id: String? = switch field {
                    case .text: Self.typeFieldID
                    case .time: Self.dayTimeID
                    case .calendar, nil: nil
                    }
                    guard let id else { return }
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { proxy.scrollTo(id, anchor: nil) }
                }
                .onChange(of: showsCalendar) { _, shown in
                    if shown {
                        DispatchQueue.main.async {
                            focus = .calendar
                            // Clamped: bring the grid into view as it opens (a no-op when it fits).
                            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) {
                                proxy.scrollTo(Self.calendarID, anchor: .bottom)
                            }
                        }
                    } else if focus == .calendar || focus == nil {
                        // The focused grid just left the hierarchy; hand the keys back to the field.
                        DispatchQueue.main.async { focus = .text }
                    }
                }
            }
            footer
                .padding(.top, M.footerGap)
                .staggered(3, appeared: appeared, reduceMotion: reduceMotion)
        }
        .tint(accent)
        .background(commandReturnTwin)
        .background(calendarShortcut)
        .onReceive(NotificationCenter.default.publisher(for: .sectionCommitRequested)) { _ in commit() }
        .onReceive(NotificationCenter.default.publisher(for: .sectionSaveRequested)) { _ in saveFromBar() }
        .onChange(of: model.text) { _, _ in model.announceAfterPause { previewSpoken() } }
        .onChange(of: model.draft) { _, newDraft in
            if focus != .time { syncTimeText() }
            // Keyboard movement into another month follows it.
            let first = MonthGrid.startOfMonth(newDraft)
            if first != calendarMonth { withAnimation(.easeOut(duration: 0.15)) { calendarMonth = first } }
        }
        .onChange(of: focus) { old, new in
            if old == .time && new != .time { applyTypedTime(beepOnInvalid: false) }
        }
        .onAppear {
            syncTimeText()
            appeared = true
            DispatchQueue.main.async { focus = .text }
        }
        .onDisappear { model.cancelAnnouncement() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Set Date")
    }

    /// Everything above the footer: field, preview, presets, day + time, and the month grid.
    private var rows: some View {
        VStack(alignment: .leading, spacing: 0) {
            typeField
                .id(Self.typeFieldID)
                .staggered(0, appeared: appeared, reduceMotion: reduceMotion)
            previewLine
                .padding(.top, M.previewGap)
                .staggered(0, appeared: appeared, reduceMotion: reduceMotion)
            presetGrid
                .padding(.top, M.presetsGap)
                .staggered(1, appeared: appeared, reduceMotion: reduceMotion)
            dayTimeRow
                .id(Self.dayTimeID)
                .padding(.top, M.dayTimeGap)
                .staggered(2, appeared: appeared, reduceMotion: reduceMotion)
            if showsCalendar {
                ScheduleMonthGrid(
                    draft: model.draft,
                    month: $calendarMonth,
                    accent: accent,
                    keyboardFocused: focus == .calendar,
                    onPick: { model.pick(day: $0) }
                )
                .focusable()
                .focusEffectDisabled()
                .focused($focus, equals: .calendar)
                .onKeyPress(.leftArrow) { moveDay(-1) }
                .onKeyPress(.rightArrow) { moveDay(1) }
                .onKeyPress(.upArrow) { moveDay(-7) }
                .onKeyPress(.downArrow) { moveDay(7) }
                .padding(.top, M.calendarGap)
                .id(Self.calendarID)
                .transition(reduceMotion
                    ? AnyTransition.opacity
                    : AnyTransition.opacity.combined(with: .offset(y: -8)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Type field

    private var typeField: some View {
        HStack(spacing: 8) {
            Image(systemName: "keyboard")
                .font(.system(size: Theme.s(12), weight: .medium))
                .foregroundStyle(.white.opacity(0.45))
                .accessibilityHidden(true)
            TextField("", text: $model.text, prompt: Text(ScheduleText.placeholder).foregroundStyle(.white.opacity(0.5)))
                .textFieldStyle(.plain)
                .font(.system(size: Theme.s(14)))
                .foregroundStyle(.white)
                .focused($focus, equals: .text)
                .onSubmit(commit)
                .accessibilityLabel("Type a date")
                .accessibilityHint(model.text.isEmpty ? "For example \(ScheduleText.invalidExample)" : previewSpoken())
            if !model.text.isEmpty, model.textIsDate {
                KeyHint("⏎")
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: Theme.s(M.typeField))
        .background(
            RoundedRectangle(cornerRadius: M.controlRadius, style: .continuous)
                .fill(Color.white.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: M.controlRadius, style: .continuous)
                .strokeBorder(focus == .text ? accent.opacity(0.7) : Color.white.opacity(0.08), lineWidth: 1)
        )
        .animation(.easeOut(duration: 0.15), value: focus == .text)
        .contentShape(Rectangle())
        .onTapGesture { focus = .text }
    }

    // MARK: Preview

    private var previewLine: some View {
        let now = model.now
        let draft = model.draft
        return HStack(spacing: 4) {
            if model.isInvalid {
                Text("Not a date — try “\(ScheduleText.invalidExample)”")
                    .foregroundStyle(.white.opacity(0.6))
            } else if draft < now {
                Image(systemName: "exclamationmark.triangle.fill")
                Text("In the past")
                Text("· " + Self.formatter.dayAndTime(draft))
                    .foregroundStyle(.white.opacity(0.6))
            } else {
                Text(Self.formatter.dayAndTime(draft))
                    .foregroundStyle(.white)
                Text("· " + Self.relative.localizedString(for: draft, relativeTo: now))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .foregroundStyle(Theme.flagOrange)
        .font(.system(size: Theme.s(12), weight: .medium).monospacedDigit())
        .lineLimit(1)
        .padding(.leading, 12)   // aligned with the field's text
        .frame(height: Theme.s(M.preview), alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Reminder date")
        .accessibilityValue(previewSpoken())
    }

    private func previewSpoken() -> String {
        if model.isInvalid { return "Not a date" }
        let date = Self.formatter.dayAndTime(model.draft)
        return model.draft < model.now ? "In the past, \(date)" : date
    }

    // MARK: Presets (3 × 2)

    private var presetGrid: some View {
        let now = model.now
        // Only one card lights up even when several presets land on the same minute.
        let highlighted = model.highlightedPreset(picked: presetPick)
        let columns = Array(repeating: GridItem(.flexible(), spacing: M.presetSpacing), count: 3)
        return LazyVGrid(columns: columns, spacing: M.presetSpacing) {
            ForEach(Array(DatePreset.allCases.enumerated()), id: \.element) { index, preset in
                presetCard(preset, number: index + 1, now: now, selected: preset == highlighted)
            }
        }
    }

    private func presetCard(_ preset: DatePreset, number: Int, now: Date, selected: Bool) -> some View {
        let date = DatePreset.date(for: preset, now: now)
        let title = DatePreset.title(for: preset, now: now)
        let detail = Self.formatter.presetDetail(date, now: now)
        return Button { finish(model.apply(preset)) } label: {
            HStack(alignment: .center, spacing: 9) {
                Image(systemName: DatePreset.systemImage(for: preset))
                    .font(.system(size: Theme.s(13), weight: .medium))
                    .foregroundStyle(accent)
                    .frame(width: Theme.s(18))
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(title)
                            .font(.system(size: Theme.s(13), weight: .medium))
                            .foregroundStyle(.white)
                        Spacer(minLength: 2)
                        Text("⌘\(number)")
                            .font(.system(size: Theme.s(10), weight: .medium))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    Text(detail)
                        .font(.system(size: Theme.s(11)).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.6))
                }
                .lineLimit(1)
                .minimumScaleFactor(0.75)   // "Tomorrow Evening" at large text sizes
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: Theme.s(M.presetRow), maxHeight: Theme.s(M.presetRow), alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: M.controlRadius, style: .continuous))
        }
        .buttonStyle(NotchFillButtonStyle(kind: selected ? .selected : .neutral, accent: accent, radius: M.controlRadius))
        .keyboardShortcut(KeyEquivalent(Character("\(number)")), modifiers: .command)
        .accessibilityLabel("\(title), \(Self.formatter.presetDetail(date, now: now, spoken: true)), Command \(number)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: Day + time

    private var dayTimeRow: some View {
        let draft = model.draft
        return HStack(spacing: 6) {
            Button(action: onToggleCalendar) {
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .font(.system(size: Theme.s(12), weight: .medium))
                        .foregroundStyle(accent)
                    Text(Self.formatter.string(from: draft, template: "EEE d MMM"))
                        .font(.system(size: Theme.s(13), weight: .medium).monospacedDigit())
                        .foregroundStyle(.white)
                    Image(systemName: "chevron.down")
                        .font(.system(size: Theme.s(9), weight: .bold))
                        .foregroundStyle(.white.opacity(0.5))
                        .rotationEffect(.degrees(showsCalendar ? 180 : 0))
                }
                .padding(.horizontal, 11)
                .frame(height: Theme.s(M.dayTimeRow))
                .contentShape(Capsule())
            }
            .buttonStyle(NotchFillButtonStyle(kind: showsCalendar ? .selected : .neutral, accent: accent, radius: nil))
            .help("Calendar ⌘K")
            .accessibilityLabel("Calendar")
            .accessibilityValue(Self.formatter.string(from: draft, template: "EEEE d MMMM"))
            .accessibilityHint(showsCalendar ? "Hides the calendar" : "Shows the calendar")

            timeField

            Spacer(minLength: 6)

            HStack(spacing: 4) {
                ForEach(ScheduleText.chipHours, id: \.self) { hour in
                    timeChip(hour)
                }
            }
        }
    }

    /// Typed digital time: "14", "1430", "14:30", "2pm" (`ScheduleDraft.applyTypedTime`), ↑/↓ step
    /// by 15 minutes. ↩ applies it and keeps the section open (the field consumes ↩, so Set's
    /// default action does not fire); leaving the field applies it too. Invalid input beeps and
    /// reverts.
    private var timeField: some View {
        HStack(spacing: 5) {
            Image(systemName: "clock")
                .font(.system(size: Theme.s(11), weight: .medium))
                .foregroundStyle(.white.opacity(0.45))
                .accessibilityHidden(true)
            TextField("", text: $timeText)
                .textFieldStyle(.plain)
                .font(.system(size: Theme.s(13), weight: .medium).monospacedDigit())
                .foregroundStyle(.white)
                .focused($focus, equals: .time)
                .onSubmit { applyTypedTime(beepOnInvalid: true) }
                .onKeyPress(.upArrow) { model.stepTime(by: 1); syncTimeText(); return .handled }
                .onKeyPress(.downArrow) { model.stepTime(by: -1); syncTimeText(); return .handled }
                .accessibilityLabel("Time")
                .accessibilityHint("Type a time, or use the up and down arrows to change it by 15 minutes")
        }
        .padding(.horizontal, 10)
        .frame(width: Theme.s(96), height: Theme.s(M.dayTimeRow))
        .background(Capsule().fill(Color.white.opacity(0.07)))
        .overlay(Capsule().strokeBorder(focus == .time ? accent.opacity(0.7) : .clear, lineWidth: 1))
        .animation(.easeOut(duration: 0.15), value: focus == .time)
        .contentShape(Capsule())
        .onTapGesture { focus = .time }
    }

    private func syncTimeText() {
        timeText = Self.formatter.time(from: model.draft)
    }

    /// false when the field holds something that is not a time (it reverts; beeps if asked).
    @discardableResult
    private func applyTypedTime(beepOnInvalid: Bool) -> Bool {
        let typed = timeText.trimmingCharacters(in: .whitespaces)
        var valid = true
        if typed != Self.formatter.time(from: model.draft), !model.applyTypedTime(typed) {
            valid = false
            if beepOnInvalid { NSSound.beep() }
        }
        syncTimeText()
        return valid
    }

    private func timeChip(_ hour: Int) -> some View {
        let date = ScheduleDefaults.at(hour: hour, minute: 0, on: model.draft)
        let parts = Calendar.current.dateComponents([.hour, .minute], from: model.draft)
        let selected = parts.hour == hour && parts.minute == 0
        return Button { model.setTime(hour: hour); syncTimeText() } label: {
            Text(Self.formatter.time(from: date))
                .font(.system(size: Theme.s(12), weight: .medium).monospacedDigit())
                .foregroundStyle(selected ? AccentContrast.label(on: accent) : Color.white.opacity(0.75))
                .padding(.horizontal, 10)
                .frame(height: Theme.s(M.dayTimeRow))
                .contentShape(Capsule())
        }
        .buttonStyle(NotchFillButtonStyle(kind: selected ? .prominent : .neutral, accent: accent, radius: nil))
        .accessibilityLabel("Set time to \(Self.formatter.time(from: date))")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// Arrow keys in the focused grid: ±1 / ±7 days, never into the past. After ‹ › paged away
    /// from the picked day, the first arrow lands in the visible month instead of jumping back.
    private func moveDay(_ days: Int) -> KeyPress.Result {
        if MonthGrid.startOfMonth(model.draft) != calendarMonth {
            model.moveInto(month: calendarMonth)
        } else if !model.moveDay(by: days) {
            NSSound.beep()
        }
        return .handled
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 8) {
            if selectedDate != nil {
                Button("Clear") { finish(model.clear()) }
                    .buttonStyle(NotchTextButtonStyle())
                    .accessibilityHint("Removes the date from the reminder")
            }
            Spacer(minLength: 0)
            Button(action: onClose) {
                Text("Cancel")
                    .font(.system(size: Theme.s(13), weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 16)
                    .frame(height: Theme.s(M.footer))
            }
            .buttonStyle(NotchFillButtonStyle(kind: .neutral, accent: accent, radius: M.controlRadius))
            Button(action: commit) {
                Text("Set · \(Self.formatter.presetDetail(model.draft, now: model.now))")
                    .font(.system(size: Theme.s(13), weight: .semibold).monospacedDigit())
                    .foregroundStyle(model.isInvalid ? Color.white : AccentContrast.label(on: accent))
                    .padding(.horizontal, 18)
                    .frame(height: Theme.s(M.footer))
                    .contentTransition(.numericText())
            }
            .buttonStyle(NotchFillButtonStyle(kind: .prominent, accent: accent, radius: M.controlRadius))
            .disabled(model.isInvalid)
            .keyboardShortcut(.defaultAction)
            .accessibilityLabel("Set, \(Self.formatter.presetDetail(model.draft, now: model.now, spoken: true))")
        }
        .frame(height: Theme.s(M.footer))
    }

    /// ⌘↩ is Set too (the bottom bar's ✓ gives up its ⌘↩ while the section is open).
    private var commandReturnTwin: some View {
        Button("", action: commit)
            .keyboardShortcut(.return, modifiers: .command)
            .opacity(0)
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    /// ⌘K toggles the month grid from anywhere in the section.
    private var calendarShortcut: some View {
        Button("", action: onToggleCalendar)
            .keyboardShortcut("k", modifiers: .command)
            .opacity(0)
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    // MARK: Commit (`ScheduleDraft` decides, the view writes)

    private func commit() {
        if focus == .time { applyTypedTime(beepOnInvalid: false) }
        guard let outcome = model.set() else {
            if !model.committed {   // not a date: stay open
                NSSound.beep()
                AccessibilityNotification.Announcement("Not a date").post()
            }
            return
        }
        finish(outcome)
    }

    /// ✓ while the section is open: see `ScheduleDraft.SaveDecision`.
    private func saveFromBar() {
        // An unreadable typed time must not be dropped silently on the way to saving.
        if focus == .time, !applyTypedTime(beepOnInvalid: true) {
            AccessibilityNotification.Announcement("Not a time. Nothing saved.").post()
            return
        }
        switch model.prepareSave() {
        case .saveAsIs:
            onClose()
            onSaveReminder()
        case .commitThenSave(let outcome):
            finish(outcome)
            onSaveReminder()
        case .invalid:
            NSSound.beep()
            AccessibilityNotification.Announcement("Not a date. Nothing saved.").post()
        }
    }

    private func finish(_ outcome: ScheduleDraft.Outcome?) {
        guard let outcome else { return }
        selectedDate = outcome.date
        presetPick = outcome.presetPick
        onClose()
        if outcome.consumesSuggestion { onConsumeSuggestion() }
    }
}
