import Testing

@testable import QuickReminderCore

/// The in-notch Set Date variant: the open blob grows for the schedule controls / the month grid
/// and settles back. No effect ever touches the window during a schedule change: the open canvas
/// is already sized for the tallest state at open (`NotchLayout.openCanvasSize`).
struct NotchMachineScheduleTests {

    private static func openMachine() -> NotchMachine {
        var m = NotchMachine()
        _ = m.handle(.show)
        return m
    }

    /// Only SwiftUI state springs: no window / canvas effect, so nothing above the bar can shift.
    @Test func openingTheScheduleOnlyAnimatesUnderTheMask() {
        var m = Self.openMachine()
        let before = m.generation
        let effects = m.handle(.scheduleChanged(.controls))
        #expect(m.schedule == .controls)
        #expect(m.generation == before + 1)
        #expect(effects == [.setSettled(false), .animateSchedule(.controls), .scheduleSettle(generation: before + 1)])
    }

    /// Every schedule step, there and back, is the same three effects — none of them geometry.
    @Test func noScheduleStepTouchesTheWindow() {
        var m = Self.openMachine()
        let windowEffects: [NotchEffect] = [.configureGeometry, .switchToOpenCanvas, .relayoutOpenWindow, .park, .orderOut]
        for step: ScheduleExpansion in [.controls, .calendar, .controls, .none, .calendar, .none] {
            let effects = m.handle(.scheduleChanged(step))
            #expect(effects == [.setSettled(false), .animateSchedule(step), .scheduleSettle(generation: m.generation)], "\(step)")
            #expect(!effects.contains(where: windowEffects.contains))
            #expect(m.handle(.settleTimerFired(generation: m.generation)) == [.setSettled(true)])
        }
    }

    @Test func calendarToggleOnlyAnimatesTheCanvasIsAlreadyTallEnough() {
        var m = Self.openMachine()
        _ = m.handle(.scheduleChanged(.controls))
        let effects = m.handle(.scheduleChanged(.calendar))
        #expect(m.schedule == .calendar)
        #expect(effects == [.setSettled(false), .animateSchedule(.calendar), .scheduleSettle(generation: m.generation)])
    }

    /// A show while Set Date is open in the notch (URL scheme, menu item, Raycast / Spotlight
    /// reopen) returns to the plain panel through the Cancel transition, so NotchState follows.
    @Test func showWhileScheduledResetsTheSchedule() {
        var m = Self.openMachine()
        _ = m.handle(.scheduleChanged(.calendar))
        let effects = m.handle(.show)
        #expect(m.phase == .open)
        #expect(m.schedule == .none)
        #expect(effects == [.setSettled(false), .animateSchedule(.none), .scheduleSettle(generation: m.generation)])
        #expect(m.handle(.settleTimerFired(generation: m.generation)) == [.setSettled(true)])
        // Plain and open: a further show is still a no-op.
        #expect(m.handle(.show).isEmpty)
        // And the section can be opened again afterwards (the machine is not stuck).
        #expect(m.handle(.scheduleChanged(.controls)).contains(.animateSchedule(.controls)))
    }

    @Test func sameExpansionTwiceIsANoOp() {
        var m = Self.openMachine()
        _ = m.handle(.scheduleChanged(.controls))
        let generation = m.generation
        #expect(m.handle(.scheduleChanged(.controls)).isEmpty)
        #expect(m.generation == generation)
        var plain = Self.openMachine()
        #expect(plain.handle(.scheduleChanged(.none)).isEmpty, "closing a schedule that is not open")
    }

    @Test(arguments: [NotchEvent.hide, .save(reduceMotion: false)])
    func ignoredUnlessOpen(_ leaving: NotchEvent) {
        var m = Self.openMachine()
        _ = m.handle(leaving)
        #expect(m.handle(.scheduleChanged(.controls)).isEmpty)
        #expect(m.schedule == .none)
        var closed = NotchMachine()
        #expect(closed.handle(.scheduleChanged(.calendar)).isEmpty)
    }

    /// Set / Cancel / Esc: the blob springs back under the mask, which drops once it settles.
    @Test func closingSettlesUnderTheMask() {
        var m = Self.openMachine()
        _ = m.handle(.scheduleChanged(.calendar))
        let effects = m.handle(.scheduleChanged(.none))
        #expect(effects == [.setSettled(false), .animateSchedule(.none), .scheduleSettle(generation: m.generation)])
        #expect(m.handle(.settleTimerFired(generation: m.generation)) == [.setSettled(true)])
    }

    @Test func staleSettleFromBeforeTheScheduleChangeIsDropped() {
        var m = Self.openMachine()
        let openGeneration = m.generation
        _ = m.handle(.scheduleChanged(.controls))
        #expect(m.handle(.settleTimerFired(generation: openGeneration)).isEmpty,
                "the open settle must not drop the mask mid-growth")
    }

    @Test func hideAndSaveResetTheSchedule() {
        var m = Self.openMachine()
        _ = m.handle(.scheduleChanged(.calendar))
        _ = m.handle(.hide)
        #expect(m.schedule == .none)

        var s = Self.openMachine()
        _ = s.handle(.scheduleChanged(.controls))
        _ = s.handle(.save(reduceMotion: false))
        #expect(s.schedule == .none)
    }

    /// After parking, a reopen switches to a fresh open canvas exactly once and starts plain.
    @Test func reopenAfterParkingSwitchesCanvasOnceAndStartsPlain() {
        var m = NotchMachine()
        _ = m.handle(.screenChanged(hasNotch: true))
        let firstOpen = m.handle(.show)
        #expect(firstOpen.filter { $0 == .switchToOpenCanvas }.count == 1)
        _ = m.handle(.scheduleChanged(.controls))
        _ = m.handle(.hide)
        _ = m.handle(.closeTimerFired(hasNotch: true))
        #expect(m.phase == .closed(parked: true))
        let reopen = m.handle(.show)
        #expect(reopen.filter { $0 == .switchToOpenCanvas }.count == 1)
        #expect(!reopen.contains(where: { if case .animateSchedule = $0 { return true } else { return false } }),
                "the plain start is set without animation inside switchToOpenCanvas")
        #expect(m.schedule == .none)
    }

    /// Reopening mid-collapse keeps the open window as it is (same size, no switch).
    @Test func reopenMidCollapseKeepsTheWindow() {
        var m = Self.openMachine()
        _ = m.handle(.scheduleChanged(.controls))
        _ = m.handle(.hide)
        let effects = m.handle(.show)
        #expect(!effects.contains(.switchToOpenCanvas))
        #expect(m.schedule == .none)
        #expect(m.handle(.settleTimerFired(generation: m.generation)) == [.setSettled(true)])
    }

    @Test func screenChangeWhileScheduledRelayoutsTheOpenWindow() {
        var m = Self.openMachine()
        _ = m.handle(.scheduleChanged(.calendar))
        let effects = m.handle(.screenChanged(hasNotch: true))
        #expect(effects == [.configureGeometry, .relayoutOpenWindow])
        #expect(m.schedule == .calendar)
    }

    /// Esc steps back one level; the panel itself is never closed by these steps.
    @Test func escapeStepsBackOneLevel() {
        #expect(ScheduleExpansion.calendar.afterEscape == .controls)
        #expect(ScheduleExpansion.controls.afterEscape == .none)
        #expect(ScheduleExpansion.none.afterEscape == .none)
        var m = Self.openMachine()
        _ = m.handle(.scheduleChanged(.calendar))
        _ = m.handle(.scheduleChanged(m.schedule.afterEscape))
        #expect(m.schedule == .controls && m.phase == .open)
        _ = m.handle(.scheduleChanged(m.schedule.afterEscape))
        #expect(m.schedule == .none && m.phase == .open)
    }
}
