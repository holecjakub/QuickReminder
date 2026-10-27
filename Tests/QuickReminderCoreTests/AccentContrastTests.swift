import SwiftUI
import Testing

@testable import QuickReminderCore

/// Label colour on the list accent (Set button, selected time chip, picked day).
struct AccentContrastTests {
    private func ratioOnWhite(_ r: Double, _ g: Double, _ b: Double) -> Double {
        AccentContrast.contrastRatio(AccentContrast.relativeLuminance(red: r / 255, green: g / 255, blue: b / 255), 1)
    }

    @Test func luminanceEndpointsAndRatio() {
        #expect(AccentContrast.relativeLuminance(red: 0, green: 0, blue: 0) == 0)
        #expect(abs(AccentContrast.relativeLuminance(red: 1, green: 1, blue: 1) - 1) < 1e-9)
        #expect(abs(AccentContrast.contrastRatio(0, 1) - 21) < 1e-9)
        #expect(AccentContrast.contrastRatio(0.3, 0.3) == 1)
    }

    /// Light Reminders list colours: white is under 3:1, a dark label passes 4.5:1.
    @Test(arguments: [
        ("orange", 255.0, 141.0, 40.0),     // #FF8D28, white ~2.3:1
        ("green", 131.0, 215.0, 84.0),      // #83D754, ~1.8:1
        ("yellow", 255.0, 204.0, 0.0),      // ~1.5:1
        ("light blue", 27.0, 173.0, 248.0), // #1BADF8, ~2.5:1
    ])
    func lightListColoursGetADarkLabel(name: String, r: Double, g: Double, b: Double) {
        #expect(ratioOnWhite(r, g, b) < 3, "\(name): white fails")
        #expect(AccentContrast.prefersDarkLabel(red: r / 255, green: g / 255, blue: b / 255), "\(name)")
        let fill = AccentContrast.relativeLuminance(red: r / 255, green: g / 255, blue: b / 255)
        #expect(AccentContrast.contrastRatio(fill, 0) >= 4.5, "\(name): black passes")
    }

    /// Mid-tone list colours keep white, like macOS's own blue default buttons.
    @Test(arguments: [
        ("blue", 0.0, 122.0, 255.0),        // #007AFF, white ~4.0:1
        ("default blue", 10.0, 132.0, 255.0), // Theme.accent (no list colour), ~3.6:1
        ("sky blue", 0.0, 136.0, 255.0),    // #0088FF, ~3.5:1
        ("purple", 203.0, 48.0, 224.0),     // #CB30E0, ~4.2:1
        ("red", 255.0, 56.0, 60.0),         // #FF383C, ~3.6:1
    ])
    func midToneListColoursKeepWhite(name: String, r: Double, g: Double, b: Double) {
        #expect(ratioOnWhite(r, g, b) >= 3, "\(name): white passes 3:1")
        #expect(!AccentContrast.prefersDarkLabel(red: r / 255, green: g / 255, blue: b / 255), "\(name)")
    }

    @Test func darkListColoursKeepWhite() {
        #expect(!AccentContrast.prefersDarkLabel(red: 0, green: 0.25, blue: 0.63))      // deep blue
        #expect(!AccentContrast.prefersDarkLabel(red: 0.55, green: 0.12, blue: 0.10))   // dark red
        #expect(ratioOnWhite(140, 31, 26) >= 4.5)
    }

    @MainActor @Test func labelResolvesSwiftUIColours() {
        #expect(AccentContrast.label(on: .init(red: 1, green: 0.8, blue: 0)) == .black)
        #expect(AccentContrast.label(on: .init(red: 0, green: 0.25, blue: 0.63)) == .white)
    }
}
