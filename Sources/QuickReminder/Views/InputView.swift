import SwiftUI

struct InputView: View {
    @Binding var title: String
    @Binding var notes: String
    @FocusState.Binding var titleFocused: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            DashedCircleView()
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 4) {
                TextField("New Reminder", text: $title)
                    .font(.system(size: 20, weight: .regular, design: .default))
                    .foregroundStyle(.white)
                    .tint(Color.accentColor)
                    .focused($titleFocused)
                    .textFieldStyle(.plain)
                    .frame(maxWidth: .infinity, alignment: .leading)

                TextField("Notes", text: $notes)
                    .font(.system(size: 15, weight: .regular, design: .default))
                    .foregroundStyle(.white.opacity(0.55))
                    .tint(Color.accentColor)
                    .textFieldStyle(.plain)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
