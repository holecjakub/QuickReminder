import SwiftUI

/// Bottom row: outlined pill with date / location / flag on the left, round ✓ save button on the right.
struct BottomBar: View {
    @Binding var dueDate: Date?
    @Binding var flagged: Bool
    @Binding var locationText: String
    let canSave: Bool
    let onSave: () -> Void

    @Binding var showLocationField: Bool
    @Binding var showCustomDatePicker: Bool
    @State private var saveScale: CGFloat = 1.0

    private let iconSize: CGFloat = 22
    private let hitSize: CGFloat = 38

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            pillView
            Spacer(minLength: 16)
            saveButton
        }
    }

    // MARK: Pill

    private var pillView: some View {
        HStack(spacing: 17) {
            dateMenu
            locationButton
            flagButton
        }
        .padding(.horizontal, 11)
        .frame(height: 44)
        .background(
            Capsule()
                .fill(Theme.pillFill)
                .overlay(Capsule().strokeBorder(Theme.pillStroke, lineWidth: 1))
        )
    }

    private func icon(_ name: String, active: Bool, activeColor: Color = Theme.accent, size: CGFloat? = nil) -> some View {
        Image(systemName: name)
            .font(.system(size: size ?? iconSize, weight: .regular))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(active ? activeColor : .white)
            .frame(width: hitSize, height: hitSize)
            .contentShape(Rectangle())
    }

    private var dateMenu: some View {
        Menu {
            Button { dueDate = nil } label: {
                Label("None", systemImage: "calendar.badge.minus")
            }
            Divider()
            Button {
                flagged = true
                dueDate = Date().addingTimeInterval(60 * 60)
            } label: {
                Label("Mark as Urgent", systemImage: "alarm")
            }
            Button { dueDate = Date().addingTimeInterval(60 * 60) } label: {
                Label("Remind Me In 1 Hour", systemImage: "clock")
            }
            Button { dueDate = tomorrowAt9AM() } label: {
                Label("Remind Me Tomorrow", systemImage: "calendar")
            }
            Divider()
            Button { showCustomDatePicker = true } label: {
                Label("Remind Me Later…", systemImage: "calendar")
            }
        } label: {
            icon("calendar.badge.clock", active: dueDate != nil, size: iconSize + 2)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .hoverScale()
        .accessibilityLabel("Add date")
        .popover(isPresented: $showCustomDatePicker, arrowEdge: .bottom) {
            DatePickerPopover(selectedDate: $dueDate, isPresented: $showCustomDatePicker)
        }
    }

    private var locationButton: some View {
        Button { showLocationField = true } label: {
            icon(locationText.isEmpty ? "location" : "location.fill", active: !locationText.isEmpty)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(HoverButtonStyle())
        .accessibilityLabel("Add location")
        .popover(isPresented: $showLocationField, arrowEdge: .bottom) {
            locationPopover
        }
    }

    private var flagButton: some View {
        Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) { flagged.toggle() }
        } label: {
            icon(flagged ? "flag.fill" : "flag", active: flagged, activeColor: Theme.flagOrange)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(HoverButtonStyle())
        .accessibilityLabel("Toggle flag")
    }

    // MARK: Save

    private var saveButton: some View {
        Button(action: handleSave) {
            ZStack {
                Circle()
                    .fill(canSave ? Theme.accent : Theme.grayCircleDisabled)
                Image(systemName: "checkmark")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 48, height: 48)
            .contentShape(Circle())
        }
        .buttonStyle(HoverButtonStyle())
        .scaleEffect(saveScale)
        .disabled(!canSave)
        .animation(.easeInOut(duration: 0.18), value: canSave)
        .accessibilityLabel("Save reminder")
        .keyboardShortcut(.return, modifiers: .command)
    }

    private var locationPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Location").font(.headline)
            TextField("Enter location", text: $locationText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 220)
                .onSubmit { showLocationField = false }
            HStack {
                Spacer()
                Button("Done") { showLocationField = false }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(14)
    }

    private func handleSave() {
        guard canSave else { return }
        withAnimation(.spring(response: 0.22, dampingFraction: 0.55)) { saveScale = 1.08 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) { saveScale = 1.0 }
        }
        onSave()
    }

    private func tomorrowAt9AM() -> Date {
        let cal = Calendar.current
        let tomorrow = cal.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        return cal.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) ?? tomorrow
    }
}
