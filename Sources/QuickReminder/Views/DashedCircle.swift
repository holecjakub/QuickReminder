import SwiftUI

/// The empty "not completed" checkbox ring from iOS Reminders: a dotted circle.
struct DashedCircleView: View {
    var size: CGFloat = 21

    var body: some View {
        Circle()
            .stroke(
                Theme.dashedRing,
                style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [0.1, 3.2])
            )
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
