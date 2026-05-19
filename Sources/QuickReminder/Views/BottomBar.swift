import SwiftUI

struct BottomBar: View {
    @Binding var dueDate: Date?
    @Binding var flagged: Bool
    @Binding var locationText: String
    let canSave: Bool
    let onSave: () -> Void

    @State private var showLocationField = false
    @State private var showCustomDatePicker = false
    @State private var saveScale: CGFloat = 1.0

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            pillView
            Spacer()
            saveButton
        }
    }

    private var pillView: some View {
        HStack(spacing: 20) {
            dateMenu
            locationButton
            flagButton
        }
        .padding(.horizontal, 14)
        .frame(height: 40)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.08))
                .overlay(
                    Capsule()
                        .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                )
        )
    }

    private var dateMenu: some View {
        Menu {
            Button {
                dueDate = nil
            } label: {
                Label("None", systemImage: "calendar.badge.minus")
            }

            Divider()

            Button {
                flagged = true
                dueDate = Date().addingTimeInterval(60 * 60)
            } label: {
                Label("Mark as Urgent", systemImage: "alarm")
            }

            Button {
                dueDate = Date().addingTimeInterval(60 * 60)
            } label: {
                Label("Remind Me In 1 Hour", systemImage: "clock")
            }

            Button {
                dueDate = tomorrowAt9AM()
            } label: {
                Label("Remind Me Tomorrow", systemImage: "calendar")
            }

            Divider()

            Button {
                showCustomDatePicker = true
            } label: {
                Label("Remind Me Later…", systemImage: "calendar")
            }
        } label: {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(dueDate != nil ? Color.accentColor : .white)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .popover(isPresented: $showCustomDatePicker, arrowEdge: .top) {
            DatePickerPopover(selectedDate: $dueDate, isPresented: $showCustomDatePicker)
        }
    }

    private var locationButton: some View {
        Button {
            showLocationField = true
        } label: {
            Image(systemName: "paperplane.fill")
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(!locationText.isEmpty ? Color.accentColor : .white)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showLocationField, arrowEdge: .top) {
            locationPopover
        }
    }

    private var flagButton: some View {
        Button {
            flagged.toggle()
        } label: {
            Image(systemName: flagged ? "flag.fill" : "flag")
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(flagged ? .orange : .white)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
    }

    private var locationPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Location")
                .font(.headline)
            TextField("Enter location", text: $locationText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 200)
            HStack {
                Spacer()
                Button("Done") { showLocationField = false }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(14)
    }

    private var saveButton: some View {
        Button(action: handleSave) {
            ZStack {
                Circle()
                    .fill(canSave ? Color.accentColor : Color.white.opacity(0.12))
                    .frame(width: 44, height: 44)
                Image(systemName: "checkmark")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(saveScale)
        .disabled(!canSave)
        .animation(.easeInOut(duration: 0.15), value: canSave)
    }

    private func handleSave() {
        withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) {
            saveScale = 1.15
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) {
                saveScale = 1.0
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            onSave()
        }
    }

    private func tomorrowAt9AM() -> Date {
        let cal = Calendar.current
        let tomorrow = cal.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        return cal.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) ?? tomorrow
    }
}
