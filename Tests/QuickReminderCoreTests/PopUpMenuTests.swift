import AppKit
import Testing

@testable import QuickReminderCore

@MainActor
struct PopUpMenuTests {

    @Test func makeMenuKeepsOrderTagsAndDetail() {
        let presenter = PopUpMenu()
        let menu = presenter.makeMenu([
            .action("None", systemImage: "calendar.badge.minus") {},
            .separator,
            .action("This Weekend", systemImage: "sofa", detail: "Sat 9:00") {},
            .action("Next Week", systemImage: "calendar.badge.plus", detail: "Mon 9:00") {},
            .separator,
            .action("Custom…", systemImage: "calendar.badge.clock", keyEquivalentHint: "d") {},
        ])

        // An attributed title replaces `title` with its plain string; type-select still matches
        // on the leading row title.
        let titles = menu.items.map { $0.title.components(separatedBy: "\t")[0] }
        #expect(titles == ["None", "", "This Weekend", "Next Week", "", "Custom…"])
        #expect(menu.items.map(\.isSeparatorItem) == [false, true, false, false, true, false])
        #expect(menu.items.filter { !$0.isSeparatorItem }.map(\.tag) == [0, 1, 2, 3])

        let weekend = menu.items[2]
        let attributed = try? #require(weekend.attributedTitle)
        #expect(attributed?.string == "This Weekend\tSat 9:00")
        #expect(menu.items[0].attributedTitle == nil, "rows without a detail keep the plain title")

        let custom = menu.items[5]
        #expect(custom.keyEquivalent == "d")
        #expect(custom.keyEquivalentModifierMask == .command)
    }

    @Test func detailTabStopsShareOneRightEdge() {
        let items: [PopUpMenu.Item] = [
            .action("A", systemImage: nil, detail: "19:00") {},
            .action("A much longer row title", systemImage: nil, detail: "Sat 9:00") {},
        ]
        let location = PopUpMenu.detailTabLocation(for: items)
        let menu = PopUpMenu().makeMenu(items)
        for item in menu.items {
            let style = item.attributedTitle?.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
            #expect(style?.tabStops.first?.location == location)
            #expect(style?.tabStops.first?.alignment == .right)
        }
    }

    @Test func selectingAnItemRunsItsHandler() {
        var fired: [String] = []
        let presenter = PopUpMenu()
        let menu = presenter.makeMenu([
            .action("One", systemImage: nil) { fired.append("one") },
            .separator,
            .action("Two", systemImage: nil, detail: "x") { fired.append("two") },
        ])
        // Headless, NSMenu does not dispatch; send the item's action the way it would.
        let item = menu.items[2]
        _ = (item.target as? NSObject)?.perform(item.action, with: item)
        #expect(fired == ["two"])
    }
}
