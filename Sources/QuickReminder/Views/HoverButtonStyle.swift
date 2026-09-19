import SwiftUI

/// Pointer feedback for the iOS-style controls: pointing-hand cursor, gentle scale-up on hover,
/// scale-down while pressed. Respects Reduce Motion (no scaling, cursor only).
struct HoverButtonStyle: ButtonStyle {
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(scale(pressed: configuration.isPressed))
            .animation(.easeOut(duration: 0.12), value: hovering)
            .animation(.easeOut(duration: 0.10), value: configuration.isPressed)
            .onHover { isHovering in
                hovering = isHovering
                (isHovering ? NSCursor.pointingHand : NSCursor.arrow).set()
            }
    }

    private func scale(pressed: Bool) -> CGFloat {
        if reduceMotion { return 1 }
        if pressed { return 0.94 }
        return hovering ? 1.06 : 1
    }
}

/// Same hover feedback for controls that are not `Button`s (e.g. a `Menu` label).
struct HoverScale: ViewModifier {
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .scaleEffect(hovering && !reduceMotion ? 1.06 : 1)
            .animation(.easeOut(duration: 0.12), value: hovering)
            .onHover { isHovering in
                hovering = isHovering
                (isHovering ? NSCursor.pointingHand : NSCursor.arrow).set()
            }
    }
}

extension View {
    func hoverScale() -> some View { modifier(HoverScale()) }
}
