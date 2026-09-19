import AppKit
import SwiftUI
import Testing

@testable import QuickReminderCore

/// Geometry, width and hit-testing checks for `NotchShape` / `NotchGeometry`.
/// Ported 1:1 from the old `Tests/QuickReminderTests.swift` assertion runner.
struct NotchShapeTests {

    @Test func widthAddsBothTopFillets() {
        #expect(NotchShape.width(forNotchWidth: 221, topCornerRadius: 6) == 233)
    }

    @Test func closedSilhouetteContainsTests() {
        let closed = NotchShape(topCornerRadius: 6, bottomCornerRadius: 14)
            .path(in: CGRect(x: 0, y: 0, width: 233, height: 38))
        #expect(closed.contains(CGPoint(x: 116, y: 19)), "centre is inside the silhouette")
        #expect(!closed.contains(CGPoint(x: 1, y: 37)), "below the top-left fillet is outside")
        #expect(!closed.contains(CGPoint(x: 7, y: 37)), "bottom-left rounded corner is outside")
        #expect(closed.contains(CGPoint(x: 3, y: 0.05)), "top edge reaches into the outward fillet (flush with the bezel)")
    }

    @MainActor
    @Test func openShapeFillsItsRect() {
        let open = NotchShape(topCornerRadius: 19, bottomCornerRadius: 32)
            .path(in: CGRect(origin: .zero, size: NotchLayout.openSize))
        #expect(open.boundingRect.width == NotchLayout.openSize.width)
    }

    @MainActor
    @Test func hitTestTopDownCanvasCoordinates() {
        let canvas = NotchLayout.canvasSize.width
        let size = NotchLayout.openSize
        let r = { (p: CGPoint) in
            NotchShape.contains(p, canvasWidth: canvas, shapeSize: size, topCornerRadius: 19, bottomCornerRadius: 32)
        }
        let ox = (canvas - size.width) / 2
        #expect(r(CGPoint(x: ox + size.width / 2, y: size.height / 2)), "centre is inside")
        #expect(r(CGPoint(x: ox + 2, y: 0.2)), "top-left fillet next to the menu bar is inside")
        #expect(!r(CGPoint(x: ox + 25, y: size.height - 4)), "bottom-left rounded corner gap is outside")
        #expect(!r(CGPoint(x: ox - 5, y: 50)), "left of the body is outside")
        #expect(r(CGPoint(x: ox + 20, y: 50)), "just inside the straight side is inside")
    }

    @MainActor
    @Test func notchGeometryChecks() {
        if let screen = NSScreen.screens.first(where: { NotchGeometry.notchRect(for: $0) != nil }),
           let rect = NotchGeometry.notchRect(for: screen) {
            #expect(rect.height == screen.safeAreaInsets.top, "notch height equals the safe-area inset")
            #expect(abs(rect.midX - screen.frame.midX) < 1, "notch is horizontally centred")
        }
        if let screen = NSScreen.screens.first {
            let fallback = NotchGeometry.fallbackNotchSize(for: screen)
            #expect(fallback.width == 200 && fallback.height > 0, "fallback pill is 200pt wide with a positive height")
        }
    }
}
