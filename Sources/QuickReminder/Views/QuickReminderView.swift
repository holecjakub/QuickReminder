import SwiftUI

/// Root of the quick-reminder UI, laid out 1:1 with the iOS 26 overlay
/// (header → input → bottom bar), sitting below the notch band.
@MainActor
struct QuickReminderView: View {
    @EnvironmentObject private var state: NotchState
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

    @FocusState private var titleFocused: Bool

    private var canSave: Bool { !title.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The physical notch / menu-bar band. Content starts below it.
            Color.clear.frame(height: state.notchBandHeight)

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
                titleFocused: $titleFocused,
                onSubmit: { if canSave { saveReminder() } },
                onTab: { applySuggestionIfAny() }
            )
            .padding(.top, 10)

            Spacer(minLength: 14)

            if let saveErrorText {
                Text(saveErrorText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(red: 1.0, green: 0.27, blue: 0.23))
                    .padding(.leading, 31)
                    .padding(.bottom, 8)
                    .transition(.opacity)
            }

            if let date = dueDate {
                dateChip(date)
                    .padding(.bottom, 8)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            } else if let suggestion {
                suggestionChip(suggestion)
                    .padding(.bottom, 8)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            BottomBar(
                dueDate: $dueDate,
                flagged: $flagged,
                locationText: $locationText,
                canSave: canSave,
                onSave: saveReminder,
                showLocationField: $showLocationField,
                showCustomDatePicker: $showCustomDatePicker
            )
            .padding(.bottom, 22)
        }
        .padding(.horizontal, Theme.horizontalPadding + NotchLayout.openTopRadius)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onReceive(NotificationCenter.default.publisher(for: .panelWillShow)) { _ in
            resetState()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { titleFocused = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: .panelDidHide)) { _ in
            titleFocused = false
            showListPicker = false
            showLocationField = false
            showCustomDatePicker = false
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: dueDate != nil)
        .animation(.easeOut(duration: 0.18), value: suggestion?.matchedText)
        .onChange(of: title) { _, newValue in updateSuggestion(for: newValue) }
    }

    // MARK: Natural-language date suggestion (Reminders-style, EN + CZ)

    private func updateSuggestion(for text: String) {
        guard dueDate == nil else { suggestion = nil; return }
        let parsed = NaturalDateParser.parse(text)
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
            date = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: date) ?? date
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
                        .font(.system(size: 12, weight: .medium))
                    Text(Self.suggestionFormatter.string(from: s.date, hasTime: s.hasTime))
                        .font(.system(size: 13, weight: .medium))
                    Text("⇥")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.45))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(RoundedRectangle(cornerRadius: 4).fill(.white.opacity(0.1)))
                }
                .foregroundStyle(Theme.accent)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(Theme.accent.opacity(0.14)))
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
        .padding(.leading, 31)
    }

    private static let suggestionFormatter = SuggestionDateFormatter()

    private func dateChip(_ date: Date) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "calendar")
                .font(.system(size: 12, weight: .medium))
            Text(Self.suggestionFormatter.string(from: date, hasTime: true))
                .font(.system(size: 13, weight: .medium))
            Button { dueDate = nil } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(Theme.accent)
        .padding(.leading, 31)
    }

    private func saveReminder() {
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
            PanelController.shared.hide()
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
