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

    /// Reminders list colours: white text fails 4.5:1 on all of these, a dark label passes.
    @Test(arguments: [
        ("orange", 240.0, 147.0, 67.0),   // the list in the screenshots
        ("yellow", 255.0, 204.0, 0.0),
        ("blue", 10.0, 132.0, 255.0),     // Theme.accent (no list colour)
        ("purple", 191.0, 90.0, 242.0),
    ])
    func lightListColoursGetADarkLabel(name: String, r: Double, g: Double, b: Double) {
        #expect(ratioOnWhite(r, g, b) < 4.5, "\(name): white fails")
        #expect(AccentContrast.prefersDarkLabel(red: r / 255, green: g / 255, blue: b / 255), "\(name)")
        let fill = AccentContrast.relativeLuminance(red: r / 255, green: g / 255, blue: b / 255)
        #expect(AccentContrast.contrastRatio(fill, 0) >= 4.5, "\(name): black passes")
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
