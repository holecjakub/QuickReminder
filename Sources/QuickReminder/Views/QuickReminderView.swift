import SwiftUI

/// Root of the quick-reminder UI, laid out 1:1 with the iOS 26 overlay
/// (header → input → bottom bar), sitting below the notch band.
@MainActor
struct QuickReminderView: View {
    /// Height of the notch / menu-bar band the content must stay below.
    let notchBandHeight: CGFloat
    /// Geometry namespace shared with the saved badge (the ✓ flies into the notch on save).
    let saveNamespace: Namespace.ID
    /// True from the moment of saving until the window is ordered out: the save button has
    /// handed its geometry to the saved badge and must stay out of the hierarchy.
    let saveButtonYielded: Bool
    @ObservedObject private var remindersService = RemindersService.shared
    @AppStorage("selectedListId") private var selectedListId: String = ""
    @AppStorage(SetDateStyle.defaultsKey) private var pickerStyle: SetDateStyle = .defaultStyle
    @EnvironmentObject private var notch: NotchState

    @State private var title: String = ""
    @State private var notes: String = ""
    @State private var dueDate: Date? = nil
    @State private var flagged: Bool = false
    @State private var locationText: String = ""
    @State private var showListPicker: Bool = false
    @State private var showLocationField: Bool = false
    /// The Set Date popover (Popover style only). The in-notch section has no flag of its own: it
    /// is shown while `notch.schedule != .none`, the panel's single source of truth.
    @State private var showSchedulePopover: Bool = false
    @State private var saveErrorText: String? = nil
    @State private var suggestion: DateSuggestion? = nil
    @State private var dismissedSuggestionText: String? = nil
    /// The preset that wrote `dueDate`, if one did: Set Date highlights it rather than every preset
    /// landing on the same minute (`DatePreset.highlighted`).
    @State private var presetPick: PresetPick? = nil


    @Environment(\.listAccent) private var accent

    /// Something Esc should close before the panel (popovers, the in-notch section).
    private var anyPopoverShown: Bool { showListPicker || showLocationField || showSchedulePopover || schedulingInNotch }

    private var canSave: Bool { !title.trimmingCharacters(in: .whitespaces).isEmpty }

    /// The in-notch Set Date section is shown (the blob has grown for it). Driven by the panel's
    /// schedule state, so the section and the blob change in the same spring transaction.
    private var schedulingInNotch: Bool { notch.schedule != .none }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The physical notch / menu-bar band. Content starts below it.
            Color.clear.frame(height: notchBandHeight)

            HeaderView(
                remindersService: remindersService,
                selectedListId: $selectedListId,
                showListPicker: $showListPicker,
                onClose: { PanelController.shared.hide() }
            )
            .padding(.top, 8)

            InputView(
                title: $title,
                notes: $notes,
                onSubmit: submitFromTextRow,
                onTab: { applySuggestionIfAny() }
            )
            .padding(.top, 10)

            // The plain panel never changes for Set Date: chip slot and bottom bar stay put.
            regularBottom

            // In notch: Set Date is appended below the bottom bar; the blob grows downward only.
            if schedulingInNotch {
                ScheduleNotchSection(
                    selectedDate: $dueDate,
                    presetPick: $presetPick,
                    accent: accent,
                    initialText: dueDate == nil ? suggestion?.matchedText : nil,
                    onConsumeSuggestion: stripSuggestionPhrase,
                    showsCalendar: notch.schedule == .calendar,
                    onToggleCalendar: {
                        PanelController.shared.setSchedule(notch.schedule == .calendar ? .controls : .calendar)
                    },
                    onClose: { PanelController.shared.setSchedule(.none) },
                    onSaveReminder: { saveReminder(afterSetDate: true) }
                )
                // Takes the rest of the grown panel; only its rows scroll when the screen clamps the
                // height (everything above is the fixed plain panel).
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.bottom, Theme.horizontalPadding)
                // The section's rows stagger in themselves; leaving, it fades quicker than it came
                // while the blob retracts over it.
                .transition(.asymmetric(insertion: .opacity.animation(.easeOut(duration: 0.12)),
                                        removal: .opacity.animation(.easeOut(duration: 0.1))))
            }
        }
        .padding(.horizontal, Theme.horizontalPadding + NotchLayout.openTopRadius)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(setDateShortcut)
        .onReceive(NotificationCenter.default.publisher(for: .panelWillShow)) { _ in
            // Belt and braces next to the locale notification: a 12/24-hour switch while the app
            // ran shows up on the next open at the latest.
            SuggestionDateFormatter.invalidateCache()
            resetState()
        }
        .onReceive(NotificationCenter.default.publisher(for: .panelDidHide)) { _ in
            showListPicker = false
            showLocationField = false
            showSchedulePopover = false
        }
        .onReceive(NotificationCenter.default.publisher(for: .panelDismissPopovers)) { _ in
            showListPicker = false
            showLocationField = false
            // In-notch Set Date steps back one level per Esc: calendar → controls → closed.
            if schedulingInNotch {
                PanelController.shared.setSchedule(notch.schedule.afterEscape)
            } else {
                showSchedulePopover = false
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .panelCancelSchedule)) { _ in
            if schedulingInNotch { PanelController.shared.setSchedule(.none) }
        }
        .onChange(of: anyPopoverShown) { _, shown in
            PanelController.shared.popoverIsOpen = shown
        }
        .onChange(of: showSchedulePopover || schedulingInNotch) { _, isShown in
            // Hand the keyboard back to the panel's title row once Set Date closes.
            if !isShown { DispatchQueue.main.async { PanelController.shared.restoreKeyFocus() } }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: dueDate != nil)
        .animation(.easeOut(duration: 0.18), value: suggestion?.matchedText)
        .onChange(of: title) { _, newValue in updateSuggestion(for: newValue) }
        .onChange(of: dueDate) { _, newValue in if newValue == nil { updateSuggestion(for: title) } }
    }

    /// Date chip / suggestion / error slot and the bottom bar (always shown, also while the in-notch
    /// Set Date section is open below them).
    private var regularBottom: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Fixed-height slot for the date chip / suggestion / error, so the bottom bar never
            // jumps when one of them appears (iOS keeps this gap empty until a date is set).
            ZStack(alignment: .bottomLeading) {
                Color.clear
                if let saveErrorText {
                    Text(saveErrorText)
                        .font(.system(size: Theme.s(12), weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundStyle(Color(red: 1.0, green: 0.27, blue: 0.23))
                        .padding(.leading, Theme.s(21) + 10)
                        .transition(.opacity)
                } else if let date = dueDate {
                    dateChip(date)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                } else if let suggestion {
                    suggestionChip(suggestion)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .frame(height: Theme.s(26))
            .padding(.bottom, 8)

            BottomBar(
                dueDate: $dueDate,
                flagged: $flagged,
                locationText: $locationText,
                canSave: canSave,
                onSave: { saveReminder() },
                showLocationField: $showLocationField,
                showSchedulePopover: $showSchedulePopover,
                onOpenSetDate: openSetDate,
                onToggleSetDate: toggleSetDate,
                setDateOpen: schedulingInNotch,
                presetPick: $presetPick,
                suggestionText: suggestion?.matchedText,
                onConsumeSuggestion: stripSuggestionPhrase,
                saveNamespace: saveNamespace,
                saveButtonYielded: saveButtonYielded
            )
            .padding(.bottom, Theme.horizontalPadding)   // same inset below the ✓ as beside it
        }
    }

    // MARK: Natural-language date suggestion (Reminders-style, EN + CZ)

    private func updateSuggestion(for text: String) {
        guard dueDate == nil else { suggestion = nil; return }
        let minute = AppClock.now.timeIntervalSinceReferenceDate.rounded(.down) // second precision is enough
        let parsed = NaturalDateParser.parse(text, now: Date(timeIntervalSinceReferenceDate: minute))
        if let parsed, parsed.matchedText == dismissedSuggestionText {
            suggestion = nil
        } else {
            suggestion = parsed
            if parsed == nil { dismissedSuggestionText = nil }
        }
    }

    /// Applies the current suggestion: sets the due date and strips the phrase from the title.
    @discardableResult
    private func applySuggestionIfAny() -> Bool {
        guard let s = suggestion else { return false }
        // Day-only phrases share the popover's and presets' rule: 9:00, or the next :00/:30 slot
        // for "today" after 9:00.
        let date = s.hasTime ? s.date : ScheduleDefaults.resolveDayOnly(s.date, now: AppClock.now)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            dueDate = date
        }
        stripSuggestionPhrase()
        return true
    }

    /// Removes the suggestion's phrase from the title (unless that would empty it) and drops the
    /// suggestion. Shared by Tab and by the Set Date popover committing the prefilled phrase.
    private func stripSuggestionPhrase() {
        guard let s = suggestion else { return }
        let stripped = NaturalDateParser.removingMatch(from: title, suggestion: s)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { suggestion = nil }
        if !stripped.trimmingCharacters(in: .whitespaces).isEmpty {
            title = stripped
        }
    }

    /// ⌘D from the title or notes opens Set Date. An invisible button keeps the shortcut in
    /// SwiftUI's key-equivalent pass (the text view does not bind ⌘D); `.hidden()` would drop it.
    private var setDateShortcut: some View {
        Button("") { if !saveButtonYielded { openSetDate() } }
            .keyboardShortcut("d", modifiers: .command)
            .opacity(0)
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private func suggestionChip(_ s: DateSuggestion) -> some View {
        HStack(spacing: 8) {
            Button { applySuggestionIfAny() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: Theme.s(12), weight: .medium))
                    Text(Self.suggestionFormatter.string(from: s.date, hasTime: s.hasTime))
                        .font(.system(size: Theme.s(13), weight: .medium))
                    Text("⇥")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.45))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(RoundedRectangle(cornerRadius: 4).fill(.white.opacity(0.1)))
                }
                .foregroundStyle(accent)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(accent.opacity(0.14)))
                .contentShape(Capsule())
            }
            .buttonStyle(HoverButtonStyle())
            .accessibilityLabel("Use suggested date")

            Button {
                dismissedSuggestionText = s.matchedText
                withAnimation(.easeOut(duration: 0.15)) { suggestion = nil }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.4))
            }
            .buttonStyle(HoverButtonStyle())
            .accessibilityLabel("Dismiss suggestion")
        }
        .padding(.leading, Theme.s(21) + 10)
    }

    private static let suggestionFormatter = SuggestionDateFormatter()

    private func dateChip(_ date: Date) -> some View {
        HStack(spacing: 6) {
            // Clicking the date reopens Set Date on it.
            Button { openSetDate() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .font(.system(size: Theme.s(12), weight: .medium))
                    Text(Self.suggestionFormatter.string(from: date, hasTime: true))
                        .font(.system(size: Theme.s(13), weight: .medium))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(HoverButtonStyle())
            .accessibilityLabel("Change date")
            .accessibilityValue(Self.suggestionFormatter.string(from: date, hasTime: true))
            Button { dueDate = nil } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Clear date")
        }
        .foregroundStyle(accent)
        .padding(.leading, Theme.s(21) + 10)
    }

    /// ⌘D, Custom… and the date chip. In notch: the panel grows (the machine ignores it unless the
    /// panel is open, so nothing can get stuck half-shown); otherwise the popover.
    private func openSetDate() {
        switch pickerStyle {
        // Already open (e.g. on the calendar): ⌘D must not collapse it back to the controls.
        case .notch: if !schedulingInNotch { PanelController.shared.setSchedule(.controls) }
        case .popover: showSchedulePopover = true
        }
    }

    /// ↩ in the title or notes: Set while the in-notch section is open, otherwise save.
    private func submitFromTextRow() {
        switch ScheduleCommit.textRowSubmit(schedulingInNotch: schedulingInNotch, canSave: canSave) {
        case .setSchedule: NotificationCenter.default.post(name: .scheduleCommitRequested, object: nil)
        case .saveReminder: saveReminder()
        case .none: break
        }
    }

    /// The calendar button in notch style: opens Set Date, or closes it (Cancel) when it is open.
    private func toggleSetDate() {
        PanelController.shared.setSchedule(schedulingInNotch ? .none : .controls)
    }

    /// ✓ (and ⌘↩ when Set Date is closed). While the in-notch section is open, ✓ asks it first
    /// (`ScheduleDraft.prepareSave`): an edited draft is Set and then saved, an untouched one is
    /// dropped and the reminder saved as it is, an invalid one beeps and nothing is saved. The
    /// section calls back with `afterSetDate: true`.
    private func saveReminder(afterSetDate: Bool = false) {
        guard !saveButtonYielded else { return }   // already saved; the ✓ is flying
        guard afterSetDate || !schedulingInNotch else {
            NotificationCenter.default.post(name: .scheduleSaveRequested, object: nil)
            return
        }
        // Like iOS Reminders: an un-dismissed date phrase is applied automatically on save.
        if dueDate == nil, suggestion != nil { applySuggestionIfAny() }
        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
        guard !trimmedTitle.isEmpty else { return }
        do {
            try remindersService.save(
                title: trimmedTitle,
                notes: notes,
                calendarID: selectedListId.isEmpty ? nil : selectedListId,
                dueDate: dueDate,
                flagged: flagged,
                location: locationText.isEmpty ? nil : locationText
            )
            PanelController.shared.collapseAfterSave()
        } catch {
            withAnimation(.easeOut(duration: 0.2)) {
                saveErrorText = error.localizedDescription
            }
            NSSound.beep()
            if !remindersService.hasAccess {
                Task { await remindersService.requestAccess() }
            }
        }
    }

    private func resetState() {
        title = ""
        notes = ""
        dueDate = nil
        flagged = false
        locationText = ""
        saveErrorText = nil
        suggestion = nil
        dismissedSuggestionText = nil
        presetPick = nil
        showSchedulePopover = false
    }
}
