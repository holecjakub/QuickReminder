import AppKit
import SwiftUI

/// "Set Date" popover: type a date, pick a preset, or adjust day and time — no clock face.
///
/// The draft, the typed field and every commit decision live in `ScheduleDraft`, shared with the
/// in-notch section. A preset is a one-click commit. Nothing is written to `selectedDate` until
/// Set / ↩ / a preset / Clear: Esc or a click outside leaves the reminder as it was.
struct SchedulePopover: View {
    @Binding var selectedDate: Date?
    @Binding var isPresented: Bool
    /// Which preset wrote the date; Set Date highlights only that one (`DatePreset.highlighted`).
    @Binding var presetPick: PresetPick?
    let accent: Color
    /// Strips that phrase from the title (Tab semantics) on any commit that writes a date, see
    /// `ScheduleCommit.consumesSuggestion`.
    let onConsumeSuggestion: () -> Void

    private enum Field: Hashable { case text, time, calendar }

    @State private var model: ScheduleDraft
    @State private var showCalendar = false
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
    private static let chipHours = ScheduleText.chipHours
    private static let placeholder = ScheduleText.placeholder
    private static var invalidExample: String { ScheduleText.invalidExample }

    /// - Parameter initialText: the title's live, undismissed date phrase ("zítra ve 2"), prefilled.
    init(selectedDate: Binding<Date?>, isPresented: Binding<Bool>, presetPick: Binding<PresetPick?>, accent: Color,
         initialText: String?, onConsumeSuggestion: @escaping () -> Void) {
        _selectedDate = selectedDate
        _isPresented = isPresented
        _presetPick = presetPick
        self.accent = accent
        self.onConsumeSuggestion = onConsumeSuggestion
        _model = State(initialValue: ScheduleDraft(selected: selectedDate.wrappedValue, initialText: initialText))
    }

    private var draft: Date { model.draft }
    private var isInvalid: Bool { model.isInvalid }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            typeField
            previewLine
            presetGrid
            dayTimeRow
            if showCalendar {
                calendar
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
            }
            footer
        }
        .padding(14)
        .frame(width: Theme.s(300))
        .preferredColorScheme(.dark)
        .tint(accent)
        .background(commandReturnTwin)
        .onChange(of: model.text) { _, _ in model.announceAfterPause { previewSpoken(now: AppClock.now) } }
        .onDisappear { model.cancelAnnouncement() }
        .onAppear {
            // One runloop later, like the location popover: the popover window is not key yet.
            DispatchQueue.main.async { focus = .text }
        }
    }

    // MARK: Type field

    private var typeField: some View {
        HStack(spacing: 8) {
            Image(systemName: "text.cursor")
                .font(.system(size: Theme.s(12), weight: .medium))
                .foregroundStyle(accent)
            TextField("", text: $model.text, prompt: Text(Self.placeholder).foregroundStyle(.white.opacity(0.5)))
                .textFieldStyle(.plain)
                .font(.system(size: Theme.s(13)))
                .focused($focus, equals: .text)
                .onSubmit(commit)
                .accessibilityLabel("Type a date")
                // The typed text stays the field's value; the hint carries what it resolves to,
                // so it is read when focus lands on the field.
                .accessibilityHint(model.text.isEmpty ? "For example \(Self.invalidExample)" : previewSpoken(now: AppClock.now))
            if !model.text.isEmpty, model.textIsDate {
                KeyHint("⏎")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: Theme.s(30))
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.06))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.pillStroke, lineWidth: 1))
        )
    }

    // MARK: Preview

    private var previewLine: some View {
        let now = AppClock.now
        return HStack(spacing: 4) {
            if isInvalid {
                Text("Not a date — try “\(Self.invalidExample)”")
                    .foregroundStyle(.white.opacity(0.6))
            } else if draft < now {
                Image(systemName: "exclamationmark.triangle")
                Text("In the past")
                Text("· " + Self.formatter.dayAndTime(draft))
                    .foregroundStyle(.white.opacity(0.6))
            } else {
                Text(Self.formatter.dayAndTime(draft))
                    .foregroundStyle(accent)
                Text("· " + Self.relative.localizedString(for: draft, relativeTo: now))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .foregroundStyle(Theme.flagOrange)
        .font(.system(size: Theme.s(12), weight: .medium))
        .lineLimit(1)
        .frame(height: Theme.s(20), alignment: .leading)   // fixed, so nothing below jumps
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Reminder date")
        .accessibilityValue(previewSpoken(now: now))
    }

    private func previewSpoken(now: Date) -> String {
        if isInvalid { return "Not a date" }
        let date = Self.formatter.dayAndTime(draft)
        return draft < now ? "In the past, \(date)" : date
    }

    // MARK: Presets

    private var presetGrid: some View {
        let now = AppClock.now
        // Only one card lights up even when several presets land on the same minute.
        let highlighted = model.highlightedPreset(picked: presetPick)
        let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
        return LazyVGrid(columns: columns, spacing: 8) {
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
        return Button { finish(model.apply(preset)) } label: {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: DatePreset.systemImage(for: preset))
                    .font(.system(size: Theme.s(13), weight: .medium))
                    .foregroundStyle(accent)
                    .frame(width: Theme.s(18))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: Theme.s(13), weight: .medium))
                        .foregroundStyle(.white)
                    HStack(spacing: 4) {
                        Text(detail)
                            .foregroundStyle(.white.opacity(0.6))
                        Spacer(minLength: 2)
                        Text("⌘\(number)")
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .font(.system(size: Theme.s(11)))
                }
                .lineLimit(1)
                .minimumScaleFactor(0.75)   // "Tomorrow Evening" at large text sizes
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: Theme.s(44), alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(PresetCardStyle(selected: selected, accent: accent))
        .keyboardShortcut(KeyEquivalent(Character("\(number)")), modifiers: .command)
        .accessibilityLabel("\(title), \(Self.formatter.presetDetail(date, now: now, spoken: true)), Command \(number)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: Day + time

    private var dayBinding: Binding<Date> {
        Binding(get: { model.draft }, set: { day in model.pick(day: day) })
    }

    private var timeBinding: Binding<Date> {
        Binding(get: { model.draft }, set: { time in model.setFromControls(ScheduleDefaults.compose(day: model.draft, time: time)) })
    }

    private var dayTimeRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button(action: toggleCalendar) {
                    HStack(spacing: 5) {
                        Text(Self.formatter.string(from: draft, template: "EEE d MMM"))
                            .font(.system(size: Theme.s(13), weight: .medium))
                            .foregroundStyle(.white)
                        Image(systemName: "chevron.down")
                            .font(.system(size: Theme.s(10), weight: .semibold))
                            .foregroundStyle(accent)
                            .rotationEffect(.degrees(showCalendar ? 180 : 0))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut("k", modifiers: .command)
                .help("Calendar ⌘K")
                .accessibilityLabel("Calendar")
                .accessibilityValue(Self.formatter.string(from: draft, template: "EEEE d MMMM"))
                .accessibilityHint(showCalendar ? "Hides the calendar" : "Shows the calendar")

                Spacer(minLength: 8)

                DatePicker("Time", selection: timeBinding, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.field)
                    .labelsHidden()
                    .focused($focus, equals: .time)
            }

            HStack(spacing: 6) {
                ForEach(Self.chipHours, id: \.self) { hour in
                    timeChip(hour)
                }
            }
        }
    }

    private func timeChip(_ hour: Int) -> some View {
        let date = ScheduleDefaults.at(hour: hour, minute: 0, on: draft)
        let parts = Calendar.current.dateComponents([.hour, .minute], from: draft)
        let selected = parts.hour == hour && parts.minute == 0
        return Button { model.setTime(hour: hour) } label: {
            Text(Self.formatter.time(from: date))
                .font(.system(size: Theme.s(11), weight: .medium).monospacedDigit())
                .foregroundStyle(selected ? AccentContrast.label(on: accent) : Color.white.opacity(0.75))
                .padding(.horizontal, 9)
                .frame(height: Theme.s(22))
                .background(Capsule().fill(selected ? accent : Color.white.opacity(0.07)))
                .contentShape(Capsule())
        }
        .buttonStyle(HoverButtonStyle())
        .accessibilityLabel("Set time to \(Self.formatter.time(from: date))")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var calendar: some View {
        // Date component only: a `.graphical` picker with `.hourAndMinute` would draw the clock.
        DatePicker("Day", selection: dayBinding, in: Calendar.current.startOfDay(for: AppClock.now)..., displayedComponents: .date)
            .datePickerStyle(.graphical)
            .labelsHidden()
            .focused($focus, equals: .calendar)
            .frame(maxWidth: .infinity)   // the native calendar does not scale with text size; centre it
    }

    private func toggleCalendar() {
        let animation: Animation = reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.32, dampingFraction: 0.86)
        let calendarHadFocus = focus == .calendar
        withAnimation(animation) { showCalendar.toggle() }
        if showCalendar {
            DispatchQueue.main.async { focus = .calendar }
        } else if calendarHadFocus {
            // The focused calendar just left the hierarchy; hand the keys back to the field.
            DispatchQueue.main.async { focus = .text }
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 8) {
            if selectedDate != nil {
                Button("Clear") { finish(model.clear()) }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button("Cancel") { isPresented = false }
                .keyboardShortcut(.cancelAction)
            // The label picks its colour against the list's accent (white on orange / yellow fails).
            Button(action: commit) {
                Text("Set · \(Self.formatter.presetDetail(draft, now: AppClock.now))")
                    .foregroundStyle(isInvalid ? Color.white : AccentContrast.label(on: accent))
            }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(isInvalid)
        }
        .padding(.top, 2)
    }

    /// ⌘↩ is Set too (the panel's ⌘↩ save does not reach a popover window). Invisible, still in
    /// the responder chain — `.hidden()` would also drop the shortcut.
    private var commandReturnTwin: some View {
        Button("", action: commit)
            .keyboardShortcut(.return, modifiers: .command)
            .opacity(0)
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    // MARK: Commit

    private func commit() {
        guard let outcome = model.set() else {
            if !model.committed { NSSound.beep() }   // not a date: stay open
            return
        }
        finish(outcome)
    }

    private func finish(_ outcome: ScheduleDraft.Outcome?) {
        guard let outcome else { return }
        selectedDate = outcome.date
        presetPick = outcome.presetPick
        isPresented = false
        if outcome.consumesSuggestion { onConsumeSuggestion() }
    }
}

/// Preset card chrome: white 5 % at rest, 10 % on hover, accent 18 % + 1 pt accent stroke when it
/// matches the current draft.
private struct PresetCardStyle: ButtonStyle {
    let selected: Bool
    let accent: Color
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 10)
        return configuration.label
            .background(shape.fill(fill(pressed: configuration.isPressed)))
            .overlay(shape.strokeBorder(selected ? accent : .clear, lineWidth: 1))
            .animation(HoverMotion.highlightAnimation, value: hovering)
            .onHover { isHovering in
                guard isHovering != hovering else { return }
                hovering = isHovering
                HoverMotion.updateCursor(hovering: isHovering)
            }
    }

    private func fill(pressed: Bool) -> Color {
        if selected { return accent.opacity(pressed ? 0.26 : 0.18) }
        if pressed { return .white.opacity(0.14) }
        return .white.opacity(hovering ? 0.10 : 0.05)
    }
}
