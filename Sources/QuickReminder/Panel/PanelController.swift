import AppKit
import SwiftUI

/// Owns the notch window and drives the expand / collapse choreography.
/// Public API (`show`, `hide`, `toggle`) is what the hotkey, menu bar and URL scheme call.
///
/// Every decision lives in `NotchMachine` (a pure reducer, see `NotchMachine.swift`); this
/// class feeds it events and performs the effects it returns against AppKit / SwiftUI.
@MainActor
final class PanelController {
    static let shared = PanelController()

    let state = NotchState()

    private var machine = NotchMachine()
    /// Events that arrive while effects are being performed run after the current batch,
    /// so the machine never sees an event in the middle of its own effect list.
    private var pendingEvents: [(event: NotchEvent, screen: NSScreen?)] = []
    private var isDispatching = false

    private var window: NotchWindow?
    private var hostingView: NSHostingView<AnyView>?
    private var globalClickMonitor: Any?
    private var localEventMonitor: Any?
    /// Pending hover dwell (the swell + haptic fire only after the pointer stays ~90 ms).
    private var hoverDwell: DispatchWorkItem?
    private var closeTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?

    /// The window stays ordered in over a physical notch while closed; displays without one
    /// keep the order-out behaviour so no black pill is painted on an external monitor.
    private func shouldStayParked(on screen: NSScreen) -> Bool {
        NotchGeometry.notchRect(for: screen) != nil
    }

    private init() {
        installGlobalClickMonitor()
        // On a notched display the window lives permanently over the notch (like boring.notch):
        // its closed silhouette is indistinguishable from the bezel and gives us hover + click
        // without any system-wide mouse polling.
        if let screen = targetScreen(), shouldStayParked(on: screen) {
            dispatch(.screenChanged(hasNotch: true), on: screen)
        }
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
        if machine.phase == .open { hide() } else { show() }
    }

    func show() {
        // nil while displays are being reconfigured; nothing to show on then.
        guard let screen = targetScreen() else { return }
        dispatch(.show, on: screen)
    }

    func hide() {
        dispatch(.hide, on: nil)
    }

    /// Reminders-style "saved" choreography: the panel collapses to notch height but stays
    /// wider at the sides, the ✓ flies into the right-hand extension and draws itself in,
    /// then the notch returns to its normal size.
    func collapseAfterSave() {
        dispatch(.save(reduceMotion: NotchLayout.reduceMotion), on: nil)
    }

    // MARK: - Hover / tap on the closed notch (tracking comes from the SwiftUI silhouette)

    func notchHoverChanged(_ hovering: Bool) {
        dispatch(hovering ? .hoverEntered : .hoverExited, on: nil)
    }

    /// Returns true when the click was consumed (the closed notch opened); false lets the
    /// event continue to the views (buttons etc.) while the panel is open.
    func notchTapped() -> Bool {
        guard case .closed(parked: true) = machine.phase, let screen = targetScreen() else { return false }
        dispatch(.notchTapped, on: screen)
        return true
    }

    // MARK: - Reducer loop

    /// Feeds one event to the machine and performs the resulting effects on `screen`
    /// (the target screen; nil for events whose effects never need one).
    private func dispatch(_ event: NotchEvent, on screen: NSScreen?) {
        pendingEvents.append((event, screen))
        guard !isDispatching else { return }
        isDispatching = true
        defer { isDispatching = false }
        while !pendingEvents.isEmpty {
            let (event, screen) = pendingEvents.removeFirst()
            let pointerOnNotch: Bool
            switch event {
            case .closeTimerFired(hasNotch: true), .screenChanged(hasNotch: true):
                // Hover arms from where the pointer is when the notch parks.
                pointerOnNotch = isOnNotch(NSEvent.mouseLocation, slack: NotchLayout.hoverGrowth.width / 2)
            default:
                pointerOnNotch = false
            }
            for effect in machine.handle(event, pointerOnNotch: pointerOnNotch) {
                perform(effect, on: screen)
            }
        }
    }

    private func perform(_ effect: NotchEffect, on screen: NSScreen?) {
        switch effect {
        // Window & geometry
        case .configureGeometry:
            if let screen { configureGeometry(for: screen) }

        case .switchToOpenCanvas:
            // Grow the window to the full canvas (no animation: the silhouette keeps its place,
            // both frames are top-aligned and centred on the notch), start collapsed.
            guard let screen else { return }
            let window = ensureWindow(on: screen)
            var noAnim = Transaction(); noAnim.disablesAnimations = true
            withTransaction(noAnim) { state.canvasSize = NotchLayout.canvasSize }
            window.setFrame(windowFrame(for: screen), display: false)
            if state.isOpen { state.isOpen = false }
            if state.contentVisible { state.contentVisible = false }

        case .relayoutOpenWindow:
            if let screen { window?.setFrame(windowFrame(for: screen), display: true) }

        case .makeKeyAndOrderFront:
            guard let screen else { return }
            let window = ensureWindow(on: screen)
            window.sharingType = .readOnly   // the open panel may appear in screenshots / sharing
            window.makeKeyAndOrderFront(nil)

        case .park:
            if let screen { parkClosed(on: screen) }

        case .orderOut:
            resetOpenFlagsWithoutAnimation()
            window?.ignoresMouseEvents = true
            window?.orderOut(nil)

        case .setIgnoresMouse(let ignores):
            // During the collapse / saved hold no input is needed; clicks reach what is below.
            window?.ignoresMouseEvents = ignores

        case .resignFirstResponder:
            window?.makeFirstResponder(nil)

        // Monitors & notifications
        case .installLocalMonitor:
            installLocalEventMonitor()

        case .removeLocalMonitor:
            removeLocalEventMonitor()

        case .postWillShow:
            NotificationCenter.default.post(name: .panelWillShow, object: nil)

        case .postDidHide:
            NotificationCenter.default.post(name: .panelDidHide, object: nil)

        // NotchState mutations
        case .animateOpen:
            // Next run-loop turn: expand.
            DispatchQueue.main.async { [state] in
                withAnimation(NotchLayout.effectiveOpen) {
                    state.isSaving = false   // reopen from the saved pill: spring from its current width
                    state.isHovering = false // and from the hover swell, if any
                    state.isOpen = true
                }
                withAnimation(NotchLayout.effectiveContentIn) { state.contentVisible = true }
            }

        case .animateClose:
            if state.contentVisible {
                withAnimation(NotchLayout.effectiveContentOut) { state.contentVisible = false }
            }
            withAnimation(NotchLayout.effectiveClose) {
                if state.isOpen { state.isOpen = false }
                if state.isSaving { state.isSaving = false }
            }

        case .animateSaving:
            withAnimation(NotchLayout.contentOutAnimation) { state.contentVisible = false }
            withAnimation(NotchLayout.savingAnimation) {
                state.isOpen = false
                state.isSaving = true
                state.savedBadgeShown = true   // same transaction as the button's removal → the ✓ flies
            }

        case .clearBadgeNoAnimation:
            // Drop the badge and give the ✓ button its geometry back without animating either.
            var noAnimation = Transaction()
            noAnimation.disablesAnimations = true
            withTransaction(noAnimation) { state.savedBadgeShown = false }

        case .setSettled(let settled):
            state.isSettled = settled

        case .swellHover:
            withAnimation(NotchLayout.hoverInAnimation) { state.isHovering = true }

        case .unswellHover:
            withAnimation(NotchLayout.hoverOutAnimation) { state.isHovering = false }

        case .haptic:
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)

        // Timers
        case .scheduleClose:
            closeTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(NotchLayout.closeDuration))
                guard !Task.isCancelled, let self else { return }
                self.closeTask = nil
                let screen = self.targetScreen()
                let hasNotch = screen.map { self.shouldStayParked(on: $0) } ?? false
                self.dispatch(.closeTimerFired(hasNotch: hasNotch), on: screen)
            }

        case .cancelClose:
            closeTask?.cancel()
            closeTask = nil

        case .scheduleSaveHold:
            saveTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(NotchLayout.savedHold))
                guard !Task.isCancelled, let self else { return }
                self.saveTask = nil
                self.dispatch(.saveHoldElapsed, on: nil)
            }

        case .cancelSaveHold:
            saveTask?.cancel()
            saveTask = nil

        case .scheduleSettle(let generation):
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.dispatch(.settleTimerFired(generation: generation), on: nil)
            }

        case .scheduleFocusRetries:
            // SwiftUI's @FocusState can lose the race against the window becoming key,
            // so re-assert keyboard focus on the title field once the content is in.
            for delay in [0.12, 0.30] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    self?.focusTitleFieldIfNeeded()
                }
            }

        case .scheduleHoverDwell:
            // A short dwell so a pointer merely crossing the notch on its way along the menu
            // bar does not swell the shape or tap the trackpad.
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.hoverDwell = nil
                self.dispatch(.hoverDwellElapsed(reduceMotion: NotchLayout.reduceMotion), on: nil)
            }
            hoverDwell = work
            DispatchQueue.main.asyncAfter(deadline: .now() + NotchLayout.hoverDwell, execute: work)

        case .cancelHoverDwell:
            hoverDwell?.cancel()
            hoverDwell = nil

        }
    }

    // MARK: - Focus

    /// Makes the first editable text field in the hosting view the first responder
    /// unless the user is already editing something.
    private func focusTitleFieldIfNeeded() {
        guard machine.isVisible, !state.isSaving, let window, let hostingView else { return }
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

    // MARK: - Window & geometry

    private func ensureWindow(on screen: NSScreen) -> NotchWindow {
        if let window { return window }
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
    /// nil while displays are being reconfigured (the screen list can be transiently empty).
    private func targetScreen() -> NSScreen? {
        if let notched = NSScreen.screens.first(where: { NotchGeometry.notchRect(for: $0) != nil }) {
            return notched
        }
        let loc = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(loc, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }

    private func configureGeometry(for screen: NSScreen) {
        NotchLayout.refreshTextScale()
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

    /// Closed state on a notched display: a small, click-through-free window hugging the notch
    /// (hover-swollen size + margin), ordered in without taking key status.
    /// (Hover arming is decided by the machine from the pointer position.)
    /// A hide dispatched in the same run-loop turn as a show (before the async open block ran)
    /// must not leave the parked window believing it is open.
    private func resetOpenFlagsWithoutAnimation() {
        var noAnim = Transaction(); noAnim.disablesAnimations = true
        withTransaction(noAnim) {
            if state.isOpen { state.isOpen = false }
            if state.contentVisible { state.contentVisible = false }
        }
    }

    private func parkClosed(on screen: NSScreen) {
        resetOpenFlagsWithoutAnimation()
        let window = ensureWindow(on: screen)
        var noAnim = Transaction(); noAnim.disablesAnimations = true
        withTransaction(noAnim) {
            state.canvasSize = state.closedCanvasSize
            if state.isHovering { state.isHovering = false }
        }
        window.setFrame(closedWindowFrame(for: screen), display: false)
        window.makeFirstResponder(nil)
        // The bleed around the notch stays out of screenshots / screen sharing while parked.
        // QR_CAPTURE_PARKED=1 keeps it capturable for development screenshots.
        window.sharingType = Self.captureParked ? .readOnly : .none
        // orderOut + orderFront in one turn hands key status back to the previous key window
        // without a visible flicker.
        window.orderOut(nil)
        window.orderFrontRegardless()
        // Force the initial layout/render pass now, so the very first hover after launch
        // animates instead of waiting for the first ordinary redraw.
        window.contentView?.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        // Accept mouse/tracking events only now: a hover exit synthesised while the window was
        // being ordered would otherwise re-arm the hover the machine just disarmed.
        window.ignoresMouseEvents = false
    }

    /// `QR_CAPTURE_PARKED=1` keeps the parked window capturable (dev screenshots, E2E); read once.
    private static let captureParked = ProcessInfo.processInfo.environment["QR_CAPTURE_PARKED"] == "1"

    private func closedWindowFrame(for screen: NSScreen) -> NSRect {
        let size = state.closedCanvasSize
        let centerX = NotchGeometry.notchRect(for: screen)?.midX ?? screen.frame.midX
        return NSRect(x: centerX - size.width / 2, y: screen.frame.maxY - size.height, width: size.width, height: size.height)
    }

    private func relayout() {
        guard let screen = targetScreen() else { return }
        dispatch(.screenChanged(hasNotch: shouldStayParked(on: screen)), on: screen)
    }

    // MARK: - Global mouse handling

    /// One global monitor for the app's lifetime:
    /// - panel open  → any click outside our window collapses it
    /// - panel closed → a click on the physical notch expands it
    private func installGlobalClickMonitor() {
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            // AppKit delivers monitor blocks on the main thread in practice, but the API does not
            // promise it, so verify before assuming isolation.
            let type = event.type
            let handle: @MainActor () -> Void = {
                guard let self else { return }
                if self.machine.isVisible {
                    self.hide()
                } else if type == .leftMouseDown, self.isOnNotch(NSEvent.mouseLocation) {
                    self.show()
                }
            }
            if Thread.isMainThread {
                MainActor.assumeIsolated { handle() }
            } else {
                DispatchQueue.main.async { handle() }
            }
        }
    }

    /// While open: Esc always collapses (even when a text field owns the key loop),
    /// and a click inside the window but outside the black silhouette collapses too
    /// (the global monitor never sees our own window's events).
    private func installLocalEventMonitor() {
        guard localEventMonitor == nil else { return }
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, self.machine.isVisible, event.window === self.window else { return event }
            if event.type == .keyDown {
                if event.keyCode == 53 { // Esc
                    self.hide()
                    return nil
                }
                // During the saved hold the panel is still key but has no field: swallow quietly.
                if self.state.isSaving { return nil }
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

    private func isOnNotch(_ point: NSPoint, slack: CGFloat = 8) -> Bool {
        for screen in NSScreen.screens {
            if let notch = NotchGeometry.notchRect(for: screen), notch.insetBy(dx: -slack, dy: 0).contains(point) {
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
