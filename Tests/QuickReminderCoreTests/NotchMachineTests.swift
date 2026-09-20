import Testing

@testable import QuickReminderCore

/// The pure panel state machine: phases, guards and effect lists, exercised without a window.
struct NotchMachineTests {

    // MARK: - Helpers

    /// Drives a fresh machine into `phase` through the public events (closed-parked via a
    /// screen change onto a notched display; open via show; saving via save; closing via hide).
    private static func machine(in phase: NotchPhase) -> NotchMachine {
        var m = NotchMachine()
        switch phase {
        case .closed(parked: false):
            break
        case .closed(parked: true):
            _ = m.handle(.screenChanged(hasNotch: true))
        case .open:
            _ = m.handle(.show)
        case .saving:
            _ = m.handle(.show)
            _ = m.handle(.save(reduceMotion: false))
        case .closing:
            _ = m.handle(.show)
            _ = m.handle(.hide)
        }
        #expect(m.phase == phase)
        return m
    }

    private static let allPhases: [NotchPhase] = [.closed(parked: false), .closed(parked: true), .open, .saving, .closing]

    // MARK: - 1. Show from closed

    @Test func showFromClosedOpensTheFullChoreography() {
        var m = NotchMachine()
        let effects = m.handle(.show)
        #expect(m.phase == .open)
        #expect(m.generation == 1)
        for expected: NotchEffect in [
            .switchToOpenCanvas, .setIgnoresMouse(false), .installLocalMonitor,
            .animateOpen(fromSaved: false), .postWillShow, .scheduleSettle(generation: 1), .scheduleFocusRetries,
        ] {
            #expect(effects.contains(expected), "missing \(expected)")
        }
        #expect(!effects.contains(.cancelClose))
        #expect(!effects.contains(.cancelSaveHold))
        // Input is enabled before the window takes key status, the monitor before the view is told.
        let mouse = effects.firstIndex(of: .setIgnoresMouse(false))!
        let key = effects.firstIndex(of: .makeKeyAndOrderFront)!
        let monitor = effects.firstIndex(of: .installLocalMonitor)!
        let willShow = effects.firstIndex(of: .postWillShow)!
        #expect(mouse < key && key < monitor && monitor < willShow)
    }

    @Test func showFromParkedLeavesParkingAndCancelsAPendingDwell() {
        var m = Self.machine(in: .closed(parked: true))
        _ = m.handle(.hoverEntered)
        #expect(m.hoverDwellPending)
        let effects = m.handle(.show)
        #expect(m.phase == .open)
        #expect(!m.hoverDwellPending)
        #expect(effects.first == .cancelHoverDwell)
        #expect(effects.contains(.switchToOpenCanvas))
    }

    @Test func showWhileOpenIsANoOp() {
        var m = Self.machine(in: .open)
        let before = m
        #expect(m.handle(.show).isEmpty)
        #expect(m == before)
    }

    // MARK: - 2. Show from closing (reverse mid-collapse)

    @Test func showFromClosingReversesWithoutSnapping() {
        var m = Self.machine(in: .closing)
        let effects = m.handle(.show)
        #expect(m.phase == .open)
        #expect(effects.contains(.cancelClose))
        #expect(!effects.contains(.switchToOpenCanvas), "the shape reverses from where it is; no canvas reset")
        #expect(effects.contains(.animateOpen(fromSaved: false)))
        #expect(effects.contains(.installLocalMonitor), "the monitor was removed by hide")
    }

    // MARK: - 3. Reopen during the saved hold

    @Test func reopenDuringSavedHoldCancelsTheHoldAndDropsTheBadge() {
        var m = Self.machine(in: .saving)
        #expect(m.badgeShown)
        let effects = m.handle(.show)
        #expect(m.phase == .open)
        #expect(!m.badgeShown)
        #expect(effects.contains(.cancelSaveHold))
        #expect(effects.contains(.clearBadgeNoAnimation))
        #expect(effects.contains(.animateOpen(fromSaved: true)))
        #expect(!effects.contains(.switchToOpenCanvas))
        #expect(!effects.contains(.installLocalMonitor), "the local monitor stays installed during the hold")
        #expect(!effects.contains(.cancelClose))
    }

    @Test func notchTapDuringSavedHoldDoesNothing() {
        var m = Self.machine(in: .saving)
        let before = m
        #expect(m.handle(.notchTapped).isEmpty)
        #expect(m == before)
    }

    @Test func notchTapOnlyActsOnTheParkedNotch() {
        for phase in [NotchPhase.closing, .open, .saving, .closed(parked: false)] {
            var m = Self.machine(in: phase)
            let before = m
            #expect(m.handle(.notchTapped).isEmpty, "tap in \(phase) is ignored")
            #expect(m == before)
        }
        var parked = Self.machine(in: .closed(parked: true))
        #expect(parked.handle(.notchTapped).contains(.animateOpen(fromSaved: false)))
        #expect(parked.phase == .open)
    }

    // MARK: - 4. Full save choreography

    @Test func saveThenHoldThenCloseParksOverANotch() {
        var m = Self.machine(in: .open)
        let save = m.handle(.save(reduceMotion: false))
        #expect(m.phase == .saving)
        #expect(m.badgeShown)
        #expect(save == [.setSettled(false), .animateSaving, .setIgnoresMouse(true), .resignFirstResponder, .scheduleSaveHold])

        let hold = m.handle(.saveHoldElapsed)
        #expect(m.phase == .closing)
        #expect(m.badgeShown, "the badge fades in place; it is only dropped once the window is parked")
        #expect(!hold.contains(.cancelSaveHold), "the hold ran out on its own")
        #expect(hold.contains(.postDidHide) && hold.contains(.removeLocalMonitor) && hold.contains(.resignFirstResponder) && hold.contains(.animateClose) && hold.contains(.scheduleClose))

        let close = m.handle(.closeTimerFired(hasNotch: true))
        #expect(m.phase == .closed(parked: true))
        #expect(!m.badgeShown)
        #expect(close == [.clearBadgeNoAnimation, .park])
    }

    @Test func closeTimerOrdersOutWithoutANotch() {
        var m = Self.machine(in: .saving)
        _ = m.handle(.saveHoldElapsed)
        let close = m.handle(.closeTimerFired(hasNotch: false))
        #expect(m.phase == .closed(parked: false))
        #expect(!m.badgeShown)
        #expect(close == [.clearBadgeNoAnimation, .orderOut])
    }

    @Test func saveWithReduceMotionIsAPlainHide() {
        var m = Self.machine(in: .open)
        let effects = m.handle(.save(reduceMotion: true))
        #expect(m.phase == .closing)
        #expect(!m.badgeShown)
        #expect(!effects.contains(.animateSaving))
        #expect(effects.contains(.animateClose) && effects.contains(.scheduleClose))
    }

    @Test func saveBumpsTheGenerationSoTheSettleTimerCannotDropTheMask() {
        var m = Self.machine(in: .open)
        let settleGeneration = m.generation
        _ = m.handle(.save(reduceMotion: false))
        #expect(m.generation == settleGeneration + 1)
        #expect(m.handle(.settleTimerFired(generation: settleGeneration)).isEmpty)
    }

    @Test func settleTimerOnlyCountsForTheCurrentGeneration() {
        var m = NotchMachine()
        _ = m.handle(.show)
        let first = m.generation
        _ = m.handle(.hide)
        _ = m.handle(.show)
        #expect(m.handle(.settleTimerFired(generation: first)).isEmpty, "stale timer from the first show")
        #expect(m.handle(.settleTimerFired(generation: m.generation)) == [.setSettled(true)])
        _ = m.handle(.hide)
        #expect(m.handle(.settleTimerFired(generation: m.generation)).isEmpty, "not while closing")
    }

    // MARK: - 5. Hover on the parked notch

    @Test func hoverDwellSwellsWithHapticAndUnswellsOnExit() {
        var m = Self.machine(in: .closed(parked: true))
        #expect(m.hoverArmed)
        #expect(m.handle(.hoverEntered) == [.scheduleHoverDwell])
        #expect(m.hoverDwellPending)
        #expect(m.handle(.hoverEntered).isEmpty, "one dwell at a time")
        #expect(m.handle(.hoverDwellElapsed(reduceMotion: false)) == [.swellHover, .haptic])
        #expect(m.hoverSwollen && !m.hoverDwellPending)
        #expect(m.handle(.hoverEntered).isEmpty, "already swollen")
        #expect(m.handle(.hoverExited) == [.unswellHover])
        #expect(!m.hoverSwollen && m.hoverArmed)
    }

    @Test func hoverExitDuringDwellCancelsIt() {
        var m = Self.machine(in: .closed(parked: true))
        _ = m.handle(.hoverEntered)
        #expect(m.handle(.hoverExited) == [.cancelHoverDwell])
        #expect(!m.hoverDwellPending)
        #expect(m.handle(.hoverDwellElapsed(reduceMotion: false)).isEmpty, "a late fire after cancel changes nothing")
        #expect(!m.hoverSwollen)
    }

    @Test func hoverDwellWithReduceMotionOnlyTapsTheTrackpad() {
        var m = Self.machine(in: .closed(parked: true))
        _ = m.handle(.hoverEntered)
        #expect(m.handle(.hoverDwellElapsed(reduceMotion: true)) == [.haptic])
        #expect(!m.hoverSwollen)
        #expect(m.handle(.hoverExited).isEmpty)
    }

    @Test func parkingUnderThePointerDisarmsHoverUntilItLeaves() {
        var m = Self.machine(in: .closing)
        _ = m.handle(.closeTimerFired(hasNotch: true), pointerOnNotch: true)
        #expect(m.phase == .closed(parked: true))
        #expect(!m.hoverArmed)
        #expect(m.handle(.hoverEntered).isEmpty)
        #expect(!m.hoverDwellPending)
        #expect(m.handle(.hoverExited).isEmpty)
        #expect(m.hoverArmed)
        #expect(m.handle(.hoverEntered) == [.scheduleHoverDwell])
    }

    @Test func parkingAwayFromThePointerArmsHoverImmediately() {
        var m = Self.machine(in: .closing)
        _ = m.handle(.closeTimerFired(hasNotch: true), pointerOnNotch: false)
        #expect(m.hoverArmed)
        #expect(m.handle(.hoverEntered) == [.scheduleHoverDwell])
    }

    @Test func hoverIsIgnoredUnlessParked() {
        for phase in Self.allPhases where phase != .closed(parked: true) {
            var m = Self.machine(in: phase)
            let before = m
            #expect(m.handle(.hoverEntered).isEmpty, "\(phase)")
            #expect(m.handle(.hoverExited).isEmpty, "\(phase)")
            #expect(m == before, "\(phase)")
        }
    }

    @Test func screenChangeWhileParkedReparksAndRearmsFromThePointer() {
        var m = Self.machine(in: .closed(parked: true))
        _ = m.handle(.hoverEntered)
        _ = m.handle(.hoverDwellElapsed(reduceMotion: false))
        #expect(m.hoverSwollen)
        #expect(m.handle(.screenChanged(hasNotch: true), pointerOnNotch: true) == [.configureGeometry, .park])
        #expect(m.phase == .closed(parked: true) && !m.hoverSwollen && !m.hoverArmed)
    }

    // MARK: - 6. Guards

    @Test func secondSaveIsSwallowed() {
        var m = Self.machine(in: .open)
        _ = m.handle(.save(reduceMotion: false))
        let before = m
        #expect(m.handle(.save(reduceMotion: false)).isEmpty)
        #expect(m.handle(.save(reduceMotion: true)).isEmpty)
        #expect(m == before)
    }

    @Test func saveIsOnlyPossibleWhileOpen() {
        for phase in Self.allPhases where phase != .open {
            var m = Self.machine(in: phase)
            let before = m
            #expect(m.handle(.save(reduceMotion: false)).isEmpty, "\(phase)")
            #expect(m == before, "\(phase)")
        }
    }

    @Test func hideDuringSavingCancelsTheHold() {
        var m = Self.machine(in: .saving)
        let effects = m.handle(.hide)
        #expect(m.phase == .closing)
        #expect(effects.first == .cancelSaveHold)
        #expect(effects.contains(.animateClose) && effects.contains(.scheduleClose))
    }

    @Test func hideIsANoOpUnlessVisible() {
        for phase: NotchPhase in [.closed(parked: false), .closed(parked: true), .closing] {
            var m = Self.machine(in: phase)
            let before = m
            #expect(m.handle(.hide).isEmpty, "\(phase)")
            #expect(m == before, "\(phase)")
        }
    }

    @Test func staleTimersAreIgnored() {
        var m = Self.machine(in: .open)
        #expect(m.handle(.saveHoldElapsed).isEmpty)
        #expect(m.handle(.closeTimerFired(hasNotch: true)).isEmpty)
        #expect(m.handle(.closeTimerFired(hasNotch: false)).isEmpty)
        #expect(m.phase == .open)
    }

    // MARK: - Screen changes

    @Test func screenChangeRelayoutsTheOpenWindowAndSkipsAClosingOne() {
        var open = Self.machine(in: .open)
        #expect(open.handle(.screenChanged(hasNotch: true)) == [.configureGeometry, .relayoutOpenWindow])
        #expect(open.phase == .open)

        var saving = Self.machine(in: .saving)
        #expect(saving.handle(.screenChanged(hasNotch: false)) == [.configureGeometry, .relayoutOpenWindow])

        var closing = Self.machine(in: .closing)
        #expect(closing.handle(.screenChanged(hasNotch: true)) == [.configureGeometry], "the close timer parks on the then-current screen")
        #expect(closing.phase == .closing)
    }

    @Test func screenChangeParksAndUnparksClosedWindows() {
        var m = NotchMachine()
        #expect(m.handle(.screenChanged(hasNotch: false)) == [.configureGeometry], "nothing to order out")
        #expect(m.handle(.screenChanged(hasNotch: true)) == [.configureGeometry, .park])
        #expect(m.phase == .closed(parked: true))
        #expect(m.handle(.screenChanged(hasNotch: false)) == [.configureGeometry, .orderOut], "the target screen lost its notch")
        #expect(m.phase == .closed(parked: false))
    }

    // MARK: - 7. Exhaustive sequences

    /// The event alphabet explored from a state: every event, every payload, and both pointer
    /// positions where they matter. Settle timers are generated relative to the current
    /// generation (current and stale), so the transition function is independent of its value.
    private static func alphabet(for m: NotchMachine) -> [(event: NotchEvent, pointerOnNotch: Bool)] {
        [
            (.show, false), (.hide, false), (.notchTapped, false),
            (.save(reduceMotion: false), false), (.save(reduceMotion: true), false),
            (.saveHoldElapsed, false),
            (.closeTimerFired(hasNotch: true), false), (.closeTimerFired(hasNotch: true), true), (.closeTimerFired(hasNotch: false), false),
            (.settleTimerFired(generation: m.generation), false), (.settleTimerFired(generation: m.generation &- 1), false),
            (.hoverEntered, false), (.hoverDwellElapsed(reduceMotion: false), false), (.hoverDwellElapsed(reduceMotion: true), false), (.hoverExited, false),
            (.screenChanged(hasNotch: true), false), (.screenChanged(hasNotch: true), true), (.screenChanged(hasNotch: false), false),
        ]
    }

    /// Everything about a machine except the generation counter (which only grows).
    private struct Shape: Hashable {
        let phase: NotchPhase
        let badgeShown, hoverSwollen, hoverArmed, hoverDwellPending: Bool
        init(_ m: NotchMachine) {
            phase = m.phase; badgeShown = m.badgeShown; hoverSwollen = m.hoverSwollen
            hoverArmed = m.hoverArmed; hoverDwellPending = m.hoverDwellPending
        }
    }

    private struct Memo: Hashable {
        let shape: Shape
        let depth: Int
    }

    /// Invariants that must hold for every single transition.
    private static func checkTransition(from before: NotchMachine, event: NotchEvent, pointerOnNotch: Bool, effects: [NotchEffect], to after: NotchMachine) {
        let context = "\(event) (pointerOnNotch: \(pointerOnNotch)) from \(before) → \(after): \(effects)"
        let isVisible = { (p: NotchPhase) in p == .open || p == .saving }
        let isClosedOrClosing = { (p: NotchPhase) -> Bool in
            if case .closed = p { return true }
            return p == .closing
        }
        let hasAnimateOpen = effects.contains { if case .animateOpen = $0 { return true } else { return false } }
        let hasScheduleSettle = effects.contains { if case .scheduleSettle = $0 { return true } else { return false } }

        // Badge lifetime: from the save until the window is parked / ordered out (or reopened).
        #expect(!after.badgeShown || after.phase == .saving || after.phase == .closing, "badge only while saving/closing — \(context)")
        // Mouse input is only re-enabled for the open panel (the parked window manages its own flag inside `park`).
        #expect(!effects.contains(.setIgnoresMouse(false)) || after.phase == .open, "setIgnoresMouse(false) for a non-open phase — \(context)")
        // The local monitor is installed exactly while visible, so install/remove alternate.
        #expect(effects.contains(.installLocalMonitor) == (!isVisible(before.phase) && isVisible(after.phase)), "monitor install — \(context)")
        #expect(effects.contains(.removeLocalMonitor) == (isVisible(before.phase) && !isVisible(after.phase)), "monitor remove — \(context)")
        // Parking / ordering out never happens from an open or saving panel and lands in the matching closed state.
        #expect(!effects.contains(.park) || (isClosedOrClosing(before.phase) && after.phase == .closed(parked: true)), "park — \(context)")
        #expect(!effects.contains(.orderOut) || (isClosedOrClosing(before.phase) && after.phase == .closed(parked: false)), "orderOut — \(context)")
        #expect(!(effects.contains(.park) && effects.contains(.orderOut)), "park and orderOut together — \(context)")
        // The swell only exists on the parked closed silhouette.
        #expect(!after.hoverSwollen || after.phase == .closed(parked: true), "swollen outside parked — \(context)")
        #expect(!effects.contains(.swellHover) || after.hoverSwollen, "swellHover without hoverSwollen — \(context)")
        #expect(!effects.contains(.unswellHover) || (before.hoverSwollen && !after.hoverSwollen), "unswellHover — \(context)")
        // Never open and close in the same breath.
        #expect(!(hasAnimateOpen && effects.contains(.animateClose)), "animateOpen + animateClose — \(context)")
        #expect(!(hasAnimateOpen && effects.contains(.animateSaving)), "animateOpen + animateSaving — \(context)")
        // Animations and timers match the phase they lead to.
        #expect(hasAnimateOpen == (after.phase == .open && before.phase != .open), "animateOpen ⇔ became open — \(context)")
        #expect(hasScheduleSettle == hasAnimateOpen, "settle timer accompanies every open — \(context)")
        #expect(effects.contains(.scheduleClose) == (after.phase == .closing && before.phase != .closing), "scheduleClose ⇔ became closing — \(context)")
        #expect(effects.contains(.animateClose) == effects.contains(.scheduleClose), "animateClose ⇔ scheduleClose — \(context)")
        #expect(effects.contains(.scheduleSaveHold) == (after.phase == .saving && before.phase != .saving), "scheduleSaveHold ⇔ became saving — \(context)")
        #expect(effects.contains(.animateSaving) == (effects.contains(.scheduleSaveHold)), "animateSaving ⇔ scheduleSaveHold — \(context)")
        #expect(!effects.contains(.animateSaving) || after.badgeShown, "saving shows the badge — \(context)")
        #expect(!effects.contains(.cancelClose) || before.phase == .closing, "cancelClose only while closing — \(context)")
        #expect(!effects.contains(.cancelSaveHold) || before.phase == .saving, "cancelSaveHold only while saving — \(context)")
        // Hover dwell bookkeeping.
        #expect(effects.contains(.scheduleHoverDwell) == (!before.hoverDwellPending && after.hoverDwellPending), "scheduleHoverDwell — \(context)")
        #expect(!effects.contains(.scheduleHoverDwell) || after.phase == .closed(parked: true), "dwell only while parked — \(context)")
        #expect(!effects.contains(.cancelHoverDwell) || (before.hoverDwellPending && !after.hoverDwellPending), "cancelHoverDwell — \(context)")
        #expect(!effects.contains(.haptic) || (before.hoverDwellPending && !after.hoverDwellPending && before.hoverArmed), "haptic only when an armed dwell elapses — \(context)")
        #expect(!effects.contains(.swellHover) || effects.contains(.haptic), "swell always comes with the haptic — \(context)")
        // The generation never goes backwards and only moves on show / save.
        #expect(after.generation >= before.generation, "generation — \(context)")
        #expect((after.generation != before.generation) == (hasAnimateOpen || effects.contains(.animateSaving)), "generation bump ⇔ show/save — \(context)")
        // Each effect at most once per transition.
        #expect(Set(effects).count == effects.count, "duplicate effect — \(context)")
        // Leaving the parked state or reopening must never leave a swell behind.
        #expect(!(before.hoverSwollen && after.phase != .closed(parked: true)) || !after.hoverSwollen, "swell survived leaving parked — \(context)")
    }

    /// Explores every event sequence of length ≤ `depth` from `start`, memoised on the
    /// machine's shape (the transition function does not depend on the generation counter,
    /// see `alphabet(for:)`). Returns the number of distinct sequences covered.
    private static func explore(from start: NotchMachine, depth: Int, memo: inout [Memo: Int], shapes: inout Set<Shape>) -> Int {
        shapes.insert(Shape(start))
        guard depth > 0 else { return 0 }
        let key = Memo(shape: Shape(start), depth: depth)
        if let cached = memo[key] { return cached }
        var count = 0
        for (event, pointerOnNotch) in alphabet(for: start) {
            var next = start
            let effects = next.handle(event, pointerOnNotch: pointerOnNotch)
            checkTransition(from: start, event: event, pointerOnNotch: pointerOnNotch, effects: effects, to: next)
            count += 1 + explore(from: next, depth: depth - 1, memo: &memo, shapes: &shapes)
        }
        memo[key] = count
        return count
    }

    @Test func everySequenceUpToLengthFiveKeepsTheInvariants() {
        let depth = 5
        var memo: [Memo: Int] = [:]
        var shapes = Set<Shape>()
        var sequences = 0
        for phase in Self.allPhases {
            sequences += Self.explore(from: Self.machine(in: phase), depth: depth, memo: &memo, shapes: &shapes)
        }
        // 5 starting phases × Σ_{k=1..5} 18^k distinct sequences.
        let alphabetSize = Self.alphabet(for: NotchMachine()).count
        var perStart = 0, power = 1
        for _ in 1...depth { power *= alphabetSize; perStart += power }
        #expect(alphabetSize == 18)
        #expect(sequences == Self.allPhases.count * perStart)
        // The reachable state space is tiny (5 phases × 4 flags ≤ 80 shapes) and always includes every phase.
        #expect(shapes.count == 17, "a new flag or phase changes the reachable state space — update this on purpose")
        for phase in Self.allPhases {
            #expect(shapes.contains { $0.phase == phase }, "\(phase) reachable")
        }
    }

    @Test func handleIsDeterministicAndValueSemantic() {
        let m = Self.machine(in: .saving)
        var a = m, b = m
        #expect(a.handle(.show) == b.handle(.show))
        #expect(a == b)
        #expect(m.phase == .saving, "the original is untouched")
    }
}
