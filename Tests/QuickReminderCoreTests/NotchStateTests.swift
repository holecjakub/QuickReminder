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
}
