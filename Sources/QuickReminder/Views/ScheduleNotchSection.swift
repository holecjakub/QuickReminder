import AppKit
import SwiftUI

/// Set Date inside the black notch panel (Settings → Date picker style → In notch).
///
/// Same capabilities and rules as `SchedulePopover` (type field with live preview, six presets on
/// ⌘1…⌘6, day + typed time with 9/12/15/19 chips, date-only calendar on ⌘K, Clear · Cancel ·
/// Set), restyled for pure black: white/grey text, white-alpha fills instead of glass, the list's
/// accent for selection and Set, corners concentric with the panel (`ScheduleMetrics.controlRadius`).
/// The panel grows to fit (`NotchLayout.scheduleContentHeight`); every row's height comes from
/// `NotchLayout.ScheduleMetrics`, so the blob always ends exactly 20 pt below the footer.
///
/// One source of truth, `draft`, exactly like the popover: typing resolves on every keystroke and
/// moves the controls one-way; the calendar, time field and chips write `draft` and clear the text.
/// Nothing reaches `selectedDate` until Set / ↩ / a preset.
struct ScheduleNotchSection: View {
    @Binding var selectedDate: Date?
    @Binding var isPresented: Bool
    /// Which preset wrote the date; Set Date highlights only that one (`DatePreset.highlighted`).
    @Binding var presetPick: PresetPick?
    let accent: Color
    /// The live, undismissed title suggestion phrase, prefilled into the field.
    let initialText: String?
    /// Strips that phrase from the title (`ScheduleCommit.consumesSuggestion`).
    let onConsumeSuggestion: () -> Void
    /// The month grid is shown (the blob is at its tallest).
    let showsCalendar: Bool
    let onToggleCalendar: () -> Void

    private enum Field: Hashable { case text, time, calendar }
    private typealias M = NotchLayout.ScheduleMetrics

    @State private var draft: Date
    @State private var text: String
    @State private var timeText: String = ""
    @State private var committed = false
    @State private var appeared = false
    @State private var announcement: Task<Void, Never>?
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

    init(selectedDate: Binding<Date?>, isPresented: Binding<Bool>, presetPick: Binding<PresetPick?>, accent: Color, initialText: String?,
         onConsumeSuggestion: @escaping () -> Void, showsCalendar: Bool, onToggleCalendar: @escaping () -> Void) {
        _selectedDate = selectedDate
        _isPresented = isPresented
        _presetPick = presetPick
        self.accent = accent
        self.initialText = initialText
        self.onConsumeSuggestion = onConsumeSuggestion
        self.showsCalendar = showsCalendar
        self.onToggleCalendar = onToggleCalendar
        let opening = ScheduleCommit.opening(selected: selectedDate.wrappedValue, initialText: initialText, now: AppClock.now)
        _draft = State(initialValue: opening.draft)
        _text = State(initialValue: opening.text)
    }

    private var parsed: ScheduleInput.Result { ScheduleInput.resolve(text, now: AppClock.now) }
    private var isInvalid: Bool { parsed == .invalid }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The rows scroll only when the screen clamps the panel (`NotchLayout.maxPanelHeight`);
            // otherwise the panel is exactly as tall as they are and nothing moves. Footer pinned.
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    rows
                }
                .scrollBounceBehavior(.basedOnSize)
                .onChange(of: showsCalendar) { _, shown in
                    guard shown else { return }
                    // Clamped: bring the grid into view as it opens (a no-op when everything fits).
                    DispatchQueue.main.async {
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) { proxy.scrollTo(Self.calendarID, anchor: .bottom) }
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
        .onReceive(NotificationCenter.default.publisher(for: .scheduleCommitRequested)) { _ in commit() }
        .onChange(of: text) { _, newValue in
            if case let .date(date) = parsed { draft = date }
            announcePreview(for: newValue)
        }
        .onChange(of: draft) { _, _ in if focus != .time { syncTimeText() } }
        .onChange(of: focus) { old, new in
            if old == .time && new != .time { applyTypedTime(beepOnInvalid: false) }
        }
        .onChange(of: showsCalendar) { _, shown in
            if shown {
                DispatchQueue.main.async { focus = .calendar }
            } else if focus == .calendar || focus == nil {
                // The focused grid just left the hierarchy; hand the keys back to the field.
                DispatchQueue.main.async { focus = .text }
            }
        }
        .onAppear {
            syncTimeText()
            appeared = true
            DispatchQueue.main.async { focus = .text }
        }
        .onDisappear { announcement?.cancel() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Set Date")
    }

    private static let calendarID = "calendar"

    /// Everything above the footer: field, preview, presets, day + time, and the month grid.
    private var rows: some View {
        VStack(alignment: .leading, spacing: 0) {
            typeField
                .padding(.top, M.topGap)
                .staggered(0, appeared: appeared, reduceMotion: reduceMotion)
            previewLine
                .padding(.top, M.previewGap)
                .staggered(0, appeared: appeared, reduceMotion: reduceMotion)
            presetGrid
                .padding(.top, M.presetsGap)
                .staggered(1, appeared: appeared, reduceMotion: reduceMotion)
            dayTimeRow
                .padding(.top, M.dayTimeGap)
                .staggered(2, appeared: appeared, reduceMotion: reduceMotion)
            if showsCalendar {
                ScheduleMonthGrid(
                    draft: draft,
                    accent: accent,
                    keyboardFocused: focus == .calendar,
                    onPick: pickDay
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
            TextField("", text: $text, prompt: Text(ScheduleText.placeholder).foregroundStyle(.white.opacity(0.3)))
                .textFieldStyle(.plain)
                .font(.system(size: Theme.s(14)))
                .foregroundStyle(.white)
                .focused($focus, equals: .text)
                .onSubmit(commit)
                .accessibilityLabel("Type a date")
                .accessibilityHint(text.isEmpty ? "For example \(ScheduleText.invalidExample)" : previewSpoken(now: AppClock.now))
            if !text.isEmpty, case .date = parsed {
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
        let now = AppClock.now
        return HStack(spacing: 4) {
            if isInvalid {
                Text("Not a date — try “\(ScheduleText.invalidExample)”")
                    .foregroundStyle(.white.opacity(0.45))
            } else if draft < now {
                Image(systemName: "exclamationmark.triangle.fill")
                Text("In the past")
                Text("· " + Self.formatter.dayAndTime(draft))
                    .foregroundStyle(.white.opacity(0.45))
            } else {
                Text(Self.formatter.dayAndTime(draft))
                    .foregroundStyle(.white)
                Text("· " + Self.relative.localizedString(for: draft, relativeTo: now))
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
        .foregroundStyle(Theme.flagOrange)
        .font(.system(size: Theme.s(12), weight: .medium).monospacedDigit())
        .lineLimit(1)
        .padding(.leading, 12)   // aligned with the field's text
        .frame(height: Theme.s(M.preview), alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Reminder date")
        .accessibilityValue(previewSpoken(now: now))
    }

    private func previewSpoken(now: Date) -> String {
        if isInvalid { return "Not a date" }
        let date = Self.formatter.dayAndTime(draft)
        return draft < now ? "In the past, \(date)" : date
    }

    /// VoiceOver does not read value changes of an element it is not focused on, so the preview is
    /// announced ~400 ms after the last keystroke (same as the popover).
    private func announcePreview(for newText: String) {
        announcement?.cancel()
        guard !newText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        announcement = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, !committed else { return }
            AccessibilityNotification.Announcement(previewSpoken(now: AppClock.now)).post()
        }
    }

    // MARK: Presets (3 × 2)

    private var presetGrid: some View {
        let now = AppClock.now
        // Only one card lights up even when several presets land on the same minute.
        let highlighted = DatePreset.highlighted(for: draft, picked: presetPick, now: now)
        let columns = Array(repeating: GridItem(.flexible(), spacing: M.presetSpacing), count: 3)
        return LazyVGrid(columns: columns, spacing: M.presetSpacing) {
            ForEach(Array(DatePreset.allCases.enumerated()), id: \.element) { index, preset in
                presetCard(preset, number: index + 1, now: now, highlighted: highlighted)
            }
        }
    }

    private func presetCard(_ preset: DatePreset, number: Int, now: Date, highlighted: DatePreset?) -> some View {
        let date = DatePreset.date(for: preset, now: now)
        let title = DatePreset.title(for: preset, now: now)
        let detail = Self.formatter.presetDetail(date, now: now)
        let selected = preset == highlighted
        return Button { apply(preset) } label: {
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
                            .foregroundStyle(.white.opacity(0.3))
                    }
                    Text(detail)
                        .font(.system(size: Theme.s(11)).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.5))
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
        HStack(spacing: 6) {
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
                        .foregroundStyle(.white.opacity(0.45))
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

    /// Typed digital time: "14", "1430", "14:30", "2pm" (read by `ScheduleInput`, time part only),
    /// ↑/↓ step by 15 minutes. Applied on ↩ or when focus leaves; invalid input beeps and reverts.
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
                .onKeyPress(.upArrow) { stepTime(by: 1); return .handled }
                .onKeyPress(.downArrow) { stepTime(by: -1); return .handled }
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
        timeText = Self.formatter.time(from: draft)
    }

    private func applyTypedTime(beepOnInvalid: Bool) {
        let typed = timeText.trimmingCharacters(in: .whitespaces)
        guard typed != Self.formatter.time(from: draft) else { return }
        if case let .date(time) = ScheduleInput.resolve(typed, now: AppClock.now) {
            setFromControls(ScheduleDefaults.compose(day: draft, time: time))
        } else if beepOnInvalid {
            NSSound.beep()
        }
        syncTimeText()
    }

    private func stepTime(by steps: Int) {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: draft)
        let minutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        // Snap to the 15-minute grid first, then step; wraps within the day.
        let snapped = steps > 0 ? (minutes / 15 + 1) * 15 : ((minutes + 14) / 15 - 1) * 15
        let wrapped = (snapped % 1440 + 1440) % 1440
        setFromControls(ScheduleDefaults.at(hour: wrapped / 60, minute: wrapped % 60, on: draft))
        syncTimeText()
    }

    private func timeChip(_ hour: Int) -> some View {
        let date = ScheduleDefaults.at(hour: hour, minute: 0, on: draft)
        let parts = Calendar.current.dateComponents([.hour, .minute], from: draft)
        let selected = parts.hour == hour && parts.minute == 0
        return Button { setFromControls(date); syncTimeText() } label: {
            Text(Self.formatter.time(from: date))
                .font(.system(size: Theme.s(12), weight: .medium).monospacedDigit())
                .foregroundStyle(selected ? Color.white : Color.white.opacity(0.7))
                .padding(.horizontal, 10)
                .frame(height: Theme.s(M.dayTimeRow))
                .contentShape(Capsule())
        }
        .buttonStyle(NotchFillButtonStyle(kind: selected ? .prominent : .neutral, accent: accent, radius: nil))
        .accessibilityLabel("Set time to \(Self.formatter.time(from: date))")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func pickDay(_ day: Date) {
        setFromControls(ScheduleDefaults.compose(day: day, time: draft))
    }

    /// Arrow keys in the focused grid: ±1 / ±7 days, never into the past.
    private func moveDay(_ days: Int) -> KeyPress.Result {
        let moved = MonthGrid.moving(draft, byDays: days, earliest: AppClock.now)
        if moved != draft { setFromControls(moved) } else { NSSound.beep() }
        return .handled
    }

    private func setFromControls(_ date: Date) {
        draft = date
        text = ""
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 8) {
            if selectedDate != nil {
                Button("Clear") {
                    selectedDate = nil
                    presetPick = nil
                    isPresented = false
                }
                .buttonStyle(NotchTextButtonStyle())
                .accessibilityHint("Removes the date from the reminder")
            }
            Spacer(minLength: 0)
            Button { isPresented = false } label: {
                Text("Cancel")
                    .font(.system(size: Theme.s(13), weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 16)
                    .frame(height: Theme.s(M.footer))
            }
            .buttonStyle(NotchFillButtonStyle(kind: .neutral, accent: accent, radius: M.controlRadius))
            Button(action: commit) {
                Text("Set · \(Self.formatter.presetDetail(draft, now: AppClock.now))")
                    .font(.system(size: Theme.s(13), weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .frame(height: Theme.s(M.footer))
                    .contentTransition(.numericText())
            }
            .buttonStyle(NotchFillButtonStyle(kind: .prominent, accent: accent, radius: M.controlRadius))
            .disabled(isInvalid)
            .keyboardShortcut(.defaultAction)
            .accessibilityLabel("Set, \(Self.formatter.presetDetail(draft, now: AppClock.now, spoken: true))")
        }
        .frame(height: Theme.s(M.footer))
    }

    /// ⌘↩ is Set too (the bottom bar and its ⌘↩ save are not shown while the section is open).
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

    // MARK: Commit (same decisions as the popover, `ScheduleCommit`)

    private func commit() {
        guard !committed else { return }
        if focus == .time { applyTypedTime(beepOnInvalid: false) }
        guard let date = ScheduleCommit.dateToSet(for: parsed, draft: draft) else {
            NSSound.beep()
            return
        }
        draft = date
        presetPick = nil   // typed / manual: the highlight falls back to the first matching preset
        finish(with: date, action: .set)
    }

    private func apply(_ preset: DatePreset) {
        guard !committed else { return }
        let date = DatePreset.date(for: preset, now: AppClock.now)
        presetPick = PresetPick(preset: preset, date: date)
        finish(with: date, action: .preset)
    }

    private func finish(with date: Date, action: ScheduleCommit.Action) {
        committed = true
        announcement?.cancel()
        selectedDate = date
        isPresented = false
        if ScheduleCommit.consumesSuggestion(initialText: initialText, action: action) { onConsumeSuggestion() }
    }
}

// MARK: - Month grid

/// Compact month grid for black: always six weeks (`MonthGrid`), today in the accent, the picked
/// day in an accent disc, the past dimmed and disabled. Arrow keys move the day while the grid is
/// focused (⌘K focuses it; handled by the section); ‹ › page the month. VoiceOver reads each day by its full name.
private struct ScheduleMonthGrid: View {
    let draft: Date
    let accent: Color
    /// The grid has the keyboard: the picked day shows a focus ring.
    let keyboardFocused: Bool
    let onPick: (Date) -> Void

    private typealias M = NotchLayout.ScheduleMetrics
    @State private var month: Date

    private static let formatter = SuggestionDateFormatter()

    init(draft: Date, accent: Color, keyboardFocused: Bool, onPick: @escaping (Date) -> Void) {
        self.draft = draft
        self.accent = accent
        self.keyboardFocused = keyboardFocused
        self.onPick = onPick
        _month = State(initialValue: MonthGrid.startOfMonth(draft))
    }

    var body: some View {
        let now = AppClock.now
        let calendar = Calendar.current
        VStack(spacing: 0) {
            header(now: now)
                .frame(height: Theme.s(M.monthHeader))
            HStack(spacing: 0) {
                ForEach(Array(zip(MonthGrid.weekdaySymbols(), MonthGrid.fullWeekdaySymbols()).enumerated()), id: \.offset) { _, pair in
                    Text(pair.0)
                        .font(.system(size: Theme.s(10), weight: .semibold))
                        .foregroundStyle(.white.opacity(0.35))
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel(pair.1)
                }
            }
            .frame(height: Theme.s(M.weekdayRow))
            .accessibilityHidden(true)
            let cells = MonthGrid.cells(for: month)
            VStack(spacing: M.dayRowSpacing) {
                ForEach(0..<MonthGrid.weeks, id: \.self) { week in
                    HStack(spacing: 0) {
                        ForEach(0..<7, id: \.self) { column in
                            dayCell(cells[week * 7 + column], now: now, calendar: calendar)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .frame(height: Theme.s(M.dayCell))
                }
            }
        }
        .onChange(of: draft) { _, newDraft in
            // Keyboard movement into another month follows it.
            let first = MonthGrid.startOfMonth(newDraft)
            if first != month { withAnimation(.easeOut(duration: 0.15)) { month = first } }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Calendar, \(Self.formatter.string(from: month, template: "MMMM y"))")
    }

    private func header(now: Date) -> some View {
        HStack(spacing: 2) {
            Text(Self.formatter.string(from: month, template: "LLLL y"))
                .font(.system(size: Theme.s(13), weight: .semibold))
                .foregroundStyle(.white)
                .contentTransition(.opacity)
                .padding(.leading, 4)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            pageButton("chevron.left", label: "Previous month", enabled: MonthGrid.canGoBack(from: month, now: now)) { page(-1) }
            pageButton("chevron.right", label: "Next month", enabled: true) { page(1) }
        }
    }

    private func pageButton(_ symbol: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: Theme.s(11), weight: .semibold))
                .foregroundStyle(.white.opacity(enabled ? 0.75 : 0.2))
                .frame(width: Theme.s(26), height: Theme.s(26))
                .contentShape(Circle())
        }
        .buttonStyle(HoverHighlightButtonStyle())
        .disabled(!enabled)
        .accessibilityLabel(label)
    }

    @ViewBuilder
    private func dayCell(_ day: Date?, now: Date, calendar: Calendar) -> some View {
        if let day {
            let selectable = MonthGrid.isSelectable(day, now: now, calendar: calendar)
            let selected = calendar.isDate(day, inSameDayAs: draft)
            let today = calendar.isDate(day, inSameDayAs: now)
            Button { onPick(day) } label: {
                Text("\(calendar.component(.day, from: day))")
                    .font(.system(size: Theme.s(13), weight: selected || today ? .semibold : .regular).monospacedDigit())
                    .foregroundStyle(foreground(selected: selected, today: today, selectable: selectable))
                    .frame(width: Theme.s(M.dayCell), height: Theme.s(M.dayCell))
                    .background(Circle().fill(selected ? accent : .clear))
                    // Keyboard focus shows on the picked day (the grid itself draws no ring).
                    .overlay(Circle().strokeBorder(.white.opacity(selected && keyboardFocused ? 0.85 : 0), lineWidth: 1.5).padding(-3))
                    // The whole cell clicks (≈ 74 × 30 pt), not just the 28 pt disc.
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(DayCellStyle(selected: selected))
            .disabled(!selectable)
            .accessibilityLabel(Self.formatter.string(from: day, template: "EEEE d MMMM"))
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityHint(today ? "Today" : "")
        } else {
            Color.clear.accessibilityHidden(true)
        }
    }

    private func foreground(selected: Bool, today: Bool, selectable: Bool) -> Color {
        if selected { return .white }
        if !selectable { return .white.opacity(0.2) }
        if today { return accent }
        return .white.opacity(0.85)
    }

    private func page(_ months: Int) {
        let target = MonthGrid.shiftMonth(month, by: months)
        guard months > 0 || MonthGrid.canGoBack(from: month, now: AppClock.now) else { return }
        withAnimation(.easeOut(duration: 0.15)) { month = target }
    }
}

/// Day cell: a soft white disc on hover, nothing else (the picked day carries the accent disc).
private struct DayCellStyle: ButtonStyle {
    let selected: Bool
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                Circle()
                    .fill(Color.white.opacity(!selected && isEnabled && (hovering || configuration.isPressed)
                                              ? (configuration.isPressed ? 0.16 : 0.09) : 0))
            )
            .animation(HoverMotion.highlightAnimation, value: hovering)
            .onHover { isHovering in
                guard isEnabled, isHovering != hovering else { return }
                hovering = isHovering
                HoverMotion.updateCursor(hovering: isHovering)
            }
    }
}

// MARK: - Black-surface button chrome

/// Fills for controls on the pure black panel: white alpha instead of glass, the list accent for
/// selection and the primary action. Press: 0.97 scale (none with Reduce Motion).
struct NotchFillButtonStyle: ButtonStyle {
    enum Kind { case neutral, selected, prominent }
    let kind: Kind
    let accent: Color
    /// nil = capsule.
    let radius: CGFloat?

    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        return configuration.label
            .background(shape.fill(fill(pressed: pressed)))
            .overlay(shape.strokeBorder(kind == .selected ? accent.opacity(0.8) : .clear, lineWidth: 1))
            .opacity(isEnabled ? 1 : 0.55)
            .scaleEffect(pressed && !reduceMotion ? 0.97 : 1)
            .animation(HoverMotion.pressAnimation, value: pressed)
            .animation(HoverMotion.highlightAnimation, value: hovering)
            .onHover { isHovering in
                guard isHovering != hovering else { return }
                hovering = isHovering
                HoverMotion.updateCursor(hovering: isHovering && isEnabled)
            }
    }

    private var shape: AnyInsettableShape {
        if let radius { return AnyInsettableShape(RoundedRectangle(cornerRadius: radius, style: .continuous)) }
        return AnyInsettableShape(Capsule())
    }

    private func fill(pressed: Bool) -> Color {
        switch kind {
        case .neutral:
            if pressed { return .white.opacity(0.15) }
            return .white.opacity(hovering ? 0.11 : 0.06)
        case .selected:
            return accent.opacity(pressed ? 0.32 : (hovering ? 0.27 : 0.2))
        case .prominent:
            guard isEnabled else { return Theme.grayCircleDisabled }
            return accent.opacity(pressed ? 0.8 : (hovering ? 0.92 : 1))
        }
    }
}

/// Text-only action on black (Clear): grey, brightening on hover.
private struct NotchTextButtonStyle: ButtonStyle {
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: Theme.s(13), weight: .medium))
            .foregroundStyle(.white.opacity(configuration.isPressed ? 0.95 : (hovering ? 0.8 : 0.5)))
            .padding(.horizontal, 8)
            .frame(height: Theme.s(NotchLayout.ScheduleMetrics.footer))
            .contentShape(Rectangle())
            .animation(HoverMotion.highlightAnimation, value: hovering)
            .onHover { isHovering in
                guard isHovering != hovering else { return }
                hovering = isHovering
                HoverMotion.updateCursor(hovering: isHovering)
            }
    }
}

/// Small keycap ("⏎") shown when the typed text resolves.
private struct KeyHint: View {
    let key: String
    init(_ key: String) { self.key = key }

    var body: some View {
        Text(key)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white.opacity(0.45))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(RoundedRectangle(cornerRadius: 4).fill(.white.opacity(0.1)))
            .accessibilityHidden(true)
    }
}

/// Type-erased insettable shape (rounded rectangle or capsule) for `NotchFillButtonStyle`.
struct AnyInsettableShape: InsettableShape {
    private let pathBuilder: @Sendable (CGRect) -> Path
    private let insetBuilder: @Sendable (CGFloat) -> AnyInsettableShape

    init<S: InsettableShape & Sendable>(_ shape: S) {
        pathBuilder = { shape.path(in: $0) }
        insetBuilder = { AnyInsettableShape(shape.inset(by: $0)) }
    }

    func path(in rect: CGRect) -> Path { pathBuilder(rect) }
    func inset(by amount: CGFloat) -> AnyInsettableShape { insetBuilder(amount) }
}

// MARK: - Stagger

private extension View {
    /// Rows settle in one after another (~35 ms apart) as the blob grows: a short drop and
    /// un-blur from where the bottom bar was. Reduce Motion: a plain fade with the section.
    func staggered(_ index: Int, appeared: Bool, reduceMotion: Bool) -> some View {
        self
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared || reduceMotion ? 0 : -6)
            .blur(radius: appeared || reduceMotion ? 0 : 3)
            .animation(reduceMotion ? .easeOut(duration: 0.15)
                       : .easeOut(duration: 0.24).delay(0.06 + Double(index) * 0.035), value: appeared)
    }
}
