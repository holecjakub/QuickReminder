import SwiftUI

/// Dotted checkbox + "New Reminder" title + "Notes" line, exactly like the iOS overlay.
struct InputView: View {
    @Binding var title: String
    @Binding var notes: String
    @FocusState.Binding var titleFocused: Bool
    let onSubmit: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            DashedCircleView()
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 1) {
                PlaceholderTextField(
                    placeholder: "New Reminder",
                    text: $title,
                    font: .system(size: 19, weight: .regular),
                    placeholderColor: Theme.placeholder,
                    onSubmit: onSubmit
                )
                .focused($titleFocused)

                PlaceholderTextField(
                    placeholder: "Notes",
                    text: $notes,
                    font: .system(size: 15, weight: .regular),
                    placeholderColor: Theme.placeholderSecondary,
                    onSubmit: onSubmit
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Plain text field with a custom-coloured placeholder (SwiftUI's default placeholder tint is not controllable).
struct PlaceholderTextField: View {
    let placeholder: String
    @Binding var text: String
    let font: Font
    let placeholderColor: Color
    let onSubmit: () -> Void

    var body: some View {
        ZStack(alignment: .leading) {
            if text.isEmpty {
                Text(placeholder)
                    .font(font)
                    .foregroundStyle(placeholderColor)
                    .allowsHitTesting(false)
            }
            TextField("", text: $text)
                .font(font)
                .foregroundStyle(.white)
                .tint(Theme.accent)
                .textFieldStyle(.plain)
                .onSubmit(onSubmit)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
