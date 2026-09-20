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
        #expect(NotchLayout.closeDuration >= 0.3, "window stays until the close spring settles")
    }
}
