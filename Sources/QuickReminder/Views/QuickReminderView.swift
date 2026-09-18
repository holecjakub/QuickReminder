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
                onSubmit: { if canSave { saveReminder() } }
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
    }

    private func dateChip(_ date: Date) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "calendar")
                .font(.system(size: 12, weight: .medium))
            Text(date.formatted(date: .abbreviated, time: .shortened))
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
    }
}
