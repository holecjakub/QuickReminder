import SwiftUI

@MainActor
struct QuickReminderView: View {
    @ObservedObject private var remindersService = RemindersService.shared
    @AppStorage("selectedListId") private var selectedListId: String = ""

    @State private var title: String = ""
    @State private var notes: String = ""
    @State private var dueDate: Date? = nil
    @State private var flagged: Bool = false
    @State private var locationText: String = ""
    @State private var showListPicker: Bool = false
    @State private var showSaveError: Bool = false
    @State private var isVisible: Bool = false

    @FocusState private var titleFocused: Bool

    private var canSave: Bool { !title.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        ZStack {
            Color.clear

            VStack(alignment: .leading, spacing: 0) {
                HeaderView(
                    remindersService: remindersService,
                    selectedListId: $selectedListId,
                    showListPicker: $showListPicker,
                    onClose: { PanelController.shared.hide() }
                )

                Spacer().frame(height: 14)

                InputView(
                    title: $title,
                    notes: $notes,
                    titleFocused: $titleFocused
                )

                Spacer()

                if let date = dueDate {
                    HStack {
                        Image(systemName: "calendar")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.accentColor)
                        Text(date.formatted(date: .abbreviated, time: .shortened))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.accentColor)
                        Button {
                            dueDate = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.bottom, 8)
                }

                BottomBar(
                    dueDate: $dueDate,
                    flagged: $flagged,
                    locationText: $locationText,
                    canSave: canSave,
                    onSave: saveReminder
                )
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
        }
        .scaleEffect(isVisible ? 1.0 : 0.96)
        .opacity(isVisible ? 1.0 : 0.0)
        .onAppear { animateIn() }
        .onReceive(NotificationCenter.default.publisher(for: .panelWillShow)) { _ in
            isVisible = false
            resetState()
            animateIn()
        }
        .onReceive(NotificationCenter.default.publisher(for: .panelDidHide)) { _ in
            withAnimation(.easeOut(duration: 0.12)) {
                isVisible = false
            }
        }
        .background(
            Button("", action: { if canSave { saveReminder() } })
                .keyboardShortcut(.return, modifiers: .command)
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        )
    }

    private func animateIn() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
            isVisible = true
        }
        titleFocused = true
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
            showSaveError = true
        }
    }

    private func resetState() {
        title = ""
        notes = ""
        dueDate = nil
        flagged = false
        locationText = ""
        showSaveError = false
    }
}

