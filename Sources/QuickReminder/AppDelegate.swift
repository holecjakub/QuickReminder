import AppKit
import Carbon

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        setupHotkey()
        // Create the controller now so its global click monitor (click-on-notch) is live from launch.
        _ = PanelController.shared
        Task { await RemindersService.shared.requestAccess() }
    }

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem?.button else { return }

        let symbolNames = ["checklist", "list.bullet.clipboard", "list.bullet", "checkmark.circle"]
        var image: NSImage?
        for name in symbolNames {
            if let img = NSImage(systemSymbolName: name, accessibilityDescription: "QuickReminder") {
                image = img
                break
            }
        }
        if let image {
            image.isTemplate = true
            button.image = image
        } else {
            button.title = "QR"
        }
        button.toolTip = "QuickReminder — \(HotkeyManager.shared.shortcut.displayString)"

        let menu = NSMenu()
        menu.addItem(withTitle: "Show Quick Reminder", action: #selector(showPanel), keyEquivalent: "")
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        // Only our own actions target the delegate; Quit goes down the responder chain to
        // NSApplication (a delegate target cannot perform `terminate:` and the item is disabled).
        for item in menu.items where item.action != #selector(NSApplication.terminate(_:)) {
            item.target = self
        }
        statusItem?.menu = menu
    }

    private func setupHotkey() {
        HotkeyManager.shared.onPressed = { [weak self] in
            self?.togglePanel()
        }
        HotkeyManager.shared.register()
    }

    @objc private func showPanel() {
        PanelController.shared.show()
    }

    @objc private func togglePanel() {
        PanelController.shared.toggle()
    }

    @objc private func openSettings() {
        SettingsWindowController.shared.show()
    }

    /// Timestamps of recent URL-scheme commands, for rate limiting (any app or web page can send them).
    private var urlCommandTimes: [Date] = []

    func application(_ application: NSApplication, open urls: [URL]) {
        // Never move keyboard focus while a password field has Secure Event Input enabled.
        guard !IsSecureEventInputEnabled() else { return }
        // One command per call: several URLs in one `open` must not bypass the limiter.
        guard let url = urls.first(where: { $0.scheme?.lowercased() == "quickreminder" }) else { return }
        // Debounce (≥ 1 s apart) and cap at 5 commands per minute so a looping page cannot
        // flicker the panel or keep stealing keystrokes.
        let now = Date()
        urlCommandTimes.removeAll { now.timeIntervalSince($0) > 60 }
        if let last = urlCommandTimes.last, now.timeIntervalSince(last) < 1 { return }
        guard urlCommandTimes.count < 5 else { return }
        urlCommandTimes.append(now)

        let command = url.host ?? url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        switch command.lowercased() {
        case "show":
            PanelController.shared.show()
        case "toggle":
            PanelController.shared.toggle()
        case "hide":
            PanelController.shared.hide()
        default:
            break
        }
    }
}
