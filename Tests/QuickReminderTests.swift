import AppKit
import Carbon
import SwiftUI

/// Minimal assertion-based tests for the pure parts of the app (no window needed).
/// Run with `Scripts/test.sh`.
@MainActor
enum QuickReminderTests {
    static var failures = 0

    static func check(_ condition: Bool, _ message: String, file: String = #fileID, line: Int = #line) {
        if condition { print("  ✓ \(message)") } else { failures += 1; print("  ✗ \(message)  (\(file):\(line))") }
    }

    static func run() {
        print("NotchShape")
        check(NotchShape.width(forNotchWidth: 221, topCornerRadius: 6) == 233, "width adds both top fillets")
        let closed = NotchShape(topCornerRadius: 6, bottomCornerRadius: 14).path(in: CGRect(x: 0, y: 0, width: 233, height: 38))
        check(closed.contains(CGPoint(x: 116, y: 19)), "centre is inside the silhouette")
        check(!closed.contains(CGPoint(x: 1, y: 37)), "below the top-left fillet is outside")
        check(!closed.contains(CGPoint(x: 7, y: 37)), "bottom-left rounded corner is outside")
        check(closed.contains(CGPoint(x: 3, y: 0.05)), "top edge reaches into the outward fillet (flush with the bezel)")
        let open = NotchShape(topCornerRadius: 19, bottomCornerRadius: 32).path(in: CGRect(origin: .zero, size: NotchLayout.openSize))
        check(open.boundingRect.width == NotchLayout.openSize.width, "open shape fills its rect")

        print("NotchLayout")
        check(NotchLayout.openSize.height > 38 + 150, "open panel leaves room for header, input and bottom bar")
        check(NotchLayout.closeDuration >= 0.3, "window stays until the close spring settles")

        print("NotchGeometry")
        if let screen = NSScreen.screens.first(where: { NotchGeometry.notchRect(for: $0) != nil }),
           let rect = NotchGeometry.notchRect(for: screen) {
            check(rect.height == screen.safeAreaInsets.top, "notch height equals the safe-area inset")
            check(abs(rect.midX - screen.frame.midX) < 1, "notch is horizontally centred")
        } else {
            print("  – no notched display attached, skipping notchRect checks")
        }
        if let screen = NSScreen.screens.first {
            let fallback = NotchGeometry.fallbackNotchSize(for: screen)
            check(fallback.width == 200 && fallback.height > 0, "fallback pill is 200pt wide with a positive height")
        }

        print("HotkeyManager.Shortcut")
        let sc = HotkeyManager.Shortcut(keyCode: 15, modifiers: UInt32(cmdKey | shiftKey))
        check(sc.displayString.contains("⌘") && sc.displayString.contains("⇧") && sc.displayString.hasSuffix("R"), "⇧⌘R renders as symbols + R, got \(sc.displayString)")
        check(HotkeyManager.Shortcut.default == sc, "default shortcut is ⇧⌘R")
        let data = try? JSONEncoder().encode(sc)
        check(data.flatMap { try? JSONDecoder().decode(HotkeyManager.Shortcut.self, from: $0) } == sc, "shortcut round-trips through JSON")

        print("NaturalDateParser")
        NaturalDateParserTests.run { ok, message in check(ok, message) }

        print(failures == 0 ? "\nAll checks passed." : "\n\(failures) check(s) FAILED.")
        exit(failures == 0 ? 0 : 1)
    }
}

@main
struct TestMain {
    static func main() {
        MainActor.assumeIsolated { QuickReminderTests.run() }
    }
}
