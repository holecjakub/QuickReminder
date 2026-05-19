import AppKit

final class QuickReminderPanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 200),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isReleasedWhenClosed = false
        animationBehavior = .utilityWindow
        backgroundColor = .clear
        hasShadow = true
    }

    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        PanelController.shared.hide()
    }
}
