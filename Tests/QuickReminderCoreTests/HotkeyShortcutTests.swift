import Carbon
import Testing

@testable import QuickReminderCore

/// Display string, default value, JSON round-trip and validity for
/// `HotkeyManager.Shortcut`. Ported 1:1 from the old `Tests/QuickReminderTests.swift`
/// assertion runner.
struct HotkeyShortcutTests {

    @Test func displayStringRendersSymbolsAndKey() {
        let sc = HotkeyManager.Shortcut(keyCode: 15, modifiers: UInt32(cmdKey | shiftKey))
        #expect(sc.displayString.contains("⌘") && sc.displayString.contains("⇧") && sc.displayString.hasSuffix("R"),
                "⇧⌘R renders as symbols + R, got \(sc.displayString)")
    }

    @Test func defaultShortcutIsShiftCommandR() {
        let sc = HotkeyManager.Shortcut(keyCode: 15, modifiers: UInt32(cmdKey | shiftKey))
        #expect(HotkeyManager.Shortcut.default == sc, "default shortcut is ⇧⌘R")
    }

    @Test func shortcutRoundTripsThroughJSON() {
        let sc = HotkeyManager.Shortcut(keyCode: 15, modifiers: UInt32(cmdKey | shiftKey))
        let data = try? JSONEncoder().encode(sc)
        #expect(data.flatMap { try? JSONDecoder().decode(HotkeyManager.Shortcut.self, from: $0) } == sc,
                "shortcut round-trips through JSON")
    }

    @Test(arguments: [
        (UInt32(cmdKey), true),
        (UInt32(controlKey), true),
        (UInt32(optionKey), true),
        (UInt32(shiftKey), false),
        (UInt32(0), false),
    ])
    func isValidRequiresCommandControlOrOption(modifiers: UInt32, expected: Bool) {
        let sc = HotkeyManager.Shortcut(keyCode: 15, modifiers: modifiers)
        #expect(sc.isValid == expected)
    }
}
