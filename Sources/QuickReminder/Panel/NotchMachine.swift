/// Pure state machine behind `PanelController`.
///
/// The machine owns every decision about *what* happens (guards, phase changes, which timers
/// to start or cancel); the controller owns *how* it happens (AppKit windows, SwiftUI
/// animations, monitors). `handle(_:pointerOnNotch:)` mutates the machine and returns the
/// effects to perform, in order. No Foundation, no AppKit, no clocks: everything time-based
/// arrives as an event (`closeTimerFired`, `saveHoldElapsed`, ...), so the whole choreography
/// can be exercised in tests without a window.

/// Where the panel is in its lifecycle.
enum NotchPhase: Hashable, Sendable {
    /// Collapsed to the notch silhouette. `parked` = the small closed window is ordered in
    /// over a physical notch (hover + click work); otherwise the window is ordered out.
    case closed(parked: Bool)
    /// Expanded, key, accepting input.
    case open
    /// "Saved" pill: collapsed to notch height but wider, badge shown, waiting out the hold.
    case saving
    /// Close spring running; the window stays ordered in until `closeTimerFired`.
    case closing
}

/// How far the open panel is grown for the in-notch Set Date variant (Settings → Date picker
/// style → In notch): not at all, the scheduling controls, or the controls plus the month grid.
enum ScheduleExpansion: Hashable, Sendable {
    case none
    case controls
    case calendar

    /// Esc steps back one level: the month grid closes first (the blob shrinks to the controls),
    /// the next Esc closes the section; the panel stays open either way.
    var afterEscape: ScheduleExpansion {
        switch self {
        case .calendar: return .controls
        case .controls, .none: return .none
        }
    }
}

/// Inputs: public API calls, pointer events and expired timers.
enum NotchEvent: Hashable, Sendable {
    /// `show()` — hotkey, menu bar, URL scheme, click on the physical notch.
    case show
    /// `hide()` — Esc, click outside, ⓧ, hotkey while open.
    case hide
    /// `collapseAfterSave()`; with Reduce Motion the saved choreography is a plain hide.
    case save(reduceMotion: Bool)
    /// The 1.0 s "saved" hold is over.
    case saveHoldElapsed
    /// The close spring has settled; the window can be parked or ordered out.
    case closeTimerFired(hasNotch: Bool)
    /// The open spring has settled (0.5 s after `show`); stale generations are dropped.
    case settleTimerFired(generation: UInt)
    /// Pointer entered / left the closed silhouette (SwiftUI `onHover`).
    case hoverEntered
    case hoverExited
    /// The 90 ms hover dwell is over; with Reduce Motion only the haptic fires.
    case hoverDwellElapsed(reduceMotion: Bool)
    /// Display configuration changed; `hasNotch` = the target screen has a physical notch.
    case screenChanged(hasNotch: Bool)
    /// Mouse-down on the closed silhouette (never reopens the saved pill).
    case notchTapped
    /// The in-notch Set Date section opened, closed or toggled its calendar (only while open).
    case scheduleChanged(ScheduleExpansion)
}

/// Outputs, performed by the controller in the order given.
enum NotchEffect: Hashable, Sendable {
    // Window & geometry
    /// Publish the closed / open silhouette sizes for the target screen.
    case configureGeometry
    /// Grow the window + canvas to the full open size without animation, start collapsed.
    case switchToOpenCanvas
    /// Re-anchor the open window on the (possibly new) target screen.
    case relayoutOpenWindow
    /// Allow capture again and take key status.
    case makeKeyAndOrderFront
    /// Closed over a physical notch: small window, no capture, key handed back, initial render forced.
    case park
    /// No physical notch: the window leaves the screen (and ignores the mouse while out).
    case orderOut
    case setIgnoresMouse(Bool)
    /// Drop the field editor so nothing can save again.
    case resignFirstResponder

    // Monitors & notifications
    case installLocalMonitor
    case removeLocalMonitor
    case postWillShow
    case postDidHide

    // NotchState mutations (each performed inside the same animation / transaction as before)
    case animateOpen(fromSaved: Bool)
    case animateClose
    case animateSaving
    case clearBadgeNoAnimation
    case setSettled(Bool)
    case swellHover
    case unswellHover
    case haptic
    /// Spring the open blob to the given schedule height. The window never resizes for this: in
    /// notch style the open canvas is already sized for the tallest schedule state
    /// (`NotchLayout.openCanvasSize`), so only SwiftUI state animates and nothing above moves.
    case animateSchedule(ScheduleExpansion)

    // Timers
    case scheduleClose
    case cancelClose
    case scheduleSaveHold
    case cancelSaveHold
    case scheduleSettle(generation: UInt)
    case scheduleFocusRetries
    case scheduleHoverDwell
    case cancelHoverDwell
}

struct NotchMachine: Hashable, Sendable {
    private(set) var phase: NotchPhase = .closed(parked: false)
    /// The ✓ badge exists (and the save button yields its geometry) from the save until the
    /// window is parked / ordered out or the panel is reopened.
    private(set) var badgeShown = false
    /// The closed silhouette is swollen under the pointer.
    private(set) var hoverSwollen = false
    /// Re-armed once the pointer has left the notch; prevents an immediate re-hover after closing.
    private(set) var hoverArmed = true
    /// A hover dwell timer is running.
    private(set) var hoverDwellPending = false
    /// Bumped by every `show`, `save` and schedule change; a settle timer only counts if it
    /// carries the current value.
    private(set) var generation: UInt = 0
    /// In-notch Set Date height of the open panel.
    private(set) var schedule: ScheduleExpansion = .none

    /// Open or saving: the window is key and the local monitor is installed.
    var isVisible: Bool { phase == .open || phase == .saving }

    /// - Parameter pointerOnNotch: whether the pointer currently rests on the physical notch
    ///   (with hover slack). Only consulted when the machine parks: hover then arms from where
    ///   the pointer actually is (still on the notch → wait for it to leave first).
    mutating func handle(_ event: NotchEvent, pointerOnNotch: Bool = false) -> [NotchEffect] {
        switch event {
        case .show:
            return show()

        case .notchTapped:
            // Only the parked notch takes taps: while open/saving/closing the window either ignores
            // the mouse or the click belongs to the panel's own controls (mid-close reopen comes
            // from the hotkey / global monitor paths, not from a tap).
            guard phase == .closed(parked: true) else { return [] }
            return show()

        case .hide:
            return isVisible ? close(cancellingHold: true) : []

        case .save(let reduceMotion):
            guard phase == .open else { return [] }   // double-save guard; nothing to save while closing
            if reduceMotion { return close(cancellingHold: true) }
            // Invalidate the settle timer from `show` so it cannot drop the mask mid-choreography.
            generation &+= 1
            phase = .saving
            badgeShown = true
            schedule = .none   // the saved pill starts from whatever height the blob had
            return [.setSettled(false), .animateSaving, .setIgnoresMouse(true), .resignFirstResponder, .scheduleSaveHold]

        case .saveHoldElapsed:
            guard phase == .saving else { return [] }
            return close(cancellingHold: false)

        case .closeTimerFired(let hasNotch):
            guard phase == .closing else { return [] }
            badgeShown = false
            return [.clearBadgeNoAnimation, hasNotch ? park(pointerOnNotch: pointerOnNotch) : orderOut()]

        case .settleTimerFired(let generation):
            guard phase == .open, generation == self.generation else { return [] }
            return [.setSettled(true)]

        case .scheduleChanged(let expansion):
            guard phase == .open, expansion != schedule else { return [] }
            return changeSchedule(to: expansion)

        case .hoverEntered:
            guard phase == .closed(parked: true), hoverArmed, !hoverSwollen, !hoverDwellPending else { return [] }
            hoverDwellPending = true
            return [.scheduleHoverDwell]

        case .hoverDwellElapsed(let reduceMotion):
            guard hoverDwellPending else { return [] }   // stale timer (cancelled dwell)
            hoverDwellPending = false
            guard phase == .closed(parked: true), hoverArmed else { return [] }
            var effects: [NotchEffect] = []
            if !reduceMotion {
                hoverSwollen = true
                effects.append(.swellHover)
            }
            effects.append(.haptic)
            return effects

        case .hoverExited:
            guard phase == .closed(parked: true) else { return [] }
            var effects: [NotchEffect] = []
            if hoverDwellPending {
                hoverDwellPending = false
                effects.append(.cancelHoverDwell)
            }
            hoverArmed = true
            if hoverSwollen {
                hoverSwollen = false
                effects.append(.unswellHover)
            }
            return effects

        case .screenChanged(let hasNotch):
            var effects: [NotchEffect] = [.configureGeometry]
            switch phase {
            case .open, .saving:
                effects.append(.relayoutOpenWindow)
            case .closing:
                break   // the close timer parks / orders out on the then-current screen
            case .closed(let parked):
                if hasNotch {
                    effects.append(park(pointerOnNotch: pointerOnNotch))
                } else if parked {
                    effects.append(orderOut())   // the target screen lost its notch
                }
            }
            return effects
        }
    }

    // MARK: - Transitions shared by several events

    private mutating func changeSchedule(to expansion: ScheduleExpansion) -> [NotchEffect] {
        schedule = expansion
        generation &+= 1
        // The content mask goes back on while the blob springs: the section is laid out at its
        // final height at once and must never show outside the black.
        return [.setSettled(false), .animateSchedule(expansion), .scheduleSettle(generation: generation)]
    }

    private mutating func show() -> [NotchEffect] {
        // Already open: nothing to do — except that a show (hotkey menu item, URL scheme, a
        // Raycast / Spotlight reopen) while Set Date is open in the notch returns to the plain
        // panel, through the same transition as Cancel, so NotchState and the view follow.
        guard phase != .open else {
            return schedule == .none ? [] : changeSchedule(to: .none)
        }
        var effects: [NotchEffect] = []
        if hoverDwellPending {
            hoverDwellPending = false
            effects.append(.cancelHoverDwell)
        }
        // Re-opening while the collapse animation is still running (or during the saved hold):
        // don't snap back to the notch, just reverse from wherever the shape currently is.
        let wasVisible = isVisible
        let fromSaved = phase == .saving
        let midCollapse: Bool
        switch phase {
        case .closing:
            effects.append(.cancelClose)
            midCollapse = true
        case .saving:
            effects.append(.cancelSaveHold)
            midCollapse = true
        case .closed, .open:
            midCollapse = false
        }
        // The badge (if any) is invisible or about to be; drop it without animating.
        badgeShown = false
        effects.append(.clearBadgeNoAnimation)
        effects.append(.configureGeometry)
        if !midCollapse { effects.append(.switchToOpenCanvas) }
        schedule = .none
        effects.append(.setIgnoresMouse(false))
        effects.append(.makeKeyAndOrderFront)
        if !wasVisible { effects.append(.installLocalMonitor) }   // still installed during the saved hold
        effects.append(.postWillShow)
        effects.append(.animateOpen(fromSaved: fromSaved))
        hoverSwollen = false   // the open spring also starts from the hover swell, if any
        phase = .open
        generation &+= 1
        effects.append(.scheduleSettle(generation: generation))
        effects.append(.scheduleFocusRetries)
        return effects
    }

    /// Open / saving → closing. `cancellingHold` is false when the hold itself ran out.
    private mutating func close(cancellingHold: Bool) -> [NotchEffect] {
        var effects: [NotchEffect] = []
        if phase == .saving && cancellingHold { effects.append(.cancelSaveHold) }
        phase = .closing
        schedule = .none   // the blob collapses from its current height; the section is gone
        // resignFirstResponder: the panel stays key for the 0.36 s collapse; without it a Return
        // typed right after Esc would still reach the text view and save the dismissed draft.
        effects += [.postDidHide, .removeLocalMonitor, .resignFirstResponder, .setIgnoresMouse(true), .setSettled(false), .animateClose, .scheduleClose]
        return effects
    }

    private mutating func park(pointerOnNotch: Bool) -> NotchEffect {
        phase = .closed(parked: true)
        hoverSwollen = false   // parking resets the swell without animation
        // Hover arms from where the pointer actually is: still on the notch → wait for it to
        // leave first; anywhere else → the next entry swells immediately.
        hoverArmed = !pointerOnNotch
        return .park
    }

    private mutating func orderOut() -> NotchEffect {
        phase = .closed(parked: false)
        hoverSwollen = false   // nothing is on screen; the next park / open resets the swell anyway
        return .orderOut
    }
}
