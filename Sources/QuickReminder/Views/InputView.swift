import SwiftUI

/// Dotted checkbox + "New Reminder" title + "Notes" line, exactly like the iOS overlay.
struct InputView: View {
    @Binding var title: String
    @Binding var notes: String
    @FocusState.Binding var titleFocused: Bool
    let onSubmit: () -> Void
    /// Return true to consume Tab (used to accept a date suggestion).
    var onTab: () -> Bool = { false }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            DashedCircleView(size: Theme.s(21))
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 1) {
                PlaceholderTextField(
                    placeholder: "New Reminder",
                    text: $title,
                    font: .system(size: Theme.s(19), weight: .regular),
                    pointSize: Theme.s(19),
                    placeholderColor: Theme.placeholder,
                    onSubmit: onSubmit
                )
                .focused($titleFocused)
                .onKeyPress(.tab) { onTab() ? .handled : .ignored }

                PlaceholderTextField(
                    placeholder: "Notes",
                    text: $notes,
                    font: .system(size: Theme.s(15), weight: .regular),
                    pointSize: Theme.s(15),
                    placeholderColor: Theme.placeholderSecondary,
                    onSubmit: onSubmit
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Plain text field with a custom-coloured placeholder (SwiftUI's default placeholder tint is not controllable).
/// Known macOS SwiftUI behaviour: a `TextField`'s height changes between "empty" and "has
/// text" (and when a placeholder view leaves the hierarchy), which nudged everything below
/// the Notes line by a point. The row therefore has a fixed height derived from the font,
/// and the placeholder stays in the layout (only its opacity changes).
struct PlaceholderTextField: View {
    let placeholder: String
    @Binding var text: String
    let font: Font
    let pointSize: CGFloat
    let placeholderColor: Color
    let onSubmit: () -> Void
    @Environment(\.listAccent) private var accent

    var body: some View {
        ZStack(alignment: .leading) {
            Text(placeholder)
                .font(font)
                .foregroundStyle(placeholderColor)
                .opacity(text.isEmpty ? 1 : 0)
                .allowsHitTesting(false)
            TextField("", text: $text)
                .font(font)
                .foregroundStyle(.white)
                .tint(accent)
                .textFieldStyle(.plain)
                .onSubmit(onSubmit)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: Self.lineHeight(for: pointSize))
        .clipped()
    }

    /// Line height of the system font at `pointSize` (ascender + |descender| + leading), rounded up.
    static func lineHeight(for pointSize: CGFloat) -> CGFloat {
        let f = NSFont.systemFont(ofSize: pointSize)
        return (f.ascender - f.descender + f.leading).rounded(.up)
    }
}
