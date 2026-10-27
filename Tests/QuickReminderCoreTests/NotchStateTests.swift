import AppKit
import SwiftUI
import Testing

@testable import QuickReminderCore

/// Size precedence and hover/closed canvas sizing for `NotchState`.
/// Ported 1:1 from the old `Tests/QuickReminderTests.swift` assertion runner.
@MainActor
struct NotchStateTests {

    @Test func hoverSizeIsClosedPlusGrowth() {
        let st = NotchState()
        #expect(st.hoverSize.width - st.closedSize.width == NotchLayout.hoverGrowth.width
                && st.hoverSize.height - st.closedSize.height == NotchLayout.hoverGrowth.height,
                "hover size = closed + growth")
    }

    @Test func closedCanvasContainsSwollenShapeAndIsSmallerThanOpenCanvas() {
        let st = NotchState()
        #expect(st.closedCanvasSize.width >= st.hoverSize.width && st.closedCanvasSize.height >= st.hoverSize.height,
                "closed canvas contains the swollen shape")
        #expect(st.closedCanvasSize.width < NotchLayout.canvasSize.width && st.closedCanvasSize.height < NotchLayout.canvasSize.height,
                "closed canvas is smaller than the open canvas")
    }

    @Test func currentSizePrecedence() {
        let st = NotchState()
        st.isSaving = true
        st.isOpen = true
        st.isHovering = true
        #expect(st.currentSize == st.savedSize, "currentSize: saving wins")

        st.isSaving = false
        #expect(st.currentSize == st.openSize, "currentSize: open beats hover")

        st.isOpen = false
        #expect(st.currentSize == st.hoverSize, "currentSize: hover beats closed")

        st.isHovering = false
        #expect(st.currentSize == st.closedSize, "currentSize: closed")
    }

    @Test func closedHitTest() {
        let st = NotchState()
        #expect(
            NotchShape.contains(
                CGPoint(x: st.closedCanvasSize.width / 2, y: st.closedSize.height / 2),
                canvasWidth: st.closedCanvasSize.width,
                shapeSize: st.closedSize,
                topCornerRadius: NotchLayout.closedTopRadius,
                bottomCornerRadius: NotchLayout.closedBottomRadius
            ),
            "closed hit test: centre inside"
        )
        #expect(
            !NotchShape.contains(
                CGPoint(x: 2, y: 10),
                canvasWidth: st.closedCanvasSize.width,
                shapeSize: st.closedSize,
                topCornerRadius: NotchLayout.closedTopRadius,
                bottomCornerRadius: NotchLayout.closedBottomRadius
            ),
            "closed hit test: margin outside"
        )
    }

    @Test func notchLayoutInvariants() {
        #expect(NotchLayout.openSize.height > 38 + 150, "open panel leaves room for header, input and bottom bar")
        #expect(NotchLayout.openSize(notchBandHeight: 50).height == NotchLayout.openSize(notchBandHeight: 39).height + 11,
                "the notch band is added on top of the content, not scaled")
        #expect(NotchLayout.canvasSize(for: NotchLayout.openSize).width == NotchLayout.openSize.width + 48)
        #expect(NotchLayout.closeDuration >= 0.3, "window stays until the close spring settles")
    }

    /// The panel height is the sum of the view constants (SPEC §4 "Vertical rhythm"); an
    /// undersized frame would centre and clip the stack, a taller one would float the ✓ button.
    @Test func openHeightFollowsTheRhythm() {
        for scale in [0.85, 1.0, 1.3, 1.6] as [CGFloat] {
            func sc(_ v: CGFloat) -> CGFloat { (v * scale).rounded(.toNearestOrEven) }
            let input = PlainTextView.lineHeight(for: sc(19)) + 2 + 1 + PlainTextView.lineHeight(for: sc(15)) + 2
            let expected = 8 + sc(36) + 10 + input + sc(26) + 8 + sc(48) + Theme.horizontalPadding
            #expect(NotchLayout.contentHeight(textScale: scale) == expected, "rhythm at scale \(scale)")
        }
        #expect(NotchLayout.contentHeight(textScale: 1) == 202, "8 + 36 + 10 + (25 + 1 + 20) + 26 + 8 + 48 + 20")
        #expect(NotchLayout.contentHeight(textScale: 1.6) > NotchLayout.contentHeight(textScale: 1))
    }

    // MARK: - In-notch Set Date

    @Test func currentSizeFollowsTheScheduleWhileOpen() {
        let st = NotchState()
        st.isOpen = true
        #expect(st.currentSize == st.openSize)
        st.schedule = .controls
        #expect(st.currentSize == st.scheduleSize)
        st.schedule = .calendar
        #expect(st.currentSize == st.scheduleCalendarSize)
        st.isSaving = true
        #expect(st.currentSize == st.savedSize, "saving still wins")
        st.isSaving = false
        st.isOpen = false
        #expect(st.currentSize == st.closedSize, "closed ignores a stale schedule")
    }

    /// The whole plain panel (header … bottom bar + its 20 pt inset) stays as it is and the section
    /// is appended below it; the sum must match `ScheduleNotchSection`'s rows exactly (an
    /// undersized blob would clip the footer, an oversized one would float it).
    @Test func scheduleHeightFollowsTheRhythm() {
        for scale in [0.85, 1.0, 1.3, 1.6] as [CGFloat] {
            func sc(_ v: CGFloat) -> CGFloat { (v * scale).rounded(.toNearestOrEven) }
            let input = PlainTextView.lineHeight(for: sc(19)) + 2 + 1 + PlainTextView.lineHeight(for: sc(15)) + 2
            let top = 8 + sc(36) + 10 + input
            let plain = top + sc(26) + 8 + sc(48) + Theme.horizontalPadding
            let controls = sc(36) + 6 + sc(18) + 10 + 2 * sc(44) + 8 + 12 + sc(30) + 14 + sc(36)
            let calendar = 10 + sc(26) + sc(18) + 6 * sc(28) + 5 * 2
            #expect(NotchLayout.topContentHeight(textScale: scale) == top, "top at \(scale)")
            #expect(NotchLayout.contentHeight(textScale: scale) == plain, "plain panel at \(scale)")
            #expect(NotchLayout.scheduleContentHeight(textScale: scale, calendar: false) == plain + controls + Theme.horizontalPadding,
                    "controls at \(scale)")
            #expect(NotchLayout.scheduleContentHeight(textScale: scale, calendar: true) == plain + controls + calendar + Theme.horizontalPadding,
                    "calendar at \(scale)")
        }
        #expect(NotchLayout.scheduleContentHeight(textScale: 1, calendar: false) == 480, "202 plain + 258 section + 20")
        #expect(NotchLayout.scheduleContentHeight(textScale: 1, calendar: true) == 712, "480 + 10 + 26 + 18 + 168 + 10")
    }

    /// The plain panel is the fixed top of every grown state: the section starts where the plain
    /// panel ends, so nothing above it moves when the blob grows.
    @Test func theSectionIsAppendedBelowThePlainPanel() {
        for band in [33, 39] as [CGFloat] {
            let plain = NotchLayout.openSize(notchBandHeight: band)
            #expect(NotchLayout.scheduleSectionTop(notchBandHeight: band, textScale: NotchLayout.textScale) == plain.height,
                    "section top = plain panel bottom (band \(band))")
        }
        #expect(abs(NotchLayout.scheduleSectionTop(notchBandHeight: 39, textScale: 1) - (39 + 202)) < 0.01)
    }

    @Test func scheduleSizesGrowOnlyInHeight() {
        let band = NotchLayout.defaultNotchBandHeight
        let plain = NotchLayout.openSize(notchBandHeight: band)
        let controls = NotchLayout.openSize(notchBandHeight: band, schedule: .controls)
        let calendar = NotchLayout.openSize(notchBandHeight: band, schedule: .calendar)
        #expect(NotchLayout.openSize(notchBandHeight: band, schedule: .none) == plain)
        #expect(controls.width == plain.width && calendar.width == plain.width)
        #expect(plain.height < controls.height && controls.height < calendar.height)
        #expect(NotchLayout.openSize(notchBandHeight: 50, schedule: .calendar).height == calendar.height + 11,
                "the notch band is added on top, not scaled")
        // The tallest state (with the overshoot room) still fits under the menu bar of a 13" Air.
        #expect(NotchLayout.canvasSize(for: calendar).height < 900)
    }

    // MARK: - Screen clamp, section top, click outside

    /// A short screen (or a large text size) clamps the grown panel to what fits above the Dock;
    /// the section's rows scroll then. Never shorter than the plain panel.
    @Test func scheduleHeightIsClampedToTheScreen() {
        let band = NotchLayout.defaultNotchBandHeight
        let plain = NotchLayout.openSize(notchBandHeight: band)
        let natural = NotchLayout.openSize(notchBandHeight: band, schedule: .calendar)
        #expect(NotchLayout.openSize(notchBandHeight: band, schedule: .calendar, maxHeight: natural.height + 100) == natural,
                "fits: unchanged")
        let clamped = NotchLayout.openSize(notchBandHeight: band, schedule: .calendar, maxHeight: 500.7)
        #expect(clamped.height == 500, "clamped to the whole point below the limit")
        #expect(clamped.width == natural.width)
        #expect(NotchLayout.openSize(notchBandHeight: band, schedule: .controls, maxHeight: 100).height == plain.height,
                "never below the plain panel")
        #expect(NotchLayout.openSize(notchBandHeight: band, schedule: .none, maxHeight: 100) == plain)
    }

    @Test func maxPanelHeightStopsAboveTheDockWithRoomForTheOvershoot() {
        // 14" MacBook Pro at default scaling, Dock 70 pt at the bottom, menu bar 38 pt.
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let visible = CGRect(x: 0, y: 70, width: 1512, height: 982 - 70 - 38)
        let maxHeight = NotchLayout.maxPanelHeight(screenFrame: screen, visibleFrame: visible)
        #expect(maxHeight == 982 - 70 - NotchLayout.scheduleScreenMargin)
        #expect(NotchLayout.scheduleScreenMargin == 40, "24 pt overshoot room + 16 pt air")
        // Hidden Dock: the whole height below the top edge.
        #expect(NotchLayout.maxPanelHeight(screenFrame: screen, visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 944))
                == 982 - NotchLayout.scheduleScreenMargin)
        // Secondary display above the main one (non-zero origin).
        let upper = CGRect(x: 0, y: 982, width: 1920, height: 1080)
        #expect(NotchLayout.maxPanelHeight(screenFrame: upper, visibleFrame: CGRect(x: 0, y: 982, width: 1920, height: 1055))
                == 1080 - NotchLayout.scheduleScreenMargin)
    }

    /// Header, title and notes cancel; the chip slot and the bottom bar below them keep their own
    /// meaning (calendar button toggles, date chip no-op, ✓ saves), and the section does not cancel.
    @Test func clickOnTheTextRowsCancelsScheduling() {
        let bandBottom = NotchLayout.scheduleCancelBandBottom(notchBandHeight: 39, textScale: 1)
        let sectionTop = NotchLayout.scheduleSectionTop(notchBandHeight: 39, textScale: 1)
        #expect(abs(bandBottom - (39 + 100)) < 0.01, "header + title + notes")
        #expect(NotchLayout.clickCancelsSchedule(atY: bandBottom - 30, bandBottom: bandBottom, schedule: .controls), "title row")
        #expect(NotchLayout.clickCancelsSchedule(atY: 60, bandBottom: bandBottom, schedule: .calendar), "header")
        let barCentre = bandBottom + 26 + 8 + 24
        #expect(!NotchLayout.clickCancelsSchedule(atY: bandBottom + 10, bandBottom: bandBottom, schedule: .controls), "date chip slot")
        #expect(!NotchLayout.clickCancelsSchedule(atY: barCentre, bandBottom: bandBottom, schedule: .controls), "bottom bar")
        #expect(!NotchLayout.clickCancelsSchedule(atY: sectionTop + 1, bandBottom: bandBottom, schedule: .controls), "inside the section")
        #expect(!NotchLayout.clickCancelsSchedule(atY: bandBottom - 30, bandBottom: bandBottom, schedule: .none), "nothing to cancel")
    }
}
