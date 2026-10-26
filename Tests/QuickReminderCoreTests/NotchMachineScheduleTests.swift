import Testing

@testable import QuickReminderCore

/// The in-notch Set Date variant: the open blob grows for the schedule controls / the month grid
/// and settles back, with the window canvas grown once and fitted again after the spring.
struct NotchMachineScheduleTests {

    private static func openMachine() -> NotchMachine {
        var m = NotchMachine()
        _ = m.handle(.show)
        return m
    }

    @Test func openingTheScheduleGrowsCanvasThenAnimatesUnderTheMask() {
        var m = Self.openMachine()
        let before = m.generation
        let effects = m.handle(.scheduleChanged(.controls))
        #expect(m.schedule == .controls)
        #expect(m.canvasGrown)
        #expect(m.generation == before + 1)
        #expect(effects == [.setSettled(false), .growCanvasForSchedule, .animateSchedule(.controls),
                            .scheduleSettle(generation: before + 1)])
    }

    @Test func calendarToggleOnlyAnimatesTheCanvasIsAlreadyTallEnough() {
        var m = Self.openMachine()
        _ = m.handle(.scheduleChanged(.controls))
        let effects = m.handle(.scheduleChanged(.calendar))
        #expect(m.schedule == .calendar)
        #expect(!effects.contains(.growCanvasForSchedule))
        #expect(effects.contains(.animateSchedule(.calendar)))
        #expect(effects.first == .setSettled(false))
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

    /// Set / Cancel / Esc: the blob springs back, the mask stays on until it settles, and only then
    /// is the canvas fitted to the plain panel again (shrinking earlier would clip the spring).
    @Test func closingSettlesThenFitsTheCanvas() {
        var m = Self.openMachine()
        _ = m.handle(.scheduleChanged(.calendar))
        let effects = m.handle(.scheduleChanged(.none))
        #expect(effects == [.setSettled(false), .animateSchedule(.none), .scheduleSettle(generation: m.generation)])
        #expect(m.canvasGrown, "canvas stays tall while the blob shrinks")
        let settled = m.handle(.settleTimerFired(generation: m.generation))
        #expect(settled == [.setSettled(true), .fitCanvasToPanel])
        #expect(!m.canvasGrown)
    }

    @Test func settleWhileStillScheduledKeepsTheTallCanvas() {
        var m = Self.openMachine()
        _ = m.handle(.scheduleChanged(.controls))
        #expect(m.handle(.settleTimerFired(generation: m.generation)) == [.setSettled(true)])
        #expect(m.canvasGrown)
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

    @Test func reopenStartsPlainAndParkingForgetsTheTallCanvas() {
        var m = NotchMachine()
        _ = m.handle(.screenChanged(hasNotch: true))
        _ = m.handle(.show)
        _ = m.handle(.scheduleChanged(.controls))
        _ = m.handle(.hide)
        _ = m.handle(.closeTimerFired(hasNotch: true))
        #expect(m.phase == .closed(parked: true))
        #expect(!m.canvasGrown)
        _ = m.handle(.show)
        #expect(m.schedule == .none)
        #expect(!m.canvasGrown)
    }

    /// Reopening mid-collapse keeps the (still tall) window; the next settle fits it.
    @Test func reopenMidCollapseFitsTheGrownCanvasOnSettle() {
        var m = Self.openMachine()
        _ = m.handle(.scheduleChanged(.controls))
        _ = m.handle(.hide)
        let effects = m.handle(.show)
        #expect(!effects.contains(.switchToOpenCanvas))
        #expect(m.canvasGrown)
        #expect(m.handle(.settleTimerFired(generation: m.generation)) == [.setSettled(true), .fitCanvasToPanel])
    }

    @Test func screenChangeWhileScheduledRelayoutsTheOpenWindow() {
        var m = Self.openMachine()
        _ = m.handle(.scheduleChanged(.calendar))
        let effects = m.handle(.screenChanged(hasNotch: true))
        #expect(effects == [.configureGeometry, .relayoutOpenWindow])
        #expect(m.schedule == .calendar)
    }
}
