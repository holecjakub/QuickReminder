import SwiftUI
import EventKit

/// "Reminders ▾" list picker on the left, gray ⓧ close button on the right.
struct HeaderView: View {
    @ObservedObject var remindersService: RemindersService
    @Binding var selectedListId: String
    @Binding var showListPicker: Bool
    let onClose: () -> Void
    @Environment(\.listAccent) private var accent

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
                        .font(.system(size: Theme.s(22), weight: .bold))
                        .foregroundStyle(accent)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: Theme.s(13), weight: .bold))
                        .foregroundStyle(accent)
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
                        .font(.system(size: Theme.s(11), weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: Theme.s(24), height: Theme.s(24))
                .frame(width: Theme.s(36), height: Theme.s(36))
                .contentShape(Circle())
            }
            .buttonStyle(HoverButtonStyle())
            .accessibilityLabel("Close")
        }
    }
}
