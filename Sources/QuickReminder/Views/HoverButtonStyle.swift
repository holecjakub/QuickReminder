import SwiftUI

/// Pointer feedback for the iOS-style controls: pointing-hand cursor, gentle scale-up on hover,
/// scale-down while pressed. Respects Reduce Motion (no scaling, cursor only).
///
/// The hover region is the control's *layout* frame, not the scaled artwork: `contentShape` is
/// applied after `scaleEffect`, so growing on hover cannot push the pointer outside the hit
/// area and flip the state back (that feedback loop is what made the icons stutter).
struct HoverButtonStyle: ButtonStyle {
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(scale(pressed: configuration.isPressed))
            .animation(HoverMotion.animation(reduceMotion: reduceMotion), value: hovering)
            .animation(HoverMotion.pressAnimation(reduceMotion: reduceMotion), value: configuration.isPressed)
            .contentShape(Rectangle())
            .onHover { isHovering in
                guard isHovering != hovering else { return }
                hovering = isHovering
                HoverMotion.updateCursor(hovering: isHovering)
            }
    }

    private func scale(pressed: Bool) -> CGFloat {
        if reduceMotion { return 1 }
        if pressed { return HoverMotion.pressedScale }
        return hovering ? HoverMotion.hoverScale : 1
    }
}

/// Same hover feedback for controls that are not `Button`s (e.g. a `Menu`).
struct HoverScale: ViewModifier {
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .scaleEffect(hovering && !reduceMotion ? HoverMotion.hoverScale : 1)
            .animation(HoverMotion.animation(reduceMotion: reduceMotion), value: hovering)
            .contentShape(Rectangle())
            .onHover { isHovering in
                guard isHovering != hovering else { return }
                hovering = isHovering
                HoverMotion.updateCursor(hovering: isHovering)
            }
    }
}

enum HoverMotion {
    static let hoverScale: CGFloat = 1.06
    static let pressedScale: CGFloat = 0.94

    /// One spring for the whole hover interaction (SwiftUI interpolates retargets smoothly,
    /// unlike two competing ease curves).
    static func animation(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .spring(duration: 0.22, bounce: 0.12)
    }

    static func pressAnimation(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .spring(duration: 0.14, bounce: 0)
    }

    @MainActor static func updateCursor(hovering: Bool) {
        (hovering ? NSCursor.pointingHand : NSCursor.arrow).set()
    }
}

extension View {
    func hoverScale() -> some View { modifier(HoverScale()) }
}
