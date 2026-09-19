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

    func show(_ items: [Item]) {
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
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    @objc private func menuItemSelected(_ sender: NSMenuItem) {
        guard actions.indices.contains(sender.tag) else { return }
        actions[sender.tag]()
    }
}
