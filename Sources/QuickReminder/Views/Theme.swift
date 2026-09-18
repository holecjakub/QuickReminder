import SwiftUI

/// Colours sampled from the iOS 26 quick-reminder overlay (reference/ios26-quickreminder.png).
enum Theme {
    /// iOS systemBlue in dark mode.
    static let accent = Color(red: 0x0A / 255, green: 0x84 / 255, blue: 0xFF / 255)
    /// Placeholder text ("New Reminder").
    static let placeholder = Color(red: 0x59 / 255, green: 0x59 / 255, blue: 0x5D / 255)
    /// Secondary placeholder ("Notes").
    static let placeholderSecondary = Color(red: 0x59 / 255, green: 0x59 / 255, blue: 0x5D / 255)
    /// Dashed empty-checkbox ring.
    static let dashedRing = Color(red: 0x59 / 255, green: 0x59 / 255, blue: 0x5D / 255)
    /// Filled gray circles (close button, disabled save button).
    static let grayCircle = Color(red: 0x59 / 255, green: 0x59 / 255, blue: 0x5D / 255)
    /// Disabled save button is a touch darker than the close button in the reference.
    static let grayCircleDisabled = Color(red: 0x47 / 255, green: 0x47 / 255, blue: 0x49 / 255)
    /// Pill background / stroke.
    static let pillFill = Color.white.opacity(0.03)
    static let pillStroke = Color(red: 0x3D / 255, green: 0x3D / 255, blue: 0x3F / 255)
    static let flagOrange = Color(red: 1.0, green: 0.62, blue: 0.04)

    static let horizontalPadding: CGFloat = 20
}
