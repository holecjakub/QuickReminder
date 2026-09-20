import AppKit
import SwiftUI
import Testing
@testable import QuickReminderCore

/// Headless checks for the text rows and the date popup: NSTextView works without a window,
/// so the single-line contract (Return, Tab, pasted newlines, caps, undo reset) is testable.
@MainActor
struct TextInputTests {

    private final class Box { var text = ""; var submits = 0; var tabs = 0; var consumeTab = false }

    private func makeRow(maxLength: Int = 2_000) -> (NSTextView, PlainTextView.Coordinator, Box) {
        let box = Box()
        let view = PlainTextView(
            text: Binding(get: { box.text }, set: { box.text = $0 }),
            pointSize: 19,
            accent: .blue,
            identifier: "title",
            placeholder: "New Reminder",
            onSubmit: { box.submits += 1 },
            onTab: { box.tabs += 1; return box.consumeTab },
            maxLength: maxLength
        )
        let coordinator = view.makeCoordinator()
        let textView = SingleLineTextView()
        PlainTextView.configure(textView, identifier: "title", placeholder: "New Reminder")
        textView.delegate = coordinator
        coordinator.observeUndo(of: textView)
        return (textView, coordinator, box)
    }

    @Test func pastedNewlinesBecomeSpacesAndTheCaretFollows() {
        let (tv, _, box) = makeRow()
        tv.insertText("Buy", replacementRange: NSRange(location: 0, length: 0))
        tv.insertText("X\nY\r\nZ", replacementRange: NSRange(location: 3, length: 0))
        #expect(tv.string == "BuyX Y Z")
        #expect(box.text == "BuyX Y Z")
        #expect(tv.selectedRange().location == "BuyX Y Z".utf16.count, "caret sits after the flattened insertion")
    }

    @Test func lengthIsCapped() {
        let (tv, _, box) = makeRow(maxLength: 10)
        tv.insertText(String(repeating: "a", count: 25), replacementRange: NSRange(location: 0, length: 0))
        #expect(tv.string.count == 10)
        #expect(box.text.count == 10)
    }

    @Test func returnSubmitsAndTabIsOfferedFirst() {
        let (tv, c, box) = makeRow()
        #expect(c.textView(tv, doCommandBy: #selector(NSResponder.insertNewline(_:))))
        #expect(box.submits == 1 && tv.string.isEmpty)
        box.consumeTab = true
        #expect(c.textView(tv, doCommandBy: #selector(NSResponder.insertTab(_:))))
        #expect(box.tabs == 1)
        #expect(c.textView(tv, doCommandBy: #selector(NSResponder.insertLineBreak(_:))), "⌃↩ is swallowed")
        #expect(tv.string.isEmpty)
        #expect(!c.textView(tv, doCommandBy: #selector(NSResponder.cancelOperation(_:))), "Esc continues up the chain")
    }

    @Test func programmaticResetClearsTheUndoStack() {
        let (tv, c, _) = makeRow()
        tv.insertText("hello", replacementRange: NSRange(location: 0, length: 0))
        #expect(tv.undoManager === c.rowUndoManager)
        PlainTextView.Coordinator.reset(tv, to: "")
        #expect(tv.string.isEmpty)
        #expect(c.rowUndoManager.canUndo == false, "a dismissed draft must not be resurrectable / crash on ⌘Z")
    }

    @Test func lineHeightGrowsWithTheFontAndFitsTheChipSlot() {
        #expect(PlainTextView.lineHeight(for: 15) < PlainTextView.lineHeight(for: 19))
        #expect(PlainTextView.lineHeight(for: 19) >= 19)
        for scale in [0.85, 1.0, 1.3, 1.6] as [CGFloat] {
            let slot = (26 * scale).rounded(.toNearestOrEven)
            let chip = PlainTextView.lineHeight(for: (13 * scale).rounded(.toNearestOrEven)) + 10
            #expect(slot + 2 >= chip, "chip (\(chip)) fits the slot (\(slot)) at scale \(scale)")
        }
    }

    @Test func popUpMenuBuildsItemsWithSequentialTagsAndDispatches() {
        let presenter = PopUpMenu()
        var fired: [String] = []
        let menu = presenter.makeMenu([
            .action("None", systemImage: "calendar.badge.minus") { fired.append("none") },
            .separator,
            .action("Tomorrow", systemImage: nil) { fired.append("tomorrow") },
        ])
        #expect(menu.items.count == 3)
        #expect(menu.items[1].isSeparatorItem)
        #expect(menu.items[0].tag == 0 && menu.items[2].tag == 1)
        #expect(menu.items[0].image != nil && menu.items[2].image == nil)
        for item in [menu.items[2], menu.items[0]] {
            _ = item.target?.perform(item.action, with: item)
        }
        #expect(fired == ["tomorrow", "none"])
        let stray = NSMenuItem(title: "x", action: nil, keyEquivalent: "")
        stray.tag = 99
        _ = menu.items[0].target?.perform(menu.items[0].action, with: stray)
        #expect(fired.count == 2, "an out-of-range tag is ignored")
    }
}
