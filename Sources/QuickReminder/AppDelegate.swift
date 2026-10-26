import AppKit
import Carbon

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    /// The launch event is only current while launching finishes; read it before it is gone.
    private var launchedInteractively = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        launchedInteractively = Self.isInteractiveLaunch(NSAppleEventManager.shared().currentAppleEvent)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        setupHotkey()
        // Create the controller now so its global click monitor (click-on-notch) is live from launch.
        _ = PanelController.shared
        Task { await RemindersService.shared.requestAccess() }
        // Launched by hand (Raycast, Spotlight, Finder, Dock) → open the panel straight away, as a
        // relaunch of the running app does. Login-item and URL-scheme launches stay silent: they
        // carry no plain "open application" event, or one flagged as a login-item launch.
        if launchedInteractively {
            DispatchQueue.main.async { PanelController.shared.show() }
        }
    }

    /// Raycast / Spotlight "open" on the already-running accessory app arrives as a reopen
    /// (there are no windows to bring forward), so it opens the panel instead.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        PanelController.shared.show()
        return false
    }

    nonisolated static func isInteractiveLaunch(_ event: NSAppleEventDescriptor?) -> Bool {
        guard let event,
              event.eventClass == AEEventClass(kCoreEventClass),
              event.eventID == AEEventID(kAEOpenApplication) else { return false }
        let launchType = event.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue
        return launchType != OSType(keyAELaunchedAsLogInItem)
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
