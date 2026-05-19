import SwiftUI
import EventKit

struct ListPickerMenu: View {
    let calendars: [EKCalendar]
    @Binding var selectedListId: String
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Lists")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 6)

            ForEach(calendars, id: \.calendarIdentifier) { cal in
                Button {
                    selectedListId = cal.calendarIdentifier
                    isPresented = false
                } label: {
                    HStack {
                        Circle()
                            .fill(Color(cgColor: cal.cgColor))
                            .frame(width: 10, height: 10)
                        Text(cal.title)
                            .font(.system(size: 15))
                            .foregroundStyle(.primary)
                        Spacer()
                        if cal.calendarIdentifier == selectedListId {
                            Image(systemName: "checkmark")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.bottom, 8)
        .frame(minWidth: 200)
    }
}
