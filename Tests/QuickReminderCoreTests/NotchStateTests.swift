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
        st.section = .controls
        #expect(st.currentSize == st.scheduleSize)
        st.section = .calendar
        #expect(st.currentSize == st.scheduleCalendarSize)
        st.isSaving = true
        #expect(st.currentSize == st.savedSize, "saving still wins")
        st.isSaving = false
        st.isOpen = false
        #expect(st.currentSize == st.closedSize, "closed ignores a stale section")
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

    @Test func scheduleSizesGrowOnlyInHeight() {
        let band = NotchLayout.defaultNotchBandHeight
        let plain = NotchLayout.openSize(notchBandHeight: band)
        let controls = NotchLayout.openSize(notchBandHeight: band, section: .controls)
        let calendar = NotchLayout.openSize(notchBandHeight: band, section: .calendar)
        #expect(NotchLayout.openSize(notchBandHeight: band, section: .none) == plain)
        #expect(controls.width == plain.width && calendar.width == plain.width)
        #expect(plain.height < controls.height && controls.height < calendar.height)
        #expect(NotchLayout.openSize(notchBandHeight: 50, section: .calendar).height == calendar.height + 11,
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
        let natural = NotchLayout.openSize(notchBandHeight: band, section: .calendar)
        #expect(NotchLayout.openSize(notchBandHeight: band, section: .calendar, maxHeight: natural.height + 100) == natural,
                "fits: unchanged")
        let clamped = NotchLayout.openSize(notchBandHeight: band, section: .calendar, maxHeight: 500.7)
        #expect(clamped.height == 500, "clamped to the whole point below the limit")
        #expect(clamped.width == natural.width)
        #expect(NotchLayout.openSize(notchBandHeight: band, section: .controls, maxHeight: 100).height == plain.height,
                "never below the plain panel")
        #expect(NotchLayout.openSize(notchBandHeight: band, section: .none, maxHeight: 100) == plain)
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
    /// Uses the overload the panel's mouse-down monitor calls.
    @Test func clickOnTheTextRowsCancelsScheduling() {
        func cancels(_ y: CGFloat, _ section: NotchSection = .controls) -> Bool {
            NotchLayout.clickCancelsSection(atY: y, notchBandHeight: 39, textScale: 1, section: section)
        }
        let bandBottom = NotchLayout.sectionCancelBandBottom(notchBandHeight: 39, textScale: 1)
        #expect(abs(bandBottom - (39 + 100)) < 0.01, "header + title + notes")
        #expect(cancels(60, .calendar), "header")
        #expect(cancels(105), "title row")
        #expect(cancels(128), "notes row")
        #expect(!cancels(152), "date chip slot")
        #expect(!cancels(197), "bottom bar centre (calendar button, ✓): must reach prepareSave with the edit")
        #expect(!cancels(39 + 202 + 10), "inside the section")
        #expect(!cancels(105, .none), "nothing to cancel")
    }

    /// While open only the black shape takes the mouse; the tall canvas around and below it passes
    /// clicks, scrolls and hovers through to the app below.
    @Test func onlyTheBlackShapeTakesTheMouse() {
        let canvasWidth: CGFloat = 648
        let plain = CGSize(width: 600, height: 241)
        let grown = CGSize(width: 600, height: 519)
        let centreX = canvasWidth / 2
        #expect(!NotchLayout.passesMouseThrough(CGPoint(x: centreX, y: 100), canvasWidth: canvasWidth, panelSize: plain), "title")
        #expect(!NotchLayout.passesMouseThrough(CGPoint(x: 24 + 560, y: 197), canvasWidth: canvasWidth, panelSize: plain), "✓")
        #expect(NotchLayout.passesMouseThrough(CGPoint(x: centreX, y: 400), canvasWidth: canvasWidth, panelSize: plain),
                "below the plain panel: the app below gets it")
        #expect(NotchLayout.passesMouseThrough(CGPoint(x: 10, y: 100), canvasWidth: canvasWidth, panelSize: plain), "side overshoot room")
        #expect(NotchLayout.passesMouseThrough(CGPoint(x: 24 + 2, y: 239), canvasWidth: canvasWidth, panelSize: plain), "outside the rounded corner")
        #expect(!NotchLayout.passesMouseThrough(CGPoint(x: centreX, y: 400), canvasWidth: canvasWidth, panelSize: grown),
                "the same spot is the Set Date section once the blob has grown")
        #expect(NotchLayout.passesMouseThrough(CGPoint(x: centreX, y: 700), canvasWidth: canvasWidth, panelSize: grown))
        // Body sides: the 600 pt shape rect sits at x 24 … 624 in the 648 pt canvas, and its straight
        // sides are the open top radius (19 pt) further in (the concave top fillets), so x 43 … 605.
        // Just inside vs just outside, mid-height, so a wrong bounding box (early-out) fails here.
        let inset = 24 + NotchLayout.openTopRadius
        #expect(!NotchLayout.passesMouseThrough(CGPoint(x: canvasWidth - inset - 2, y: 120), canvasWidth: canvasWidth, panelSize: plain), "just inside the right side")
        #expect(NotchLayout.passesMouseThrough(CGPoint(x: canvasWidth - inset + 2, y: 120), canvasWidth: canvasWidth, panelSize: plain), "just outside the right side")
        #expect(!NotchLayout.passesMouseThrough(CGPoint(x: inset + 2, y: 120), canvasWidth: canvasWidth, panelSize: plain), "just inside the left side")
        #expect(NotchLayout.passesMouseThrough(CGPoint(x: inset - 2, y: 120), canvasWidth: canvasWidth, panelSize: plain), "just outside the left side")
        #expect(NotchLayout.passesMouseThrough(CGPoint(x: centreX, y: 242), canvasWidth: canvasWidth, panelSize: plain), "just below the bottom edge")
    }

    /// Never drop the window mid-press; taking the mouse back is immediate.
    @Test func ignoringTheMouseWaitsForTheButtonRelease() {
        #expect(!NotchLayout.shouldIgnoreMouse(target: true, current: false, buttonsPressed: true), "holds false while pressed")
        #expect(NotchLayout.shouldIgnoreMouse(target: true, current: false, buttonsPressed: false), "flips on release")
        #expect(!NotchLayout.shouldIgnoreMouse(target: false, current: true, buttonsPressed: true), "back into the shape: immediate")
        #expect(NotchLayout.shouldIgnoreMouse(target: true, current: true, buttonsPressed: true), "already ignoring stays")
        #expect(!NotchLayout.shouldIgnoreMouse(target: false, current: false, buttonsPressed: false))
    }

    /// Global bottom-left mouse coordinates → top-down canvas points, also for a window whose
    /// screen does not start at y 0 (a display arranged above / below the main one).
    @Test func canvasPointConversion() {
        let frame = CGRect(x: 432, y: 1169 - 775, width: 648, height: 775)
        #expect(NotchLayout.canvasPoint(mouse: CGPoint(x: 432, y: 1169), windowFrame: frame) == .zero, "top-left")
        #expect(NotchLayout.canvasPoint(mouse: CGPoint(x: 756, y: 1169 - 197), windowFrame: frame) == CGPoint(x: 324, y: 197))
        let upper = CGRect(x: -200, y: 1169 + 1080 - 775, width: 648, height: 775)   // screen above, minY ≠ 0
        #expect(NotchLayout.canvasPoint(mouse: CGPoint(x: 124, y: 1169 + 1080 - 100), windowFrame: upper) == CGPoint(x: 324, y: 100))
        // Round trip into the pass-through decision: centre of the title row on that screen.
        let title = NotchLayout.canvasPoint(mouse: CGPoint(x: 124, y: 1169 + 1080 - 100), windowFrame: upper)
        #expect(!NotchLayout.passesMouseThrough(title, canvasWidth: upper.width, panelSize: CGSize(width: 600, height: 241)))
    }

    // MARK: - Open canvas (constant from open to close)

    /// In notch style the open window is sized at open for the tallest Set Date state, so the
    /// blob grows inside it without the window ever resizing; the popover style keeps the plain one.
    @Test func openCanvasFitsTheTallestScheduleStateInNotchStyle() {
        let band = NotchLayout.defaultNotchBandHeight
        let plain = NotchLayout.openSize(notchBandHeight: band)
        let calendar = NotchLayout.openSize(notchBandHeight: band, section: .calendar)
        let notch = NotchLayout.openCanvasSize(openSize: plain, tallestSectionSize: calendar, style: .notch)
        #expect(notch == NotchLayout.canvasSize(for: calendar))
        #expect(notch.height >= NotchLayout.openSize(notchBandHeight: band, section: .controls).height + NotchLayout.overshootPadding,
                "every section state plus the overshoot room fits")
        #expect(NotchLayout.openCanvasSize(openSize: plain, tallestSectionSize: calendar, style: .popover)
                == NotchLayout.canvasSize(for: plain))
        // A clamped (shorter) schedule size never makes the canvas smaller than the plain panel's.
        let tiny = CGSize(width: plain.width, height: plain.height - 50)
        #expect(NotchLayout.openCanvasSize(openSize: plain, tallestSectionSize: tiny, style: .notch) == NotchLayout.canvasSize(for: plain))
    }

    /// At 100 % text size with a 39 pt band: 751 pt calendar blob + 24 pt overshoot, 648 pt wide.
    @Test func openCanvasAtDefaultTextSize() {
        let plain = CGSize(width: 600, height: 39 + 202)
        let calendar = CGSize(width: 600, height: 39 + 712)
        #expect(NotchLayout.openCanvasSize(openSize: plain, tallestSectionSize: calendar, style: .notch) == CGSize(width: 648, height: 775))
        #expect(NotchLayout.openCanvasSize(openSize: plain, tallestSectionSize: calendar, style: .popover) == CGSize(width: 648, height: 265))
    }

    // MARK: - Location section

    /// The plain panel stays and the Location section (field 36 + 6 + five 34 pt suggestion rows,
    /// always reserved + 14 + footer 36) is appended.
    @Test func locationHeightFollowsTheRhythm() {
        for scale in [0.85, 1.0, 1.3, 1.6] as [CGFloat] {
            func sc(_ v: CGFloat) -> CGFloat { (v * scale).rounded(.toNearestOrEven) }
            let section = sc(36) + 6 + 5 * sc(34) + 14 + sc(36)
            #expect(NotchLayout.LocationMetrics.listHeight(textScale: scale) == 5 * sc(34), "list at \(scale)")
            #expect(NotchLayout.LocationMetrics.sectionHeight(textScale: scale) == section, "section at \(scale)")
            #expect(NotchLayout.locationContentHeight(textScale: scale)
                    == NotchLayout.contentHeight(textScale: scale) + section + Theme.horizontalPadding, "content at \(scale)")
        }
        #expect(NotchLayout.LocationMetrics.rows == PlaceSearchModel.maxRows, "room for every row the model shows")
        #expect(NotchLayout.LocationMetrics.sectionHeight(textScale: 1) == 262)
        #expect(abs(NotchLayout.locationContentHeight(textScale: 1) - 484) < 0.01, "202 plain + 262 + 20")
    }

    @Test func locationSizeAndPrecedence() {
        let band = NotchLayout.defaultNotchBandHeight
        let plain = NotchLayout.openSize(notchBandHeight: band)
        let location = NotchLayout.openSize(notchBandHeight: band, section: .location)
        let calendar = NotchLayout.openSize(notchBandHeight: band, section: .calendar)
        #expect(location.width == plain.width)
        #expect(location.height == 523, "39 band + 484")
        #expect(plain.height < location.height && location.height < calendar.height,
                "the calendar stays the tallest state, so the canvas never resizes for Location")
        #expect(NotchLayout.openSize(notchBandHeight: band, section: .location, maxHeight: plain.height + 10).height == plain.height + 10,
                "clamped like Set Date")

        let st = NotchState()
        st.isOpen = true
        st.section = .location
        #expect(st.currentSize == st.locationSize)
        #expect(st.tallestSectionSize == st.scheduleCalendarSize, "the calendar stays the tallest: the canvas does not change")
        #expect(NotchLayout.clickCancelsSection(atY: 105, notchBandHeight: 39, textScale: 1, section: .location), "title cancels Location too")
        #expect(!NotchLayout.clickCancelsSection(atY: 197, notchBandHeight: 39, textScale: 1, section: .location), "the bar does not")
    }
}
