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

    @State private var title: String = ""
    @State private var notes: String = ""
    @State private var dueDate: Date? = nil
    @State private var flagged: Bool = false
    @State private var locationText: String = ""
    @State private var showListPicker: Bool = false
    @State private var showLocationField: Bool = false
    @State private var showCustomDatePicker: Bool = false
    @State private var saveErrorText: String? = nil
    @State private var suggestion: DateSuggestion? = nil
    @State private var dismissedSuggestionText: String? = nil


    @Environment(\.listAccent) private var accent

    private var canSave: Bool { !title.trimmingCharacters(in: .whitespaces).isEmpty }

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
                onSubmit: { if canSave { saveReminder() } },
                onTab: { applySuggestionIfAny() }
            )
            .padding(.top, 10)

            Spacer(minLength: 0)

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
                onSave: saveReminder,
                showLocationField: $showLocationField,
                showCustomDatePicker: $showCustomDatePicker,
                saveNamespace: saveNamespace,
                saveButtonYielded: saveButtonYielded
            )
            .padding(.bottom, 22)
        }
        .padding(.horizontal, Theme.horizontalPadding + NotchLayout.openTopRadius)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onReceive(NotificationCenter.default.publisher(for: .panelWillShow)) { _ in
            resetState()
        }
        .onReceive(NotificationCenter.default.publisher(for: .panelDidHide)) { _ in
            showListPicker = false
            showLocationField = false
            showCustomDatePicker = false
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: dueDate != nil)
        .animation(.easeOut(duration: 0.18), value: suggestion?.matchedText)
        .onChange(of: title) { _, newValue in updateSuggestion(for: newValue) }
        .onChange(of: dueDate) { _, newValue in if newValue == nil { updateSuggestion(for: title) } }
    }

    // MARK: Natural-language date suggestion (Reminders-style, EN + CZ)

    private func updateSuggestion(for text: String) {
        guard dueDate == nil else { suggestion = nil; return }
        let minute = Date().timeIntervalSinceReferenceDate.rounded(.down) // second precision is enough
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
        var date = s.date
        if !s.hasTime {
            let cal = Calendar.current
            date = cal.date(bySettingHour: 9, minute: 0, second: 0, of: date) ?? date
            // "today" after 9:00 → next full hour instead of an alarm already in the past.
            if cal.isDateInToday(date), date < Date() {
                date = cal.nextDate(after: Date(), matching: DateComponents(minute: 0, second: 0), matchingPolicy: .nextTime) ?? date
            }
        }
        let stripped = NaturalDateParser.removingMatch(from: title, suggestion: s)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            dueDate = date
            suggestion = nil
        }
        if !stripped.trimmingCharacters(in: .whitespaces).isEmpty {
            title = stripped
        }
        return true
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
            Image(systemName: "calendar")
                .font(.system(size: Theme.s(12), weight: .medium))
            Text(Self.suggestionFormatter.string(from: date, hasTime: true))
                .font(.system(size: Theme.s(13), weight: .medium))
            Button { dueDate = nil } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(accent)
        .padding(.leading, Theme.s(21) + 10)
    }

    private func saveReminder() {
        guard !saveButtonYielded else { return }   // already saved; the ✓ is flying
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
    }
}
