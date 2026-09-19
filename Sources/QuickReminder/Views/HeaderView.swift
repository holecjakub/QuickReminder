import SwiftUI
import EventKit

/// "Reminders ▾" list picker on the left, gray ⓧ close button on the right.
struct HeaderView: View {
    @ObservedObject var remindersService: RemindersService
    @Binding var selectedListId: String
    @Binding var showListPicker: Bool
    let onClose: () -> Void

    private var selectedListName: String {
        if selectedListId.isEmpty { return "Reminders" }
        return remindersService.calendars
            .first { $0.calendarIdentifier == selectedListId }?.title ?? "Reminders"
    }

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            Button {
                showListPicker.toggle()
            } label: {
                HStack(alignment: .center, spacing: 7) {
                    Text(selectedListName)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Theme.accent)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.accent)
                        .offset(y: 0.5)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(HoverButtonStyle())
            .popover(isPresented: $showListPicker, arrowEdge: .bottom) {
                ListPickerMenu(
                    calendars: remindersService.calendars,
                    selectedListId: $selectedListId,
                    isPresented: $showListPicker
                )
            }
            .accessibilityLabel("Choose list")

            Spacer(minLength: 12)

            Button(action: onClose) {
                ZStack {
                    Circle().fill(Theme.grayCircle)
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 24, height: 24)
                .frame(width: 36, height: 36)
                .contentShape(Circle())
            }
            .buttonStyle(HoverButtonStyle())
            .accessibilityLabel("Close")
        }
    }
}
