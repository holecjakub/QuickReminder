import AppKit
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let showQuickReminder = Self(
        "showQuickReminder",
        default: .init(.r, modifiers: [.command, .shift])
    )
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        setupHotkey()
        Task { await RemindersService.shared.requestAccess() }
    }

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "checklist", accessibilityDescription: "QuickReminder")
            button.image?.isTemplate = true
        }

        let menu = NSMenu()
        menu.addItem(withTitle: "Show Quick Reminder", action: #selector(showPanel), keyEquivalent: "")
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        for item in menu.items {
            item.target = self
        }
        statusItem?.menu = menu
    }

    private func setupHotkey() {
        KeyboardShortcuts.onKeyDown(for: .showQuickReminder) { [weak self] in
            Task { @MainActor in
                self?.togglePanel()
            }
        }
    }

    @objc private func showPanel() {
        PanelController.shared.show()
    }

    @objc private func togglePanel() {
        PanelController.shared.toggle()
    }

    @objc private func openSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
