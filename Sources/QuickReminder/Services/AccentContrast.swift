import AppKit
import SwiftUI

/// Text on a fill of the list's colour (the Set button, the selected time chip, the picked day).
/// The colour is the user's list colour, so white is not always readable: white on system orange
/// is ~2.3:1, on yellow ~1.5:1. Body-size text needs 4.5:1 (WCAG 1.4.3); the label is white when
/// it reaches that, otherwise black (whichever of the two contrasts more).
enum AccentContrast {
    /// WCAG minimum for normal-size text.
    static let minimumTextContrast = 4.5

    /// WCAG relative luminance of an sRGB colour (components 0…1).
    static func relativeLuminance(red: Double, green: Double, blue: Double) -> Double {
        func linear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    /// WCAG contrast ratio of two relative luminances (order does not matter), 1…21.
    static func contrastRatio(_ a: Double, _ b: Double) -> Double {
        (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    /// Whether a label on a fill of this colour should be dark instead of white.
    static func prefersDarkLabel(red: Double, green: Double, blue: Double) -> Bool {
        let fill = relativeLuminance(red: red, green: green, blue: blue)
        let onWhite = contrastRatio(fill, 1)
        if onWhite >= minimumTextContrast { return false }
        return contrastRatio(fill, 0) > onWhite
    }

    /// Label colour for text on `fill` (resolved in sRGB; an unresolvable colour keeps white).
    @MainActor static func label(on fill: Color) -> Color {
        guard let rgb = NSColor(fill).usingColorSpace(.sRGB) else { return .white }
        return prefersDarkLabel(red: Double(rgb.redComponent), green: Double(rgb.greenComponent), blue: Double(rgb.blueComponent))
            ? .black : .white
    }
}
