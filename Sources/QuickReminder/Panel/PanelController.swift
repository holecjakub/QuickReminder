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
        if isVisible { hide() } else { show() }
    }

    func show() {
        guard !isVisible else { return }
        // Re-opening while the collapse animation is still running: don't snap
        // back to the notch, just reverse from wherever the shape currently is.
        let wasClosing = closeTask != nil
        closeTask?.cancel()
        closeTask = nil

        let screen = targetScreen()
        configureGeometry(for: screen)
        let window = ensureWindow()
        if !wasClosing {
            window.setFrame(windowFrame(for: screen), display: false)
            // Start collapsed so the first frame is indistinguishable from the bezel.
            state.isOpen = false
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
        NotificationCenter.default.post(name: .panelDidHide, object: nil)

        removeLocalEventMonitor()
        withAnimation(NotchLayout.effectiveContentOut) { state.contentVisible = false }
        withAnimation(NotchLayout.effectiveClose) { state.isOpen = false }

        closeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(NotchLayout.closeDuration))
            guard !Task.isCancelled, let self, !self.isVisible else { return }
            window.ignoresMouseEvents = true
            window.orderOut(nil)
            self.closeTask = nil
        }
    }

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
        if let notch = NotchGeometry.notchRect(for: screen) {
            // Shape width includes the two outward top fillets; +2/+1 hides anti-aliasing seams around the bezel.
            state.closedSize = CGSize(
                width: NotchShape.width(forNotchWidth: notch.width, topCornerRadius: NotchLayout.closedTopRadius) + 2,
                height: notch.height + 1
            )
        } else {
            let fallback = NotchGeometry.fallbackNotchSize(for: screen)
            state.closedSize = CGSize(
                width: NotchShape.width(forNotchWidth: fallback.width, topCornerRadius: NotchLayout.closedTopRadius),
                height: fallback.height
            )
        }
        state.openSize = NotchLayout.openSize
    }

    /// Window covers the fully-open panel, anchored to the top edge, centred on the notch.
    private func windowFrame(for screen: NSScreen) -> NSRect {
        let size = NotchLayout.openSize
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
            let location = NSEvent.mouseLocation
            Task { @MainActor in
                guard let self else { return }
                if self.isVisible {
                    self.hide()
                } else if event.type == .leftMouseDown, self.isOnNotch(location) {
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
    private func silhouetteContains(_ point: CGPoint, in bounds: CGRect) -> Bool {
        let size = state.openSize
        // Hosting view is not flipped: y grows upward, shape hangs from the top edge.
        let rect = CGRect(x: bounds.midX - size.width / 2, y: bounds.maxY - size.height, width: size.width, height: size.height)
        let path = NotchShape(topCornerRadius: NotchLayout.openTopRadius, bottomCornerRadius: NotchLayout.openBottomRadius)
            .path(in: CGRect(origin: .zero, size: size))
        // NotchShape draws top-down (minY = top); mirror the point into that space.
        let local = CGPoint(x: point.x - rect.minX, y: rect.maxY - point.y)
        return path.contains(local)
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
