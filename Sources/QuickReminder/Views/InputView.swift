import SwiftUI

struct InputView: View {
    @Binding var title: String
    @Binding var notes: String
    @FocusState.Binding var titleFocused: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            DashedCircleView()
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 6) {
                TextField("New Reminder", text: $title)
                    .font(.system(size: 22, weight: .regular, design: .default))
                    .foregroundStyle(.white)
                    .focused($titleFocused)
                    .textFieldStyle(.plain)

                TextField("Notes", text: $notes)
                    .font(.system(size: 17, weight: .regular, design: .default))
                    .foregroundStyle(.white.opacity(0.7))
                    .textFieldStyle(.plain)
            }
        }
    }
}
