import AppKit
import SwiftUI

/// Single-line text input backed by one `NSTextView` for its whole life.
///
/// SwiftUI's `TextField` on macOS is an `NSTextField`: unfocused it draws through its cell,
/// focused it swaps in the field editor, and the two place glyphs a point apart at some font
/// sizes (15 pt here), so text visibly hopped when focus moved. A text view lays out its text
/// identically in both states. Single-line behaviour: Return submits, Tab is offered to the
/// caller (accept a date suggestion) and otherwise moves focus, the content scrolls
/// horizontally inside a scroller-less scroll view instead of wrapping.
struct PlainTextView: NSViewRepresentable {
    @Binding var text: String
    var pointSize: CGFloat
    var textColor: NSColor = .white
    var accent: Color
    var identifier: String
    var onSubmit: () -> Void
    /// Return true to consume Tab; false lets focus move to the next field.
    var onTab: () -> Bool = { false }
    /// Hard cap on the field's length (a multi-MB paste would stall layout and the parser).
    var maxLength: Int = 2_000

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasHorizontalScroller = false
        scroll.hasVerticalScroller = false
        scroll.horizontalScrollElasticity = .none
        scroll.verticalScrollElasticity = .none
        scroll.borderType = .noBorder
        scroll.autohidesScrollers = true

        let textView = SingleLineTextView()
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.usesFontPanel = false
        textView.usesFindPanel = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isHorizontallyResizable = true
        textView.isVerticallyResizable = false
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.setAccessibilityIdentifier(identifier)
        scroll.documentView = textView
        apply(to: textView)
        textView.string = text
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let textView = scroll.documentView as? NSTextView else { return }
        context.coordinator.parent = self
        apply(to: textView)
        if textView.string != text {
            textView.string = text
            // A programmatic reset (new draft) must not leave the old draft on the undo stack.
            textView.undoManager?.removeAllActions()
        }
        // Keep the text view as tall as the row so the caret and the glyphs stay put.
        let rowHeight = scroll.bounds.height
        if textView.frame.height != rowHeight, rowHeight > 0 {
            textView.frame.size.height = rowHeight
            textView.textContainerInset = NSSize(width: 0, height: max(0, (rowHeight - Self.lineHeight(for: pointSize)) / 2))
        }
    }

    private func apply(to textView: NSTextView) {
        let font = NSFont.systemFont(ofSize: pointSize)
        if textView.font != font { textView.font = font }
        textView.textColor = textColor
        textView.insertionPointColor = NSColor(accent)
        textView.typingAttributes = [.font: font, .foregroundColor: textColor]
    }

    /// Line height of the system font at `pointSize` (ascender + |descender| + leading).
    static func lineHeight(for pointSize: CGFloat) -> CGFloat {
        let f = NSFont.systemFont(ofSize: pointSize)
        return (f.ascender - f.descender + f.leading).rounded(.up)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: PlainTextView
        init(_ parent: PlainTextView) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            if parent.text != textView.string { parent.text = textView.string }
        }

        /// Keeps the field single-line and bounded *before* the change lands (so selection and
        /// undo stay consistent): every kind of line break (\r, \n, U+0085, U+2028, U+2029) in a
        /// paste becomes a space, and the result is capped at `maxLength`.
        func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
            guard let replacement = replacementString else { return true }   // attribute-only change
            let flat = replacement.components(separatedBy: .newlines).joined(separator: " ")
            let resulting = textView.string.utf16.count - affectedCharRange.length + flat.utf16.count
            if flat != replacement || resulting > parent.maxLength {
                let room = max(0, parent.maxLength - (textView.string.utf16.count - affectedCharRange.length))
                let clipped = String(flat.utf16.prefix(room)) ?? ""
                if textView.shouldChangeText(in: affectedCharRange, replacementString: clipped) {
                    textView.replaceCharacters(in: affectedCharRange, with: clipped)
                    textView.didChangeText()
                }
                return false
            }
            return true
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.insertNewline(_:)):
                parent.onSubmit()
                return true
            case #selector(NSResponder.insertLineBreak(_:)), #selector(NSResponder.insertParagraphSeparator(_:)):
                return true   // single line: swallow ⌃↩ / ⌥↩ line breaks
            case #selector(NSResponder.insertTab(_:)):
                if parent.onTab() { return true }
                textView.window?.selectNextKeyView(nil)
                return true
            case #selector(NSResponder.insertBacktab(_:)):
                textView.window?.selectPreviousKeyView(nil)
                return true
            default:
                return false   // Esc etc. continue up the responder chain (the window handles Esc)
            }
        }
    }
}

/// NSTextView that reports the row height as its own so AppKit never grows it to two lines.
final class SingleLineTextView: NSTextView {
    override var acceptsFirstResponder: Bool { true }
    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        // Place the caret at the end when focus arrives by keyboard or first responder fallback.
        if ok, selectedRange().length == 0, selectedRange().location > string.utf16.count {
            setSelectedRange(NSRange(location: string.utf16.count, length: 0))
        }
        return ok
    }
}
