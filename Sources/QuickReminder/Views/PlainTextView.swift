import AppKit
import SwiftUI

/// Single-line text input backed by one `NSTextView` for its whole life.
///
/// SwiftUI's `TextField` on macOS is an `NSTextField`: unfocused it draws through its cell,
/// focused it swaps in the field editor, and the two place glyphs a point apart at some font
/// sizes (15 pt here), so text visibly hopped when focus moved. A text view lays out its text
/// identically in both states. Single-line behaviour: Return submits, Tab is offered to the
/// caller (accept a date suggestion) and otherwise moves focus, line breaks in pasted text
/// become spaces, the content scrolls horizontally inside a scroller-less scroll view instead
/// of wrapping. Geometry (row height, vertical centring) is driven by AppKit layout, not by
/// SwiftUI updates, so the row is right from the first frame.
struct PlainTextView: NSViewRepresentable {
    @Binding var text: String
    var pointSize: CGFloat
    var textColor: NSColor = .white
    var accent: Color
    var identifier: String
    var placeholder: String = ""
    var onSubmit: () -> Void
    /// Return true to consume Tab; false lets focus move to the next field.
    var onTab: () -> Bool = { false }
    /// Hard cap on the field's length (a multi-MB paste would stall layout and the parser).
    var maxLength: Int = 2_000

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> RowScrollView {
        let scroll = RowScrollView()
        scroll.drawsBackground = false
        scroll.hasHorizontalScroller = false
        scroll.hasVerticalScroller = false
        scroll.horizontalScrollElasticity = .none
        scroll.verticalScrollElasticity = .none
        scroll.borderType = .noBorder
        scroll.autohidesScrollers = true
        scroll.lineHeight = Self.lineHeight(for: pointSize)

        let textView = SingleLineTextView()
        Self.configure(textView, identifier: identifier, placeholder: placeholder)
        textView.delegate = context.coordinator
        scroll.documentView = textView
        apply(to: textView)
        textView.string = text
        context.coordinator.observeUndo(of: textView)
        return scroll
    }

    /// Single-line, plain-text configuration (shared with the tests' headless text views).
    static func configure(_ textView: NSTextView, identifier: String, placeholder: String) {
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
        textView.setAccessibilityLabel(placeholder)
        textView.setAccessibilityPlaceholderValue(placeholder)
    }

    func updateNSView(_ scroll: RowScrollView, context: Context) {
        guard let textView = scroll.documentView as? NSTextView else { return }
        context.coordinator.parent = self
        scroll.lineHeight = Self.lineHeight(for: pointSize)
        apply(to: textView)
        if textView.string != text {
            Coordinator.reset(textView, to: text)
        }
        scroll.tile()
    }

    private func apply(to textView: NSTextView) {
        let font = NSFont.systemFont(ofSize: pointSize)
        if textView.font != font { textView.font = font }
        if textView.textColor != textColor { textView.textColor = textColor }
        let caret = NSColor(accent)
        if textView.insertionPointColor != caret { textView.insertionPointColor = caret }
        textView.typingAttributes = [.font: font, .foregroundColor: textColor]
    }

    /// Line height of the system font at `pointSize` (ascender + |descender| + leading).
    static func lineHeight(for pointSize: CGFloat) -> CGFloat {
        let f = NSFont.systemFont(ofSize: pointSize)
        return (f.ascender - f.descender + f.leading).rounded(.up)
    }

    /// Every kind of line break (\r, \n, U+0085, U+2028, U+2029) becomes a space.
    static func flattened(_ s: String) -> String {
        // Character-wise so "\r\n" (one grapheme) becomes one space, not two.
        String(s.map { $0.isNewline ? " " : $0 })
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: PlainTextView
        /// Each row owns its undo stack: ⌘Z in Notes must not undo a title edit.
        let rowUndoManager = UndoManager()
        private weak var textView: NSTextView?

        init(_ parent: PlainTextView) { self.parent = parent }

        func undoManager(for view: NSTextView) -> UndoManager? { rowUndoManager }

        /// Programmatic reset (new draft, suggestion stripped): the previous text's edits must
        /// not stay on the undo stack, they would point at ranges that no longer exist.
        static func reset(_ textView: NSTextView, to text: String) {
            textView.breakUndoCoalescing()
            textView.string = text
            textView.undoManager?.removeAllActions()
        }

        /// Undo/redo do not post `textDidChange`; resync the binding from the text view.
        /// Selector-based observers are removed automatically when the coordinator deallocates.
        func observeUndo(of textView: NSTextView) {
            self.textView = textView
            let center = NotificationCenter.default
            center.addObserver(self, selector: #selector(undoStackDidChange), name: .NSUndoManagerDidUndoChange, object: rowUndoManager)
            center.addObserver(self, selector: #selector(undoStackDidChange), name: .NSUndoManagerDidRedoChange, object: rowUndoManager)
        }

        @objc private func undoStackDidChange(_ notification: Notification) {
            guard let textView else { return }
            if parent.text != textView.string { parent.text = textView.string }
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            if parent.text != textView.string { parent.text = textView.string }
        }

        /// Keeps the field single-line and bounded *before* the change lands (so selection and
        /// undo stay consistent): line breaks in a paste become spaces, the result is capped.
        func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
            guard let replacement = replacementString else { return true }   // attribute-only change
            let flat = PlainTextView.flattened(replacement)
            let room = max(0, parent.maxLength - (textView.string.utf16.count - affectedCharRange.length))
            let clipped = flat.utf16.count > room ? (String(flat.utf16.prefix(room)) ?? "") : flat
            if clipped != replacement {
                // insertText registers undo and places the caret after the insertion.
                textView.insertText(clipped, replacementRange: affectedCharRange)
                return false
            }
            return true
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.insertNewline(_:)),
                 #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):
                parent.onSubmit()
                return true
            case #selector(NSResponder.insertLineBreak(_:)), #selector(NSResponder.insertParagraphSeparator(_:)):
                return true   // single line: swallow ⌃↩ / line separators
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

/// Scroll view that keeps its document text view exactly one row tall and vertically centred,
/// from AppKit's own layout pass (`tile()`), independent of SwiftUI update timing.
final class RowScrollView: NSScrollView {
    var lineHeight: CGFloat = 0

    override func tile() {
        super.tile()
        guard let textView = documentView as? NSTextView else { return }
        let rowHeight = contentView.bounds.height
        guard rowHeight > 0 else { return }
        if textView.frame.height != rowHeight {
            textView.frame.size.height = rowHeight
        }
        let inset = max(0, ((rowHeight - lineHeight) / 2).rounded(.down))
        if textView.textContainerInset.height != inset {
            textView.textContainerInset = NSSize(width: 0, height: inset)
        }
    }
}

/// Places the caret at the end when focus arrives by keyboard or the controller's first-responder
/// fallback; a mouse click keeps its own caret placement.
final class SingleLineTextView: NSTextView {
    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok, NSApp.currentEvent?.type != .leftMouseDown, selectedRange().length == 0 {
            setSelectedRange(NSRange(location: string.utf16.count, length: 0))
        }
        return ok
    }
}
