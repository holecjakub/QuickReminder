import SwiftUI

/// Stopgap: the graphical picker with `[.date, .hourAndMinute]` drew an analog clock whose hands
/// had to be dragged. Day and time are now two controls on the same value: a month calendar
/// (date only, so no clock can render) and a typed hour/minute field.
struct DatePickerPopover: View {
    @Binding var selectedDate: Date?
    @Binding var isPresented: Bool
    let accent: Color

    @State private var pickerDate = Date()

    var body: some View {
        VStack(spacing: 16) {
            DatePicker("", selection: $pickerDate, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()

            DatePicker("Time", selection: $pickerDate, displayedComponents: .hourAndMinute)
                .datePickerStyle(.field)

            HStack {
                Button("Clear") {
                    selectedDate = nil
                    isPresented = false
                }
                .foregroundStyle(.secondary)

                Spacer()

                Button("Cancel") { isPresented = false }
                    .keyboardShortcut(.cancelAction)

                Button("Set") {
                    selectedDate = pickerDate
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 4)
        }
        .padding(16)
        .frame(width: 300)
        .preferredColorScheme(.dark)
        .tint(accent)
        .onAppear {
            pickerDate = selectedDate ?? ScheduleDefaults.nextSlot(after: AppClock.now)
        }
    }
}
