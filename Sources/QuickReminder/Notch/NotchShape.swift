//
//  NotchShape.swift
//  QuickReminder
//
//  The silhouette of the MacBook notch, drawn so that it can grow into a panel.
//
//  Geometry is modelled on the shape shared by DynamicNotchKit (MrKai77) and
//  boring.notch (TheBoredTeam), which both trace the outline with four quadratic
//  curves: two *outward* (concave) fillets at the top that blend the black body
//  into the screen bezel, and two ordinary convex fillets at the bottom.
//

import AppKit
import SwiftUI

// MARK: - NotchShape

/// The notch silhouette: a flat top edge flush with `rect.minY`, top corners that
/// curve *outward* into the surrounding menu bar, straight sides and rounded
/// bottom corners.
///
/// The shape is drawn to fill the whole `rect`, so the caller is responsible for
/// sizing it. Because the top fillets eat `topCornerRadius` of horizontal space on
/// each side, the rect must be `notchWidth + 2 * topCornerRadius` wide for the
/// straight sides to line up with the real notch cutout — see
/// ``NotchShape/width(forNotchWidth:topCornerRadius:)``.
/// (Same convention as DynamicNotchKit's `NotchView.minWidth`.)
///
/// ```swift
/// NotchShape(topCornerRadius: 6, bottomCornerRadius: 14)
///     .fill(.black)
///     .frame(width: NotchShape.width(forNotchWidth: 221, topCornerRadius: 6), height: 38)
/// ```
struct NotchShape: Shape {
    /// Radius of the two concave fillets at the top, where the shape meets the
    /// screen edge. `6` closed / `15`–`19` open in the reference projects.
    var topCornerRadius: CGFloat

    /// Radius of the two convex corners at the bottom of the shape.
    /// `14` closed / `24`–`32` open in the reference projects.
    var bottomCornerRadius: CGFloat

    /// - Parameters:
    ///   - topCornerRadius: defaults to ``NotchShape/Radius/closedTop`` (6pt, boring.notch).
    ///   - bottomCornerRadius: defaults to ``NotchShape/Radius/closedBottom`` (14pt, boring.notch).
    init(
        topCornerRadius: CGFloat = Radius.closedTop,
        bottomCornerRadius: CGFloat = Radius.closedBottom
    ) {
        self.topCornerRadius = topCornerRadius
        self.bottomCornerRadius = bottomCornerRadius
    }

    /// Both radii animate together, so a single `withAnimation` call morphs the
    /// closed pill into the opened panel.
    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topCornerRadius, bottomCornerRadius) }
        set {
            topCornerRadius = newValue.first
            bottomCornerRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        // Clamp so a too-small rect degrades to a plain rounded rectangle instead
        // of producing self-intersecting curves.
        let top = max(0, min(topCornerRadius, rect.width / 2))
        let bottom = max(0, min(bottomCornerRadius, min(rect.height, rect.width / 2 - top)))

        var path = Path()

        // Start at the top-left, flush with the top of the rect (the screen edge).
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))

        // Top-left: concave fillet curving *outward*, so the black body appears to
        // flow into the menu bar rather than end in a hard corner.
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + top, y: rect.minY + top),
            control: CGPoint(x: rect.minX + top, y: rect.minY)
        )

        // Left side.
        path.addLine(to: CGPoint(x: rect.minX + top, y: rect.maxY - bottom))

        // Bottom-left: ordinary convex corner.
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + top + bottom, y: rect.maxY),
            control: CGPoint(x: rect.minX + top, y: rect.maxY)
        )

        // Bottom edge.
        path.addLine(to: CGPoint(x: rect.maxX - top - bottom, y: rect.maxY))

        // Bottom-right.
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - top, y: rect.maxY - bottom),
            control: CGPoint(x: rect.maxX - top, y: rect.maxY)
        )

        // Right side.
        path.addLine(to: CGPoint(x: rect.maxX - top, y: rect.minY + top))

        // Top-right: the mirrored concave fillet.
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.maxX - top, y: rect.minY)
        )

        // Close along the top edge.
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.closeSubpath()

        return path
    }
}

extension NotchShape {
    /// Corner radii used by the reference implementations.
    enum Radius {
        /// boring.notch `cornerRadiusInsets.closed.top` — also DynamicNotchKit's compact top.
        static let closedTop: CGFloat = 6
        /// boring.notch `cornerRadiusInsets.closed.bottom` — also DynamicNotchKit's compact bottom.
        static let closedBottom: CGFloat = 14
        /// boring.notch `cornerRadiusInsets.opened.top` is 19; DynamicNotchKit's `.notch` preset uses 15.
        static let openTop: CGFloat = 19
        /// boring.notch uses 24 open; NotchDrop uses 32; DynamicNotchKit's preset 20.
        static let openBottom: CGFloat = 32
    }

    /// Total width the shape needs so that its straight sides sit exactly on the
    /// edges of a notch `notchWidth` wide.
    ///
    /// Mirrors `NotchView.minWidth` in DynamicNotchKit (`notchSize.width + topCornerRadius * 2`).
    static func width(forNotchWidth notchWidth: CGFloat, topCornerRadius: CGFloat = Radius.closedTop) -> CGFloat {
        notchWidth + topCornerRadius * 2
    }
}

// MARK: - NotchGeometry

/// Measures the physical notch of a display.
enum NotchGeometry {
    /// Extra size added to the real notch so the drawn black shape slightly
    /// overlaps the hardware cutout and hides anti-aliasing seams.
    ///
    /// boring.notch adds `+4` to the computed notch width; NotchDrop uses an
    /// `inset` of `-4` for the same reason. 2pt on each side is the compromise.
    static let bleed: CGFloat = 4

    /// Fallback notch size for displays without a hardware notch.
    ///
    /// NotchDrop falls back to `150 × 28`, DynamicNotchKit to `300 × menuBarHeight`.
    /// We keep a 200pt pill and match the menu bar height when we can read it.
    static let fallbackSize = CGSize(width: 200, height: 32)

    /// The real notch rectangle in screen (bottom-left origin, global) coordinates,
    /// or `nil` when `screen` has no notch.
    ///
    /// Width comes from the auxiliary top areas — everything the menu bar cannot
    /// use on the left and right of the cutout — and height from `safeAreaInsets.top`
    /// (38pt on a 14" MacBook Pro). Same derivation as `NSScreen.notchSize` in
    /// both NotchDrop and DynamicNotchKit.
    @MainActor
    static func notchRect(for screen: NSScreen) -> CGRect? {
        guard screen.safeAreaInsets.top > 0,
              let leftArea = screen.auxiliaryTopLeftArea,
              let rightArea = screen.auxiliaryTopRightArea,
              leftArea.width > 0, rightArea.width > 0
        else { return nil }

        let height = screen.safeAreaInsets.top
        let width = screen.frame.width - leftArea.width - rightArea.width
        guard width > 0 else { return nil }

        return CGRect(
            x: screen.frame.midX - width / 2,
            y: screen.frame.maxY - height,
            width: width,
            height: height
        )
    }

    /// A plausible notch size for a display that has none (external monitor, or an
    /// older MacBook): the fallback width, with the menu bar height when readable.
    @MainActor
    static func fallbackNotchSize(for screen: NSScreen) -> CGSize {
        let menuBarHeight = screen.frame.maxY - screen.visibleFrame.maxY
        return CGSize(
            width: fallbackSize.width,
            height: menuBarHeight > 0 ? menuBarHeight : fallbackSize.height
        )
    }

    /// The notch rect if there is one, otherwise a centred rect of
    /// ``fallbackNotchSize(for:)`` at the top of the screen.
    @MainActor
    static func notchRectOrFallback(for screen: NSScreen) -> CGRect {
        if let rect = notchRect(for: screen) { return rect }
        let size = fallbackNotchSize(for: screen)
        return CGRect(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }

    /// The notch rect grown by ``bleed`` in both dimensions, anchored to the top
    /// edge — what the closed black shape should actually be drawn at.
    @MainActor
    static func closedShapeSize(for screen: NSScreen) -> CGSize {
        let rect = notchRectOrFallback(for: screen)
        return CGSize(width: rect.width + bleed, height: rect.height + bleed / 2)
    }
}

// MARK: - Preview

#Preview("Notch shape") {
    VStack(spacing: 48) {
        // Closed: 221pt notch + 2 x 6pt fillets, 38pt tall (14" MacBook Pro).
        NotchShape(topCornerRadius: NotchShape.Radius.closedTop,
                   bottomCornerRadius: NotchShape.Radius.closedBottom)
            .fill(.white)
            .frame(width: NotchShape.width(forNotchWidth: 221), height: 38)

        // Opened panel.
        NotchShape(topCornerRadius: NotchShape.Radius.openTop,
                   bottomCornerRadius: NotchShape.Radius.openBottom)
            .fill(.white)
            .frame(width: 420, height: 180)
    }
    .frame(width: 520, height: 340, alignment: .top)
    .padding(.top, 24)
    .background(Color.black)
}
