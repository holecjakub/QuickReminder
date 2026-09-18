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

    /// Size of the collapsed silhouette. Slightly larger than the physical notch so
    /// anti-aliased edges never peek out around the bezel.
    @Published var closedSize: CGSize = CGSize(width: 221, height: 38)
    /// Size of the fully expanded panel.
    @Published var openSize: CGSize = NotchLayout.openSize

    /// Height of the band occupied by the physical notch / menu bar at the top of the panel.
    var notchBandHeight: CGFloat { closedSize.height }

    var currentSize: CGSize { isOpen ? openSize : closedSize }
}

/// Layout constants for the expanded quick-reminder panel.
enum NotchLayout {
    static let openSize = CGSize(width: 600, height: 214)
    static let closedTopRadius: CGFloat = NotchShape.Radius.closedTop
    static let closedBottomRadius: CGFloat = NotchShape.Radius.closedBottom
    static let openTopRadius: CGFloat = NotchShape.Radius.openTop
    static let openBottomRadius: CGFloat = NotchShape.Radius.openBottom

    /// Spring used when the panel expands out of the notch.
    static let openAnimation: Animation = .spring(response: 0.42, dampingFraction: 0.78, blendDuration: 0)
    /// Spring used when the panel collapses back into the notch.
    static let closeAnimation: Animation = .spring(response: 0.30, dampingFraction: 0.92, blendDuration: 0)
    /// Content fades in after the shape has mostly expanded.
    static let contentInAnimation: Animation = .easeOut(duration: 0.20).delay(0.16)
    static let contentOutAnimation: Animation = .easeOut(duration: 0.12)
    /// Reduce Motion: plain, quick crossfades instead of springs / blur / scale.
    static let reducedMotionAnimation: Animation = .easeOut(duration: 0.15)
    static var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    static var effectiveOpen: Animation { reduceMotion ? reducedMotionAnimation : openAnimation }
    static var effectiveClose: Animation { reduceMotion ? reducedMotionAnimation : closeAnimation }
    static var effectiveContentIn: Animation { reduceMotion ? reducedMotionAnimation : contentInAnimation }
    static var effectiveContentOut: Animation { reduceMotion ? reducedMotionAnimation : contentOutAnimation }

    /// Total time before the window is ordered out after a close request.
    static let closeDuration: TimeInterval = 0.36
}
