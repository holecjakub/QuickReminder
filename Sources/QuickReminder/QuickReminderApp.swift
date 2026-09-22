import AppKit

/// AppKit entry point. Everything the app shows — the notch panel, the status item and the
/// Settings window — is an AppKit window that hosts SwiftUI views, so there is no SwiftUI
/// `App` / `Settings` scene. (The earlier `Settings` scene could not be opened from the status
/// item: an LSUIElement app driven by an `NSApplicationDelegate` has no responder for SwiftUI's
/// undocumented `showSettingsWindow:` and the menu item silently did nothing.)
@main
enum QuickReminderApp {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
        withExtendedLifetime(delegate) {}
    }
}
