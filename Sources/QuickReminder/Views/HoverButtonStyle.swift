import SwiftUI

/// Pointer feedback for the round controls (ⓧ, ✓, header, chips): pointing-hand cursor, gentle
/// scale-up on hover, scale-down while pressed. The hover region is the control's *layout*
/// frame (`contentShape` after `scaleEffect`), so growing on hover cannot push the pointer out
/// of the hit area and flip the state back. Respects Reduce Motion (cursor only).
struct HoverButtonStyle: ButtonStyle {
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(scale(pressed: configuration.isPressed))
            .animation(reduceMotion ? nil : HoverMotion.scaleAnimation, value: hovering)
            .animation(reduceMotion ? nil : HoverMotion.pressAnimation, value: configuration.isPressed)
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

/// Pointer feedback for the pill icons (calendar, location, flag), following the macOS HIG:
/// a soft circular highlight fades in behind the icon and deepens while pressed; no geometry
/// changes, so the row never shifts.
struct HoverHighlightButtonStyle: ButtonStyle {
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
    static let hoverScale: CGFloat = 1.06
    static let pressedScale: CGFloat = 0.94
    static let scaleAnimation: Animation = .spring(duration: 0.22, bounce: 0.12)
    static let hoverHighlight: Double = 0.10
    static let pressedHighlight: Double = 0.18
    static let highlightAnimation: Animation = .easeOut(duration: 0.12)
    static let pressAnimation: Animation = .spring(duration: 0.14, bounce: 0)

    @MainActor static func updateCursor(hovering: Bool) {
        (hovering ? NSCursor.pointingHand : NSCursor.arrow).set()
    }
}
