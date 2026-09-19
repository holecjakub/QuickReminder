import AppKit

/// Presents an `NSMenu` at the pointer from a plain SwiftUI `Button`, so the date options keep
/// the native menu while the trigger stays an ordinary control (SwiftUI's `Menu` with the
/// borderless style brings its own AppKit hover chrome and resizes on hover, which made the
/// whole pill row shift).
@MainActor
final class PopUpMenu: NSObject {
    enum Item {
        case action(String, systemImage: String?, () -> Void)
        case separator
    }

    private var actions: [() -> Void] = []

    /// Presents the menu just below the panel (the panel window sits above the menu's window
    /// level, so a menu popped at the pointer would be partly hidden behind it).
    func show(_ items: [Item], belowPanelAt x: CGFloat? = nil) {
        let menu = NSMenu()
        actions = []
        for item in items {
            switch item {
            case .separator:
                menu.addItem(.separator())
            case let .action(title, systemImage, handler):
                let menuItem = NSMenuItem(title: title, action: #selector(menuItemSelected(_:)), keyEquivalent: "")
                menuItem.target = self
                menuItem.tag = actions.count
                if let systemImage {
                    menuItem.image = NSImage(systemSymbolName: systemImage, accessibilityDescription: nil)
                }
                actions.append(handler)
                menu.addItem(menuItem)
            }
        }
        // Screen coordinates (Cocoa, bottom-left origin) — `in: nil` pops relative to the screen.
        var point = NSEvent.mouseLocation
        if let x, let window = NSApp.keyWindow {
            // Visible panel bottom = window bottom + overshoot padding; drop the menu right below it.
            point = NSPoint(x: x, y: window.frame.minY + NotchLayout.overshootPadding - 4)
        }
        menu.popUp(positioning: menu.items.first, at: point, in: nil)
    }

    @objc private func menuItemSelected(_ sender: NSMenuItem) {
        guard actions.indices.contains(sender.tag) else { return }
        actions[sender.tag]()
    }
}
