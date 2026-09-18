import AppKit

/// Borderless, transparent, non-activating panel that sits over the menu bar and the notch.
/// The visible silhouette is drawn by SwiftUI (`NotchContainerView`); the window itself is invisible.
final class NotchWindow: NSPanel {
    init(frame: NSRect) {
        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isMovable = false
        isMovableByWindowBackground = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        hidesOnDeactivate = false
        titleVisibility = .hidden
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Esc while the panel is key.
    override func cancelOperation(_ sender: Any?) {
        PanelController.shared.hide()
    }
}
