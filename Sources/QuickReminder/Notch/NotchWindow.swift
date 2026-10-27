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
        // Pointer moves reach the local monitor that keeps the transparent canvas click-through.
        acceptsMouseMovedEvents = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Esc while the panel is key.
    override func cancelOperation(_ sender: Any?) {
        PanelController.shared.hide()
    }

    /// A mouse-down on the parked (closed) notch opens the panel. Handled here rather than
    /// with a SwiftUI gesture so a click landing mid hover-swell animation cannot be missed;
    /// black pixels are the only ones that receive events (transparent margins pass through).
    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown, PanelController.shared.notchTapped() {
            return
        }
        super.sendEvent(event)
    }
}
