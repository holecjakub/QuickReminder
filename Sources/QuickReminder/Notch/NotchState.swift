import AppKit
import SwiftUI

/// Single source of truth for the notch panel geometry and open/closed state.
/// Sizes are in points, in the coordinate space of the hosting window.
@MainActor
final class NotchState: ObservableObject {
    /// Whether the panel is expanded (content visible) or collapsed to the notch silhouette.
    @Published var isOpen: Bool = false
    /// Drives the content fade; toggled slightly after `isOpen` so the shape leads and the content follows.
    @Published var contentVisible: Bool = false
    /// True once the open spring has settled; the content mask is dropped then (it forces
    /// offscreen rendering of the whole panel on every repaint while attached).
    @Published var isSettled: Bool = false
    /// "Saved" phase: the silhouette collapses to notch height but stays wider at the sides
    /// while the ✓ flies into the right-hand extension and plays its done animation.
    @Published var isSaving: Bool = false
    /// The saved badge exists (and the save button yields its geometry) from the moment of
    /// saving until the window is ordered out, so the badge never flies back to the button.
    @Published var savedBadgeShown: Bool = false
    /// Pointer is over the (closed) notch: the silhouette swells slightly to acknowledge it.
    @Published var isHovering: Bool = false
    /// Size of the hosting canvas (= window). Small around the closed notch so the window only
    /// intercepts clicks on the notch itself; the full canvas while the panel is open.
    @Published var canvasSize: CGSize = NotchLayout.canvasSize

    /// Size of the collapsed silhouette. Slightly larger than the physical notch so
    /// anti-aliased edges never peek out around the bezel.
    @Published var closedSize: CGSize = CGSize(width: 221, height: 38)
    /// Size of the fully expanded panel.
    @Published var openSize: CGSize = NotchLayout.openSize

    /// Height of the band occupied by the physical notch / menu bar at the top of the panel.
    var notchBandHeight: CGFloat { closedSize.height }

    var currentSize: CGSize {
        if isSaving { return savedSize }
        if isOpen { return openSize }
        if isHovering { return hoverSize }
        return closedSize
    }

    /// Closed silhouette, swollen by `NotchLayout.hoverGrowth` while the pointer is over it.
    var hoverSize: CGSize {
        CGSize(width: closedSize.width + NotchLayout.hoverGrowth.width, height: closedSize.height + NotchLayout.hoverGrowth.height)
    }

    /// Window/canvas size while closed: the hover-swollen silhouette plus a small margin.
    var closedCanvasSize: CGSize {
        CGSize(width: hoverSize.width + NotchLayout.closedCanvasMargin.width, height: hoverSize.height + NotchLayout.closedCanvasMargin.height)
    }

    /// Notch height, widened by `NotchLayout.savedExtension` on each side.
    var savedSize: CGSize {
        CGSize(width: closedSize.width + 2 * NotchLayout.savedExtension, height: closedSize.height)
    }
}

/// Layout constants for the expanded quick-reminder panel.
enum NotchLayout {
    static let openSize = CGSize(width: 600, height: 214)
    /// Extra room around the open panel so the bouncy spring's ~2 % overshoot is not clipped
    /// by the window edge (notch-research.md: "a bouncy spring overshoots the mask").
    static let overshootPadding: CGFloat = 24
    /// Window / container size: open panel plus overshoot room on the sides and bottom.
    static var canvasSize: CGSize {
        CGSize(width: openSize.width + 2 * overshootPadding, height: openSize.height + overshootPadding)
    }
    static let closedTopRadius: CGFloat = NotchShape.Radius.closedTop
    static let closedBottomRadius: CGFloat = NotchShape.Radius.closedBottom
    static let openTopRadius: CGFloat = NotchShape.Radius.openTop
    static let openBottomRadius: CGFloat = NotchShape.Radius.openBottom

    /// Extra width on each side of the notch during the "saved" phase (room for the ✓ on the right).
    static let savedExtension: CGFloat = 72
    /// Diameter of the ✓ badge that lands in the right-hand extension.
    static let savedBadgeSize: CGFloat = 24
    /// Panel → saved pill (shape + ✓ flight).
    static let savingAnimation: Animation = .spring(response: 0.45, dampingFraction: 0.82, blendDuration: 0)
    /// How long the saved pill stays before the notch returns to normal.
    static let savedHold: TimeInterval = 1.0

    /// How much the closed notch grows on hover (total, both sides / bottom).
    static let hoverGrowth = CGSize(width: 22, height: 5)
    /// Hover in: a lively little spring; hover out: a calmer one.
    static let hoverInAnimation: Animation = .spring(response: 0.32, dampingFraction: 0.55, blendDuration: 0)
    static let hoverOutAnimation: Animation = .spring(response: 0.30, dampingFraction: 0.85, blendDuration: 0)
    /// Margin around the swollen closed notch kept inside the small closed window.
    static let closedCanvasMargin = CGSize(width: 16, height: 8)

    /// Spring used when the panel expands out of the notch.
    static let openAnimation: Animation = .spring(response: 0.42, dampingFraction: 0.78, blendDuration: 0)
    /// Spring used when the panel collapses back into the notch.
    static let closeAnimation: Animation = .spring(response: 0.30, dampingFraction: 0.92, blendDuration: 0)
    /// Content fades in after the shape has mostly expanded.
    static let contentInAnimation: Animation = .easeOut(duration: 0.20).delay(0.16)
    static let contentOutAnimation: Animation = .easeOut(duration: 0.12)
    /// Reduce Motion: plain, quick crossfades instead of springs / blur / scale.
    static let reducedMotionAnimation: Animation = .easeOut(duration: 0.15)
    @MainActor static var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    @MainActor static var effectiveOpen: Animation { reduceMotion ? reducedMotionAnimation : openAnimation }
    @MainActor static var effectiveClose: Animation { reduceMotion ? reducedMotionAnimation : closeAnimation }
    @MainActor static var effectiveContentIn: Animation { reduceMotion ? reducedMotionAnimation : contentInAnimation }
    @MainActor static var effectiveContentOut: Animation { reduceMotion ? reducedMotionAnimation : contentOutAnimation }

    /// Total time before the window is ordered out after a close request.
    static let closeDuration: TimeInterval = 0.36
}
