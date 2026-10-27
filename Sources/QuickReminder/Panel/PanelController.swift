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
        // Pointer monitors see nothing while a menu tracks (PopUpMenu / NSMenu) or a popover is up;
        // re-check the pass-through when they end, before the next unmoved click.
        for name in [NSMenu.didEndTrackingNotification, NSPopover.didCloseNotification] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.updatePointerPassThrough() }
            }
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

    /// In-notch Set Date (Settings → Date picker style → In notch): grow the open blob for the
    /// scheduling controls / the month grid, or settle back to the plain panel.
    func setSection(_ expansion: NotchSection) {
        dispatch(.sectionChanged(expansion), on: targetScreen())
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
            // The style is read once per open: the canvas is sized for it and stays that size until
            // the panel closes (Set Date never resizes the window).
            openStyle = SetDateStyle.current
            withTransaction(noAnim) {
                state.canvasSize = openCanvasSize
                if state.section != .none { state.section = .none }   // every open starts plain
            }
            window.setFrame(windowFrame(for: screen), display: false)
            if state.isOpen { state.isOpen = false }
            if state.contentVisible { state.contentVisible = false }

        case .relayoutOpenWindow:
            guard let screen else { return }
            var noAnim = Transaction(); noAnim.disablesAnimations = true
            withTransaction(noAnim) { state.canvasSize = openCanvasSize }
            window?.setFrame(windowFrame(for: screen), display: true)
            // The shape moved under a pointer that may not move again before the next click.
            updatePointerPassThrough()

        case .makeKeyAndOrderFront:
            guard let screen else { return }
            let window = ensureWindow(on: screen)
            window.sharingType = .readOnly   // the open panel may appear in screenshots / sharing
            window.makeKeyAndOrderFront(nil)
            // Key first, then let the transparent canvas pass the mouse through: a window that
            // already ignores the mouse when it is made key could miss the keyboard (keystrokes
            // then reached the app below in an E2E run).
            updatePointerPassThrough()

        case .park:
            if let screen { parkClosed(on: screen) }

        case .orderOut:
            resetOpenFlagsWithoutAnimation()
            window?.ignoresMouseEvents = true
            window?.orderOut(nil)

        case .setIgnoresMouse(let ignores):
            // During the collapse / saved hold no input is needed; clicks reach what is below.
            window?.ignoresMouseEvents = ignores
            // The open pass-through is decided only after the window is key (.makeKeyAndOrderFront).

        case .resignFirstResponder:
            window?.makeFirstResponder(nil)

        // Monitors & notifications
        case .installLocalMonitor:
            installLocalEventMonitor()
            installPointerTracking()

        case .removeLocalMonitor:
            removeLocalEventMonitor()
            removePointerTracking()

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
                if state.section != .none { state.section = .none }
            }

        case .animateSaving:
            withAnimation(NotchLayout.contentOutAnimation) { state.contentVisible = false }
            withAnimation(NotchLayout.savingAnimation) {
                state.isOpen = false
                state.isSaving = true
                state.section = .none
                state.savedBadgeShown = true   // same transaction as the button's removal → the ✓ flies
            }

        case .clearBadgeNoAnimation:
            // Drop the badge and give the ✓ button its geometry back without animating either.
            var noAnimation = Transaction()
            noAnimation.disablesAnimations = true
            withTransaction(noAnimation) { state.savedBadgeShown = false }

        case .setSettled(let settled):
            state.isSettled = settled
            if settled { updatePointerPassThrough() }

        case .swellHover:
            withAnimation(NotchLayout.hoverInAnimation) { state.isHovering = true }

        case .unswellHover:
            withAnimation(NotchLayout.hoverOutAnimation) { state.isHovering = false }

        case .haptic:
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)

        case .animateSection(let expansion):
            withAnimation(NotchLayout.effectiveSection) { state.section = expansion }
            // The blob is about to grow / shrink under a resting pointer: decide from its target.
            updatePointerPassThrough()

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

    /// Set by the root view while one of its popovers is shown (see the Esc handling).
    var popoverIsOpen = false

    // MARK: - Focus

    /// A popover (Set Date, location) closed: the panel takes the keyboard back, and the title
    /// field gets it unless a text row still owns it.
    func restoreKeyFocus() {
        guard machine.isVisible, !state.isSaving, let window else { return }
        makeKeyKeepingPassThrough(window)
        focusTitleFieldIfNeeded()
    }

    /// Makes the first editable text field in the hosting view the first responder
    /// unless the user is already editing something.
    private func focusTitleFieldIfNeeded() {
        guard machine.isVisible, !state.isSaving, let window, let hostingView else { return }
        // In-notch Set Date owns the keyboard while it is shown (its fields, the grid); the
        // open-time retries must not pull it back to the title (⌘D right after the hotkey).
        if state.section != .none { return }
        // The title / notes rows are real text views. A field editor belongs to a SwiftUI
        // TextField (the in-notch Set Date fields) that may just have left the hierarchy and
        // still holds first responder, so it does not count as "the user is editing".
        if let editing = window.firstResponder as? NSTextView, !editing.isFieldEditor { return }
        makeKeyKeepingPassThrough(window)
        if let field = Self.titleTextView(in: hostingView) {
            window.makeFirstResponder(field)
        }
    }

    private static func titleTextView(in view: NSView) -> NSTextView? {
        for sub in view.subviews {
            if let tv = sub as? NSTextView, tv.accessibilityIdentifier() == "title" { return tv }
            if let found = titleTextView(in: sub) { return found }
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
        // The open body is the notch band actually on this display plus the content rhythm.
        let band = state.closedSize.height
        let open = NotchLayout.openSize(notchBandHeight: band)
        if state.openSize != open { state.openSize = open }
        // The grown states stop short of the Dock / screen bottom; the section scrolls instead.
        let maxHeight = NotchLayout.maxPanelHeight(screenFrame: screen.frame, visibleFrame: screen.visibleFrame)
        let section = NotchLayout.openSize(notchBandHeight: band, section: .controls, maxHeight: maxHeight)
        if state.scheduleSize != section { state.scheduleSize = section }
        let calendar = NotchLayout.openSize(notchBandHeight: band, section: .calendar, maxHeight: maxHeight)
        if state.scheduleCalendarSize != calendar { state.scheduleCalendarSize = calendar }
        let location = NotchLayout.openSize(notchBandHeight: band, section: .location, maxHeight: maxHeight)
        if state.locationSize != location { state.locationSize = location }
    }

    /// Publishing unchanged values would re-render the whole panel for nothing.
    private func setClosedSize(_ size: CGSize) {
        if state.closedSize != size { state.closedSize = size }
    }

    /// Set Date style as of the current open (see `.switchToOpenCanvas`).
    private var openStyle: SetDateStyle = .defaultStyle

    /// The open canvas, constant from open to close (`NotchLayout.openCanvasSize`).
    private var openCanvasSize: CGSize {
        NotchLayout.openCanvasSize(openSize: state.openSize, tallestSectionSize: state.tallestSectionSize,
                                   style: openStyle)
    }

    /// Window covers the fully-open panel, anchored to the top edge, centred on the notch.
    private func windowFrame(for screen: NSScreen) -> NSRect {
        let size = openCanvasSize
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
                    // A popover of this non-activating panel never becomes the key window: its keys
                    // arrive here with `event.window` = the panel. So the first Esc closes only the
                    // popover (cancel, nothing written) and a second Esc closes the panel.
                    if self.popoverIsOpen {
                        NotificationCenter.default.post(name: .panelDismissPopovers, object: nil)
                        return nil
                    }
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
                // In-notch Set Date: a click on the header / title / notes cancels scheduling (like a
                // click outside the popover) and still lands where it was aimed.
                let topDown = hosting.isFlipped ? point.y : hosting.bounds.maxY - point.y
                if event.type == .leftMouseDown,
                   NotchLayout.clickCancelsSection(atY: topDown, notchBandHeight: self.state.notchBandHeight,
                                                    textScale: NotchLayout.cachedTextScale, section: self.state.section) {
                    NotificationCenter.default.post(name: .panelCancelSection, object: nil)
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

    /// Re-asserts key status (focus retries, a popover closing) with the mouse briefly taken back,
    /// for the same reason as on open, then restores the pass-through.
    private func makeKeyKeepingPassThrough(_ window: NSWindow) {
        if window.ignoresMouseEvents { window.ignoresMouseEvents = false }
        window.makeKey()
        updatePointerPassThrough()
    }

    // MARK: - Pointer pass-through (open panel)

    /// While open, the window is the full (in notch style tall) canvas but only the black shape
    /// should take the mouse. Pointer moves over our window arrive at the local monitor, moves
    /// anywhere else (including our transparent area while it ignores the mouse) at the global one;
    /// either way `ignoresMouseEvents` follows the pointer, so a click below the panel reaches the
    /// app there and the global click monitor closes the panel, as for any click outside.
    private var pointerMonitors: [Any] = []

    private func installPointerTracking() {
        guard pointerMonitors.isEmpty else { return }
        // Mouse-ups too: a drag out of the shape keeps the window until release (see below).
        let events: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .leftMouseUp, .rightMouseUp]
        if let local = NSEvent.addLocalMonitorForEvents(matching: events, handler: { [weak self] event in
            self?.updatePointerPassThrough()
            return event
        }) { pointerMonitors.append(local) }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: events, handler: { [weak self] _ in
            if Thread.isMainThread {
                MainActor.assumeIsolated { self?.updatePointerPassThrough() }
            } else {
                DispatchQueue.main.async { self?.updatePointerPassThrough() }
            }
        }) { pointerMonitors.append(global) }
    }

    private func removePointerTracking() {
        pointerMonitors.forEach(NSEvent.removeMonitor)
        pointerMonitors.removeAll()
    }

    /// Open phase only: the collapse / saved hold set `ignoresMouseEvents` themselves, and the
    /// parked window takes the mouse for hover and click on the notch.
    private func updatePointerPassThrough() {
        guard machine.phase == .open, let window else { return }
        let frame = window.frame
        let point = NotchLayout.canvasPoint(mouse: NSEvent.mouseLocation, windowFrame: frame)
        let ignores = NotchLayout.passesMouseThrough(point, canvasWidth: frame.width, panelSize: state.panelSize)
        guard window.ignoresMouseEvents != ignores else { return }
        // Never drop the window mid-press (a drag that started on a control and left the shape);
        // the mouse-up event re-evaluates.
        if ignores && NSEvent.pressedMouseButtons != 0 { return }
        window.ignoresMouseEvents = ignores
        // Leaving the shape this way may not deliver a hover exit to the control under the edge;
        // never leave its pointing-hand cursor behind over the app below.
        if ignores { NSCursor.arrow.set() }
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
    /// Esc while a popover (list picker, Set Date, location) is shown: close it, keep the panel.
    static let panelDismissPopovers = Notification.Name("PanelDismissPopovers")
    /// A click on the panel above the in-notch Set Date section: cancel it (nothing written).
    static let panelCancelSection = Notification.Name("PanelCancelSchedule")
    /// ↩ / ⌘↩ in the title or notes while the in-notch section is open: Set, not save.
    static let sectionCommitRequested = Notification.Name("ScheduleCommitRequested")
    /// ✓ while the in-notch section is open: it decides (Set first or not), then the reminder saves.
    static let sectionSaveRequested = Notification.Name("ScheduleSaveRequested")
}
