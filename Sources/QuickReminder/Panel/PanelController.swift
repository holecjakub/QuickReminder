import AppKit
import SwiftUI

/// Owns the notch window and drives the expand / collapse choreography.
/// Public API (`show`, `hide`, `toggle`) is what the hotkey, menu bar and URL scheme call.
@MainActor
final class PanelController {
    static let shared = PanelController()

    let state = NotchState()

    private var window: NotchWindow?
    private var hostingView: NSHostingView<AnyView>?
    private var globalClickMonitor: Any?
    private var localEventMonitor: Any?
    private var openGeneration = UUID()
    private var closeTask: Task<Void, Never>?
    private var isVisible = false

    private init() {
        installGlobalClickMonitor()
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.relayout() }
        }
    }

    // MARK: - Public

    func toggle() {
        if isVisible && !state.isSaving { hide() } else { show() }
    }

    func show() {
        // Re-opening during the "saved" hold counts as a reopen from the pill.
        let reopeningFromSaved = isVisible && state.isSaving
        guard !isVisible || reopeningFromSaved else { return }
        // Re-opening while the collapse animation is still running: don't snap
        // back to the notch, just reverse from wherever the shape currently is.
        let wasClosing = closeTask != nil || reopeningFromSaved
        closeTask?.cancel()
        closeTask = nil
        saveTask?.cancel()
        saveTask = nil
        // The badge (if any) is invisible or about to be; drop it and give the ✓ button its
        // geometry back without animating either.
        var noAnimation = Transaction()
        noAnimation.disablesAnimations = true
        withTransaction(noAnimation) {
            state.savedBadgeShown = false
            state.isSaving = false
        }

        let screen = targetScreen()
        configureGeometry(for: screen)
        let window = ensureWindow()
        if !wasClosing {
            window.setFrame(windowFrame(for: screen), display: false)
            // Start collapsed so the first frame is indistinguishable from the bezel.
            state.isOpen = false
            state.isSaving = false
            state.savedBadgeShown = false
            state.contentVisible = false
        }
        window.ignoresMouseEvents = false
        window.makeKeyAndOrderFront(nil)
        isVisible = true
        installLocalEventMonitor()
        NotificationCenter.default.post(name: .panelWillShow, object: nil)

        // Next run-loop turn: expand.
        DispatchQueue.main.async { [state] in
            withAnimation(NotchLayout.effectiveOpen) { state.isOpen = true }
            withAnimation(NotchLayout.effectiveContentIn) { state.contentVisible = true }
        }
        let openGeneration = UUID()
        self.openGeneration = openGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self, self.isVisible, self.openGeneration == openGeneration else { return }
            self.state.isSettled = true
        }
        // SwiftUI's @FocusState can lose the race against the window becoming key,
        // so re-assert keyboard focus on the title field once the content is in.
        for delay in [0.12, 0.30] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.focusTitleFieldIfNeeded()
            }
        }
    }

    /// Makes the first editable text field in the hosting view the first responder
    /// unless the user is already editing something.
    private func focusTitleFieldIfNeeded() {
        guard isVisible, let window, let hostingView else { return }
        if window.firstResponder is NSTextView { return }
        window.makeKey()
        if let field = Self.firstTextField(in: hostingView) {
            window.makeFirstResponder(field)
        }
    }

    private static func firstTextField(in view: NSView) -> NSTextField? {
        for sub in view.subviews {
            if let field = sub as? NSTextField, field.isEditable { return field }
            if let found = firstTextField(in: sub) { return found }
        }
        return nil
    }

    func hide() {
        guard isVisible, let window else { return }
        isVisible = false
        saveTask?.cancel()
        saveTask = nil
        NotificationCenter.default.post(name: .panelDidHide, object: nil)

        removeLocalEventMonitor()
        state.isSettled = false
        withAnimation(NotchLayout.effectiveContentOut) { state.contentVisible = false }
        withAnimation(NotchLayout.effectiveClose) {
            state.isOpen = false
            state.isSaving = false
        }

        closeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(NotchLayout.closeDuration))
            guard !Task.isCancelled, let self, !self.isVisible else { return }
            window.ignoresMouseEvents = true
            window.orderOut(nil)
            var noAnimation = Transaction()
            noAnimation.disablesAnimations = true
            withTransaction(noAnimation) { self.state.savedBadgeShown = false }
            self.closeTask = nil
        }
    }

    /// Reminders-style "saved" choreography: the panel collapses to notch height but stays
    /// wider at the sides, the ✓ flies into the right-hand extension and draws itself in,
    /// then the notch returns to its normal size.
    func collapseAfterSave() {
        guard isVisible, !state.isSaving, let window else { return }
        if NotchLayout.reduceMotion {
            hide()
            return
        }
        // Input is done: no clicks, no keystrokes into the invisible field, and the
        // settle timer from show() must not drop the mask mid-choreography.
        removeLocalEventMonitor()
        window.ignoresMouseEvents = true
        window.makeFirstResponder(nil)
        openGeneration = UUID()
        state.isSettled = false
        withAnimation(NotchLayout.contentOutAnimation) { state.contentVisible = false }
        withAnimation(NotchLayout.savingAnimation) {
            state.isOpen = false
            state.isSaving = true
            state.savedBadgeShown = true   // same transaction as the button's removal → the ✓ flies
        }
        saveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(NotchLayout.savedHold))
            guard !Task.isCancelled, let self, self.isVisible else { return }
            self.saveTask = nil
            self.hide()
        }
    }

    private var saveTask: Task<Void, Never>?

    // MARK: - Window & geometry

    private func ensureWindow() -> NotchWindow {
        if let window { return window }
        let screen = targetScreen()
        let window = NotchWindow(frame: windowFrame(for: screen))
        let root = AnyView(
            NotchContainerView()
                .environmentObject(state)
                .environment(\.colorScheme, .dark)
        )
        let hosting = NSHostingView(rootView: root)
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        window.contentView = hosting
        self.hostingView = hosting
        self.window = window
        return window
    }

    /// Prefer the built-in display with a notch; otherwise the screen under the mouse.
    private func targetScreen() -> NSScreen {
        if let notched = NSScreen.screens.first(where: { NotchGeometry.notchRect(for: $0) != nil }) {
            return notched
        }
        let loc = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(loc, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }

    private func configureGeometry(for screen: NSScreen) {
        setClosedSize(NotchGeometry.closedShapeSize(for: screen, topCornerRadius: NotchLayout.closedTopRadius))
        if state.openSize != NotchLayout.openSize { state.openSize = NotchLayout.openSize }
    }

    /// Publishing unchanged values would re-render the whole panel for nothing.
    private func setClosedSize(_ size: CGSize) {
        if state.closedSize != size { state.closedSize = size }
    }

    /// Window covers the fully-open panel, anchored to the top edge, centred on the notch.
    private func windowFrame(for screen: NSScreen) -> NSRect {
        let size = NotchLayout.canvasSize
        let centerX: CGFloat
        if let notch = NotchGeometry.notchRect(for: screen) {
            centerX = notch.midX
        } else {
            centerX = screen.frame.midX
        }
        return NSRect(
            x: centerX - size.width / 2,
            y: screen.frame.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }

    private func relayout() {
        guard let window else { return }
        let screen = targetScreen()
        configureGeometry(for: screen)
        window.setFrame(windowFrame(for: screen), display: true)
    }

    // MARK: - Global mouse handling

    /// One global monitor for the app's lifetime:
    /// - panel open  → any click outside our window collapses it
    /// - panel closed → a click on the physical notch expands it
    private func installGlobalClickMonitor() {
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            // Global monitor handlers run on the main thread; no hop needed.
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.isVisible {
                    self.hide()
                } else if event.type == .leftMouseDown, self.isOnNotch(NSEvent.mouseLocation) {
                    self.show()
                }
            }
        }
    }

    /// While open: Esc always collapses (even when a text field owns the key loop),
    /// and a click inside the window but outside the black silhouette collapses too
    /// (the global monitor never sees our own window's events).
    private func installLocalEventMonitor() {
        guard localEventMonitor == nil else { return }
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, self.isVisible, event.window === self.window else { return event }
            if event.type == .keyDown {
                if event.keyCode == 53 { // Esc
                    self.hide()
                    return nil
                }
                return event
            }
            if let hosting = self.hostingView {
                let point = hosting.convert(event.locationInWindow, from: nil)
                if !self.silhouetteContains(point, in: hosting.bounds) {
                    self.hide()
                    return nil
                }
            }
            return event
        }
    }

    private func removeLocalEventMonitor() {
        if let localEventMonitor {
            NSEvent.removeMonitor(localEventMonitor)
            self.localEventMonitor = nil
        }
    }

    /// Hit-test against the open silhouette (top-anchored, centred) in the hosting view's flipped-or-not coords.
    /// Hit-test against the silhouette as currently drawn (top-anchored, centred in the canvas).
    private func silhouetteContains(_ point: CGPoint, in bounds: CGRect) -> Bool {
        guard let hostingView else { return false }
        // Convert to top-down canvas coordinates regardless of the hosting view's flippedness.
        let topDown = CGPoint(x: point.x, y: hostingView.isFlipped ? point.y : bounds.maxY - point.y)
        return NotchShape.contains(
            topDown,
            canvasWidth: bounds.width,
            shapeSize: state.currentSize,
            topCornerRadius: state.isOpen ? NotchLayout.openTopRadius : NotchLayout.closedTopRadius,
            bottomCornerRadius: state.isOpen ? NotchLayout.openBottomRadius : NotchLayout.closedBottomRadius
        )
    }

    private func isOnNotch(_ point: NSPoint) -> Bool {
        for screen in NSScreen.screens {
            if let notch = NotchGeometry.notchRect(for: screen), notch.insetBy(dx: -8, dy: 0).contains(point) {
                return true
            }
        }
        return false
    }
}

extension Notification.Name {
    static let panelWillShow = Notification.Name("PanelWillShow")
    static let panelDidHide = Notification.Name("PanelDidHide")
}
