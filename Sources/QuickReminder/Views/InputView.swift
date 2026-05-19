import SwiftUI

struct InputView: View {
    @Binding var title: String
    @Binding var notes: String
    @FocusState.Binding var titleFocused: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            DashedCircleView()
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 4) {
                TextField("New Reminder", text: $title)
                    .font(.system(size: 17, weight: .regular, design: .default))
                    .foregroundStyle(.white)
                    .focused($titleFocused)
                    .textFieldStyle(.plain)

                TextField("Notes", text: $notes)
                    .font(.system(size: 13, weight: .regular, design: .default))
                    .foregroundStyle(.white.opacity(0.7))
                    .textFieldStyle(.plain)
            }
        }
    }
}
