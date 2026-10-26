import AppKit

/// Presents an `NSMenu` at the pointer from a plain SwiftUI `Button`, so the date options keep
/// the native menu while the trigger stays an ordinary control (SwiftUI's `Menu` with the
/// borderless style brings its own AppKit hover chrome and resizes on hover, which made the
/// whole pill row shift).
@MainActor
final class PopUpMenu: NSObject {
    enum Item {
        /// `detail` is drawn right-aligned in the secondary colour on the same line ("Sat 9:00");
        /// `keyEquivalentHint` is a ⌘ + key shortcut shown at the trailing edge (e.g. "d" → ⌘D).
        case action(String, systemImage: String?, detail: String? = nil, keyEquivalentHint: String? = nil, () -> Void)
        case separator
    }

    private var actions: [() -> Void] = []

    /// Presents the menu just below the panel (the panel window sits above the menu's window
    /// level, so a menu popped at the pointer would be partly hidden behind it).
    func show(_ items: [Item], belowPanelAt x: CGFloat? = nil) {
        let menu = makeMenu(items)
        // The tracking loop swallows the hover exit; drop the hand cursor before it starts.
        HoverMotion.updateCursor(hovering: false)
        show(menu, belowPanelAt: x)
    }

    /// Builds the menu (separately testable): items get tags in order, separators none.
    func makeMenu(_ items: [Item]) -> NSMenu {
        let menu = NSMenu()
        actions = []
        let detailTab = Self.detailTabLocation(for: items)
        for item in items {
            switch item {
            case .separator:
                menu.addItem(.separator())
            case let .action(title, systemImage, detail, keyHint, handler):
                let menuItem = NSMenuItem(title: title, action: #selector(menuItemSelected(_:)), keyEquivalent: "")
                menuItem.target = self
                menuItem.tag = actions.count
                if let systemImage {
                    menuItem.image = NSImage(systemSymbolName: systemImage, accessibilityDescription: nil)
                }
                if let detail {
                    menuItem.attributedTitle = Self.titleWithDetail(title, detail, tabLocation: detailTab)
                    menuItem.setAccessibilityLabel("\(title), \(detail)")
                }
                if let keyHint {
                    // Display (and, while the menu is open, also triggers the item); the panel
                    // owns the real shortcut.
                    menuItem.keyEquivalent = keyHint
                    menuItem.keyEquivalentModifierMask = .command
                }
                actions.append(handler)
                menu.addItem(menuItem)
            }
        }
        return menu
    }

    // MARK: Detail column

    private static var menuFont: NSFont { NSFont.menuFont(ofSize: 0) }

    /// One line, title then a right-aligned detail at a shared tab stop (a `subtitle` would add
    /// a second line and make the menu twice as tall).
    static func titleWithDetail(_ title: String, _ detail: String, tabLocation: CGFloat) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.tabStops = [NSTextTab(textAlignment: .right, location: tabLocation)]
        let text = NSMutableAttributedString(string: title + "\t", attributes: [
            .font: menuFont, .paragraphStyle: paragraph, .foregroundColor: NSColor.labelColor,
        ])
        text.append(NSAttributedString(string: detail, attributes: [
            .font: menuFont, .paragraphStyle: paragraph, .foregroundColor: NSColor.secondaryLabelColor,
        ]))
        return text
    }

    /// Widest title + a gap + widest detail, so every detail ends on the same right edge.
    static func detailTabLocation(for items: [Item]) -> CGFloat {
        var titleWidth: CGFloat = 0, detailWidth: CGFloat = 0
        let attributes: [NSAttributedString.Key: Any] = [.font: menuFont]
        for case let .action(title, _, detail, _, _) in items {
            titleWidth = max(titleWidth, (title as NSString).size(withAttributes: attributes).width)
            if let detail { detailWidth = max(detailWidth, (detail as NSString).size(withAttributes: attributes).width) }
        }
        return (titleWidth + 28 + detailWidth).rounded(.up)
    }

    func show(_ menu: NSMenu, belowPanelAt x: CGFloat?) {
        // Screen coordinates (Cocoa, bottom-left origin) — `in: nil` pops relative to the screen.
        var point = NSEvent.mouseLocation
        if let x, let window = NSApp.windows.first(where: { $0 is NotchWindow }) {
            // Visible panel bottom = window bottom + overshoot padding. With `positioning: nil` the
            // point is the menu's top-left corner (the first item sits below the menu's own top
            // inset), so a 2 pt gap keeps the whole menu clear of the panel.
            point = NSPoint(x: x, y: window.frame.minY + NotchLayout.overshootPadding - 2)
        }
        menu.popUp(positioning: nil, at: point, in: nil)
    }

    @objc private func menuItemSelected(_ sender: NSMenuItem) {
        guard actions.indices.contains(sender.tag) else { return }
        actions[sender.tag]()
    }
}
