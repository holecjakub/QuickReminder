import SwiftUI

/// macOS-style pointer feedback (HIG "Feedback": controls highlight on hover, they do not
/// grow): a soft circular highlight fades in behind the control on hover and deepens while
/// pressed, plus the pointing-hand cursor. No geometry changes, so nothing around the control
/// moves. Respects Reduce Motion by switching the fade to an instant change.
struct HoverButtonStyle: ButtonStyle {
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                Circle()
                    .fill(Color.white.opacity(highlightOpacity(pressed: configuration.isPressed)))
                    .animation(reduceMotion ? nil : HoverMotion.highlightAnimation, value: hovering)
                    .animation(reduceMotion ? nil : HoverMotion.pressAnimation, value: configuration.isPressed)
            )
            .contentShape(Rectangle())
            .onHover { isHovering in
                guard isHovering != hovering else { return }
                hovering = isHovering
                HoverMotion.updateCursor(hovering: isHovering)
            }
    }

    private func highlightOpacity(pressed: Bool) -> Double {
        if pressed { return HoverMotion.pressedHighlight }
        return hovering ? HoverMotion.hoverHighlight : 0
    }
}

enum HoverMotion {
    /// Control Center / toolbar-like highlight strengths on a black surface.
    static let hoverHighlight: Double = 0.10
    static let pressedHighlight: Double = 0.18
    static let highlightAnimation: Animation = .easeOut(duration: 0.12)
    static let pressAnimation: Animation = .easeOut(duration: 0.06)

    @MainActor static func updateCursor(hovering: Bool) {
        (hovering ? NSCursor.pointingHand : NSCursor.arrow).set()
    }
}
