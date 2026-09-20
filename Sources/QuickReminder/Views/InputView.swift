import SwiftUI

/// Dotted checkbox + "New Reminder" title + "Notes" line, exactly like the iOS overlay.
struct InputView: View {
    @Binding var title: String
    @Binding var notes: String
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
                    pointSize: Theme.s(19),
                    placeholderColor: Theme.placeholder,
                    identifier: "title",
                    onSubmit: onSubmit,
                    onTab: onTab
                )

                PlaceholderTextField(
                    placeholder: "Notes",
                    text: $notes,
                    pointSize: Theme.s(15),
                    placeholderColor: Theme.placeholderSecondary,
                    identifier: "notes",
                    onSubmit: onSubmit,
                    maxLength: 10_000
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// One text row: a fixed-height `PlainTextView` with a SwiftUI placeholder drawn over it while
/// empty (opacity only, so the row never changes size).
struct PlaceholderTextField: View {
    let placeholder: String
    @Binding var text: String
    let pointSize: CGFloat
    let placeholderColor: Color
    let identifier: String
    let onSubmit: () -> Void
    var onTab: () -> Bool = { false }
    var maxLength: Int = 2_000
    @Environment(\.listAccent) private var accent

    var body: some View {
        ZStack(alignment: .leading) {
            PlainTextView(
                text: $text,
                pointSize: pointSize,
                accent: accent,
                identifier: identifier,
                placeholder: placeholder,
                onSubmit: onSubmit,
                onTab: onTab,
                maxLength: maxLength
            )
            Text(placeholder)
                .font(.system(size: pointSize, weight: .regular))
                .foregroundStyle(placeholderColor)
                .opacity(text.isEmpty ? 1 : 0)
                .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: PlainTextView.lineHeight(for: pointSize) + 2)
    }
}
