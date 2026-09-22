import AppKit
import SwiftUI

/// The Settings… window: one plain `NSWindow` hosting `SettingsView`, created on first use and
/// kept for the app's lifetime (closing hides it; reopening shows the same window).
@MainActor
final class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()

    private init() {
        let hosting = NSHostingController(rootView: SettingsView())
        let window = NSWindow(contentViewController: hosting)
        window.title = "QuickReminder Settings"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.setContentSize(hosting.view.fittingSize)
        window.setFrameAutosaveName("SettingsWindow")
        window.center()
        super.init(window: window)
    }

    required init?(coder: NSCoder) { fatalError("SettingsWindowController is code-only") }

    /// Brings the window to the front. The app is an accessory (LSUIElement), so it has to
    /// activate itself for the window to take keyboard focus; the notch panel is unaffected
    /// (it is a non-activating panel on its own window level).
    func show() {
        NSApp.activate()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}
