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
        let effects = m.handle(.sectionChanged(.controls))
        #expect(m.section == .controls)
        #expect(m.generation == before + 1)
        #expect(effects == [.setSettled(false), .animateSection(.controls), .scheduleSettle(generation: before + 1)])
    }

    /// Every schedule step, there and back, is the same three effects — none of them geometry.
    @Test func noScheduleStepTouchesTheWindow() {
        var m = Self.openMachine()
        let windowEffects: [NotchEffect] = [.configureGeometry, .switchToOpenCanvas, .relayoutOpenWindow, .park, .orderOut]
        for step: NotchSection in [.controls, .calendar, .controls, .none, .calendar, .none] {
            let effects = m.handle(.sectionChanged(step))
            #expect(effects == [.setSettled(false), .animateSection(step), .scheduleSettle(generation: m.generation)], "\(step)")
            #expect(!effects.contains(where: windowEffects.contains))
            #expect(m.handle(.settleTimerFired(generation: m.generation)) == [.setSettled(true)])
        }
    }

    @Test func calendarToggleOnlyAnimatesTheCanvasIsAlreadyTallEnough() {
        var m = Self.openMachine()
        _ = m.handle(.sectionChanged(.controls))
        let effects = m.handle(.sectionChanged(.calendar))
        #expect(m.section == .calendar)
        #expect(effects == [.setSettled(false), .animateSection(.calendar), .scheduleSettle(generation: m.generation)])
    }

    /// A show while Set Date is open in the notch (URL scheme, menu item, Raycast / Spotlight
    /// reopen) returns to the plain panel through the Cancel transition, so NotchState follows.
    @Test func showWhileScheduledResetsTheSchedule() {
        var m = Self.openMachine()
        _ = m.handle(.sectionChanged(.calendar))
        let effects = m.handle(.show)
        #expect(m.phase == .open)
        #expect(m.section == .none)
        #expect(effects == [.setSettled(false), .animateSection(.none), .scheduleSettle(generation: m.generation)])
        #expect(m.handle(.settleTimerFired(generation: m.generation)) == [.setSettled(true)])
        // Plain and open: a further show is still a no-op.
        #expect(m.handle(.show).isEmpty)
        // And the section can be opened again afterwards (the machine is not stuck).
        #expect(m.handle(.sectionChanged(.controls)).contains(.animateSection(.controls)))
    }

    @Test func sameExpansionTwiceIsANoOp() {
        var m = Self.openMachine()
        _ = m.handle(.sectionChanged(.controls))
        let generation = m.generation
        #expect(m.handle(.sectionChanged(.controls)).isEmpty)
        #expect(m.generation == generation)
        var plain = Self.openMachine()
        #expect(plain.handle(.sectionChanged(.none)).isEmpty, "closing a section that is not open")
    }

    @Test(arguments: [NotchEvent.hide, .save(reduceMotion: false)])
    func ignoredUnlessOpen(_ leaving: NotchEvent) {
        var m = Self.openMachine()
        _ = m.handle(leaving)
        #expect(m.handle(.sectionChanged(.controls)).isEmpty)
        #expect(m.section == .none)
        var closed = NotchMachine()
        #expect(closed.handle(.sectionChanged(.calendar)).isEmpty)
    }

    /// Set / Cancel / Esc: the blob springs back under the mask, which drops once it settles.
    @Test func closingSettlesUnderTheMask() {
        var m = Self.openMachine()
        _ = m.handle(.sectionChanged(.calendar))
        let effects = m.handle(.sectionChanged(.none))
        #expect(effects == [.setSettled(false), .animateSection(.none), .scheduleSettle(generation: m.generation)])
        #expect(m.handle(.settleTimerFired(generation: m.generation)) == [.setSettled(true)])
    }

    @Test func staleSettleFromBeforeTheScheduleChangeIsDropped() {
        var m = Self.openMachine()
        let openGeneration = m.generation
        _ = m.handle(.sectionChanged(.controls))
        #expect(m.handle(.settleTimerFired(generation: openGeneration)).isEmpty,
                "the open settle must not drop the mask mid-growth")
    }

    @Test func hideAndSaveResetTheSchedule() {
        var m = Self.openMachine()
        _ = m.handle(.sectionChanged(.calendar))
        _ = m.handle(.hide)
        #expect(m.section == .none)

        var s = Self.openMachine()
        _ = s.handle(.sectionChanged(.controls))
        _ = s.handle(.save(reduceMotion: false))
        #expect(s.section == .none)
    }

    /// After parking, a reopen switches to a fresh open canvas exactly once and starts plain.
    @Test func reopenAfterParkingSwitchesCanvasOnceAndStartsPlain() {
        var m = NotchMachine()
        _ = m.handle(.screenChanged(hasNotch: true))
        let firstOpen = m.handle(.show)
        #expect(firstOpen.filter { $0 == .switchToOpenCanvas }.count == 1)
        _ = m.handle(.sectionChanged(.controls))
        _ = m.handle(.hide)
        _ = m.handle(.closeTimerFired(hasNotch: true))
        #expect(m.phase == .closed(parked: true))
        let reopen = m.handle(.show)
        #expect(reopen.filter { $0 == .switchToOpenCanvas }.count == 1)
        #expect(!reopen.contains(where: { if case .animateSection = $0 { return true } else { return false } }),
                "the plain start is set without animation inside switchToOpenCanvas")
        #expect(m.section == .none)
    }

    /// Reopening mid-collapse keeps the open window as it is (same size, no switch).
    @Test func reopenMidCollapseKeepsTheWindow() {
        var m = Self.openMachine()
        _ = m.handle(.sectionChanged(.controls))
        _ = m.handle(.hide)
        let effects = m.handle(.show)
        #expect(!effects.contains(.switchToOpenCanvas))
        #expect(m.section == .none)
        #expect(m.handle(.settleTimerFired(generation: m.generation)) == [.setSettled(true)])
    }

    @Test func screenChangeWhileScheduledRelayoutsTheOpenWindow() {
        var m = Self.openMachine()
        _ = m.handle(.sectionChanged(.calendar))
        let effects = m.handle(.screenChanged(hasNotch: true))
        #expect(effects == [.configureGeometry, .relayoutOpenWindow])
        #expect(m.section == .calendar)
    }

    /// Esc steps back one level; the panel itself is never closed by these steps.
    @Test func escapeStepsBackOneLevel() {
        #expect(NotchSection.calendar.afterEscape == .controls)
        #expect(NotchSection.controls.afterEscape == .none)
        #expect(NotchSection.none.afterEscape == .none)
        var m = Self.openMachine()
        _ = m.handle(.sectionChanged(.calendar))
        _ = m.handle(.sectionChanged(m.section.afterEscape))
        #expect(m.section == .controls && m.phase == .open)
        _ = m.handle(.sectionChanged(m.section.afterEscape))
        #expect(m.section == .none && m.phase == .open)
    }

    // MARK: - Location (one section at a time)

    @Test func locationIsASectionLikeSetDate() {
        var m = Self.openMachine()
        let effects = m.handle(.sectionChanged(.location))
        #expect(m.section == .location)
        #expect(effects == [.setSettled(false), .animateSection(.location), .scheduleSettle(generation: m.generation)])
    }

    /// Opening one section while the other is shown switches over in one spring (no close first).
    @Test(arguments: [(NotchSection.calendar, NotchSection.location), (.location, .controls), (.controls, .location)])
    func switchingSectionsIsOneStep(from: NotchSection, to: NotchSection) {
        var m = Self.openMachine()
        _ = m.handle(.sectionChanged(from))
        let effects = m.handle(.sectionChanged(to))
        #expect(m.section == to)
        #expect(effects == [.setSettled(false), .animateSection(to), .scheduleSettle(generation: m.generation)])
    }

    @Test func escapeAndShowCloseLocation() {
        #expect(NotchSection.location.afterEscape == .none)
        #expect(!NotchSection.location.isSchedule)
        #expect(NotchSection.controls.isSchedule && NotchSection.calendar.isSchedule)
        #expect(!NotchSection.none.isSchedule)
        var m = Self.openMachine()
        _ = m.handle(.sectionChanged(.location))
        _ = m.handle(.show)
        #expect(m.section == .none, "a show while Location is open returns to the plain panel")
        _ = m.handle(.sectionChanged(.location))
        _ = m.handle(.hide)
        #expect(m.section == .none)
    }
}
