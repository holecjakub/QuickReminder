import SwiftUI

struct BottomBar: View {
    @Binding var dueDate: Date?
    @Binding var flagged: Bool
    @Binding var locationText: String
    let canSave: Bool
    let onSave: () -> Void

    @State private var showDatePicker = false
    @State private var showLocationField = false
    @State private var saveScale: CGFloat = 1.0

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            pillView
            Spacer()
            saveButton
        }
    }

    private var pillView: some View {
        HStack(spacing: 28) {
            pillButton(icon: "calendar.badge.clock", tinted: dueDate != nil) {
                showDatePicker = true
            }
            .popover(isPresented: $showDatePicker, arrowEdge: .top) {
                DatePickerPopover(selectedDate: $dueDate, isPresented: $showDatePicker)
            }

            pillButton(icon: "paperplane.fill", tinted: !locationText.isEmpty) {
                showLocationField = true
            }
            .popover(isPresented: $showLocationField, arrowEdge: .top) {
                locationPopover
            }

            pillButton(
                icon: flagged ? "flag.fill" : "flag",
                tinted: flagged,
                tintColor: flagged ? .orange : .white
            ) {
                flagged.toggle()
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 52)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.08))
                .overlay(
                    Capsule()
                        .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                )
        )
    }

    private var locationPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Location")
                .font(.headline)
            TextField("Enter location", text: $locationText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 220)
            HStack {
                Spacer()
                Button("Done") { showLocationField = false }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
    }

    private var saveButton: some View {
        Button(action: handleSave) {
            ZStack {
                Circle()
                    .fill(canSave ? Color.accentColor : Color.white.opacity(0.12))
                    .frame(width: 56, height: 56)
                Image(systemName: "checkmark")
                    .font(.system(size: 22, weight: .semibold))
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

    @ViewBuilder
    private func pillButton(
        icon: String,
        tinted: Bool,
        tintColor: Color = .accentColor,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(tinted ? tintColor : .white)
                .frame(width: 36, height: 36)
        }
        .buttonStyle(.plain)
    }
}
