import SwiftUI

// Chrome for controls on the pure black panel (in-notch Set Date): white alpha instead of glass,
// the list accent for selection and the primary action.

/// Neutral: white 6 % / 11 % hover / 15 % pressed. Selected: accent 20 % + accent stroke.
/// Prominent: the accent itself (the label picks its colour with `AccentContrast.label(on:)`).
/// Press: 0.97 scale (none with Reduce Motion).
struct NotchFillButtonStyle: ButtonStyle {
    enum Kind { case neutral, selected, prominent }
    let kind: Kind
    let accent: Color
    /// nil = capsule (a corner radius larger than half the height draws one).
    let radius: CGFloat?

    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        let shape = RoundedRectangle(cornerRadius: radius ?? 999, style: .continuous)
        return configuration.label
            .background(shape.fill(fill(pressed: pressed)))
            .overlay(shape.strokeBorder(kind == .selected ? accent.opacity(0.8) : .clear, lineWidth: 1))
            .opacity(isEnabled ? 1 : 0.55)
            .scaleEffect(pressed && !reduceMotion ? 0.97 : 1)
            .animation(HoverMotion.pressAnimation, value: pressed)
            .animation(HoverMotion.highlightAnimation, value: hovering)
            .onHover { isHovering in
                guard isHovering != hovering else { return }
                hovering = isHovering
                HoverMotion.updateCursor(hovering: isHovering && isEnabled)
            }
    }

    private func fill(pressed: Bool) -> Color {
        switch kind {
        case .neutral:
            if pressed { return .white.opacity(0.15) }
            return .white.opacity(hovering ? 0.11 : 0.06)
        case .selected:
            return accent.opacity(pressed ? 0.32 : (hovering ? 0.27 : 0.2))
        case .prominent:
            guard isEnabled else { return Theme.grayCircleDisabled }
            // Always the full accent: the label colour is chosen against it, so hover / press must
            // not thin it (the 0.97 press scale is the feedback).
            return accent
        }
    }
}

/// Text-only action on black (Clear): grey, brightening on hover.
struct NotchTextButtonStyle: ButtonStyle {
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: Theme.s(13), weight: .medium))
            .foregroundStyle(.white.opacity(configuration.isPressed ? 0.95 : (hovering ? 0.85 : 0.6)))
            .padding(.horizontal, 8)
            .frame(height: Theme.s(NotchLayout.ScheduleMetrics.footer))
            .contentShape(Rectangle())
            .animation(HoverMotion.highlightAnimation, value: hovering)
            .onHover { isHovering in
                guard isHovering != hovering else { return }
                hovering = isHovering
                HoverMotion.updateCursor(hovering: isHovering)
            }
    }
}

/// Small keycap ("⏎") shown when the typed text resolves (decorative; hidden from VoiceOver).
struct KeyHint: View {
    let key: String
    init(_ key: String) { self.key = key }

    var body: some View {
        Text(key)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white.opacity(0.5))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(RoundedRectangle(cornerRadius: 4).fill(.white.opacity(0.1)))
            .accessibilityHidden(true)
    }
}

extension View {
    /// Rows settle in one after another (~35 ms apart) as the blob grows: a short drop and
    /// un-blur from where the bottom bar was. Reduce Motion: a plain fade with the section.
    func staggered(_ index: Int, appeared: Bool, reduceMotion: Bool) -> some View {
        self
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared || reduceMotion ? 0 : -6)
            .blur(radius: appeared || reduceMotion ? 0 : 3)
            .animation(reduceMotion ? .easeOut(duration: 0.15)
                       : .easeOut(duration: 0.24).delay(0.06 + Double(index) * 0.035), value: appeared)
    }
}
