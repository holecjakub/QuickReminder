import SwiftUI

struct DatePickerPopover: View {
    @Binding var selectedDate: Date?
    @Binding var isPresented: Bool

    @State private var pickerDate = Date()

    var body: some View {
        VStack(spacing: 16) {
            DatePicker(
                "Date & Time",
                selection: $pickerDate,
                displayedComponents: [.date, .hourAndMinute]
            )
            .datePickerStyle(.graphical)
            .labelsHidden()

            HStack {
                Button("Clear") {
                    selectedDate = nil
                    isPresented = false
                }
                .foregroundStyle(.secondary)

                Spacer()

                Button("Done") {
                    selectedDate = pickerDate
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 4)
        }
        .padding(16)
        .frame(width: 300)
        .onAppear {
            pickerDate = selectedDate ?? Date()
        }
    }
}
