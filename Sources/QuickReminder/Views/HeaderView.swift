import SwiftUI
import EventKit

struct HeaderView: View {
    @ObservedObject var remindersService: RemindersService
    @Binding var selectedListId: String
    @Binding var showListPicker: Bool
    let onClose: () -> Void

    private var selectedListName: String {
        if selectedListId.isEmpty {
            return "Reminders"
        }
        return remindersService.calendars
            .first { $0.calendarIdentifier == selectedListId }?.title ?? "Reminders"
    }

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            Button {
                showListPicker = true
            } label: {
                HStack(alignment: .center, spacing: 8) {
                    Text(selectedListName)
                        .font(.system(size: 28, weight: .bold, design: .default))
                        .foregroundStyle(Color.accentColor)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showListPicker, arrowEdge: .bottom) {
                ListPickerMenu(
                    calendars: remindersService.calendars,
                    selectedListId: $selectedListId,
                    isPresented: $showListPicker
                )
            }

            Spacer()

            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 28))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .frame(width: 36, height: 36)
        }
    }
}
