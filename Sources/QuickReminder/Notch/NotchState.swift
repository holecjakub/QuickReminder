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
    /// In-notch Set Date: the open panel grown by the scheduling controls / plus the month grid.
    @Published var scheduleSize: CGSize = NotchLayout.openSize(notchBandHeight: NotchLayout.defaultNotchBandHeight, schedule: .controls)
    @Published var scheduleCalendarSize: CGSize = NotchLayout.openSize(notchBandHeight: NotchLayout.defaultNotchBandHeight, schedule: .calendar)
    /// How far the open panel is grown for the in-notch Set Date section (mirrors `NotchMachine.schedule`).
    @Published var schedule: ScheduleExpansion = .none

    /// Height of the band occupied by the physical notch / menu bar at the top of the panel.
    var notchBandHeight: CGFloat { closedSize.height }

    /// The open panel at its current schedule height.
    var panelSize: CGSize { size(for: schedule) }

    func size(for expansion: ScheduleExpansion) -> CGSize {
        switch expansion {
        case .none: return openSize
        case .controls: return scheduleSize
        case .calendar: return scheduleCalendarSize
        }
    }

    var currentSize: CGSize {
        if isSaving { return savedSize }
        if isOpen { return panelSize }
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
    /// Base (100 % text size) open panel width; the height follows from `contentHeight`.
    static let baseOpenWidth: CGFloat = 600
    /// Notch band assumed until the display is known (14"/16" MacBook Pro: 38 pt + 1 pt bleed).
    static let defaultNotchBandHeight: CGFloat = 39

    /// Open panel size for the default notch band (initial state, tests, previews).
    @MainActor static var openSize: CGSize { openSize(notchBandHeight: defaultNotchBandHeight) }

    /// Open panel size at the user's text size: the width grows a little so long titles keep
    /// their room; the height is the notch band (dead zone) plus the content's vertical rhythm,
    /// so the bottom bar always ends exactly `Theme.horizontalPadding` above the body edge and
    /// nothing is ever centred-and-clipped by an undersized frame.
    @MainActor static func openSize(notchBandHeight: CGFloat) -> CGSize {
        let s = textScale
        return CGSize(width: (baseOpenWidth * min(1 + (s - 1) * 0.5, 1.3)).rounded(),
                      height: notchBandHeight + contentHeight(textScale: s))
    }

    /// Open panel size with the in-notch Set Date section at `schedule` (`.none` = the plain panel),
    /// never taller than `maxHeight` (see `maxPanelHeight`) and never shorter than the plain
    /// panel. The plain panel is a fixed top part either way; when clamped, only the section's rows
    /// scroll (between the bottom bar above and the section's own pinned footer).
    @MainActor static func openSize(notchBandHeight: CGFloat, schedule: ScheduleExpansion,
                                    maxHeight: CGFloat = .infinity) -> CGSize {
        let plain = openSize(notchBandHeight: notchBandHeight)
        guard schedule != .none else { return plain }
        let natural = notchBandHeight + scheduleContentHeight(textScale: textScale, calendar: schedule == .calendar)
        return CGSize(width: plain.width, height: max(plain.height, min(natural, maxHeight.rounded(.down))))
    }

    /// Room below the grown panel: the spring's overshoot (`overshootPadding`) plus a little air
    /// above the Dock / the bottom of the screen.
    static let scheduleScreenMargin: CGFloat = overshootPadding + 16

    /// The tallest the open panel may grow on a screen: from the top edge (the panel covers the
    /// menu bar) down to the top of the visible area (above the Dock), minus the margin.
    static func maxPanelHeight(screenFrame: CGRect, visibleFrame: CGRect) -> CGFloat {
        screenFrame.maxY - visibleFrame.minY - scheduleScreenMargin
    }

    /// The bottom of the band whose clicks cancel scheduling: the header, title and notes. The chip
    /// slot and the bottom bar below it keep their own meaning while the section is open (the
    /// calendar button toggles the section, the date chip is a no-op, ✓ saves, see SPEC), and the
    /// section itself is below them.
    @MainActor static func scheduleCancelBandBottom(notchBandHeight: CGFloat, textScale s: CGFloat) -> CGFloat {
        notchBandHeight + topContentHeight(textScale: s)
    }

    /// A click on the header / title / notes while the section is open cancels scheduling, like a
    /// click outside the popover; the click still reaches what it landed on.
    static func clickCancelsSchedule(atY y: CGFloat, bandBottom: CGFloat, schedule: ScheduleExpansion) -> Bool {
        schedule != .none && y < bandBottom
    }

    /// The decision the panel's mouse-down monitor makes, from a top-down point in the hosting
    /// view: only the header / title / notes band cancels — never the chip slot, the bottom bar
    /// (its ✓ must reach `prepareSave` with the edit intact) or the section.
    @MainActor static func clickCancelsSchedule(atY y: CGFloat, notchBandHeight: CGFloat, textScale s: CGFloat,
                                                schedule: ScheduleExpansion) -> Bool {
        clickCancelsSchedule(atY: y, bandBottom: scheduleCancelBandBottom(notchBandHeight: notchBandHeight, textScale: s),
                             schedule: schedule)
    }

    /// While the panel is open the window ignores the mouse when the pointer is outside the black
    /// shape (`panelSize`, open radii; top-down hosting-view point), so the transparent part of the
    /// tall canvas never swallows a click, scroll or hover meant for the app below.
    static func passesMouseThrough(_ point: CGPoint, canvasWidth: CGFloat, panelSize: CGSize) -> Bool {
        !NotchShape.contains(point, canvasWidth: canvasWidth, shapeSize: panelSize,
                             topCornerRadius: openTopRadius, bottomCornerRadius: openBottomRadius)
    }

    /// Vertical rhythm of the open content below the notch band (SPEC §4) at text scale `s`.
    /// Every term has a counterpart in QuickReminderView / HeaderView / InputView / BottomBar;
    /// a change there must be mirrored here (`NotchStateTests.openHeightFollowsTheRhythm`).
    @MainActor static func contentHeight(textScale s: CGFloat) -> CGFloat {
        func sc(_ v: CGFloat) -> CGFloat { (v * s).rounded(.toNearestOrEven) }
        let chipSlot = sc(26)
        let bottomBar = sc(48)                                // ✓ button, taller than the 44 pt pill
        return topContentHeight(textScale: s) + chipSlot + 8 + bottomBar + Theme.horizontalPadding
    }

    /// Header + title/notes: the part of the content the in-notch Set Date section keeps on top.
    @MainActor static func topContentHeight(textScale s: CGFloat) -> CGFloat {
        func sc(_ v: CGFloat) -> CGFloat { (v * s).rounded(.toNearestOrEven) }
        let header = sc(36)                                   // ⓧ hit frame, taller than the 22 pt title
        let input = (PlainTextView.lineHeight(for: sc(19)) + 2)
            + 1                                               // row spacing
            + (PlainTextView.lineHeight(for: sc(15)) + 2)
        return 8 + header + 10 + input
    }

    /// In-notch Set Date: the whole plain panel stays as it is (`contentHeight`, ending 20 pt below
    /// the bottom bar) and the section is appended below it, ending `Theme.horizontalPadding` above
    /// the grown body edge. `ScheduleNotchSection` lays itself out from the same metrics;
    /// `NotchStateTests.scheduleHeightFollowsTheRhythm` pins the sum.
    @MainActor static func scheduleContentHeight(textScale s: CGFloat, calendar: Bool) -> CGFloat {
        contentHeight(textScale: s) + ScheduleMetrics.sectionHeight(textScale: s, calendar: calendar) + Theme.horizontalPadding
    }

    /// Vertical metrics of the in-notch Set Date section, at 100 % text size (scaled like `Theme.s`).
    /// Gaps are fixed points, control heights scale.
    enum ScheduleMetrics {
        // The type field starts right at the section top: the plain panel's 20 pt inset below the
        // bottom bar is the gap above it.
        static let typeField: CGFloat = 36
        static let previewGap: CGFloat = 6
        static let preview: CGFloat = 18
        static let presetsGap: CGFloat = 10
        static let presetRow: CGFloat = 44       // 3 × 2 cards
        static let presetSpacing: CGFloat = 8
        static let dayTimeGap: CGFloat = 12
        static let dayTimeRow: CGFloat = 30
        static let calendarGap: CGFloat = 10
        static let monthHeader: CGFloat = 26
        static let weekdayRow: CGFloat = 18
        static let dayCell: CGFloat = 28         // 6 rows, always: the month never changes the height
        static let dayRowSpacing: CGFloat = 2
        static let footerGap: CGFloat = 14
        static let footer: CGFloat = 36
        /// Concentric with the panel's 32 pt bottom corners at the 20 pt inset (32 − 20).
        static let controlRadius: CGFloat = 12

        @MainActor static func calendarHeight(textScale s: CGFloat) -> CGFloat {
            func sc(_ v: CGFloat) -> CGFloat { (v * s).rounded(.toNearestOrEven) }
            return sc(monthHeader) + sc(weekdayRow) + 6 * sc(dayCell) + 5 * dayRowSpacing
        }

        @MainActor static func sectionHeight(textScale s: CGFloat, calendar: Bool) -> CGFloat {
            func sc(_ v: CGFloat) -> CGFloat { (v * s).rounded(.toNearestOrEven) }
            var height = sc(typeField) + previewGap + sc(preview)
                + presetsGap + 2 * sc(presetRow) + presetSpacing
                + dayTimeGap + sc(dayTimeRow)
            if calendar { height += calendarGap + calendarHeight(textScale: s) }
            return height + footerGap + sc(footer)
        }
    }

    /// Blob growth / shrink for the in-notch Set Date section: the open spring's gooey language,
    /// a touch quicker since it is a step within the panel. Reduce Motion: plain ease.
    static let scheduleAnimation: Animation = .spring(response: 0.38, dampingFraction: 0.8, blendDuration: 0)
    @MainActor static var effectiveSchedule: Animation { reduceMotion ? reducedMotionAnimation : scheduleAnimation }
    /// System text size (System Settings → Accessibility → Display → Text size, or per-app),
    /// relative to the default 13 pt body. Read live so every open reflects the current setting.
    @MainActor static var textScale: CGFloat {
        if let forcedScale { return forcedScale }
        let body = NSFont.preferredFont(forTextStyle: .body).pointSize
        return max(0.85, min(body / 13, 1.6))
    }
    /// `QR_TEXT_SCALE` dev override, read once (the environment cannot change while running).
    private static let forcedScale: CGFloat? = ProcessInfo.processInfo.environment["QR_TEXT_SCALE"]
        .flatMap(Double.init).map { max(0.85, min(CGFloat($0), 1.6)) }

    /// `textScale` as sampled by the controller on every show / screen change; views read this
    /// (via `Theme.s`) so a body evaluation costs nothing, while every open still reflects the
    /// current system setting.
    @MainActor static var cachedTextScale: CGFloat = 1

    @MainActor static func refreshTextScale() {
        cachedTextScale = textScale
    }
    /// Extra room around the open panel so the bouncy spring's ~2 % overshoot is not clipped
    /// by the window edge (notch-research.md: "a bouncy spring overshoots the mask").
    static let overshootPadding: CGFloat = 24
    /// Window / container size: open panel plus overshoot room on the sides and bottom.
    @MainActor static var canvasSize: CGSize { canvasSize(for: openSize) }

    /// The window / canvas while the panel is open, set once per open (`switchToOpenCanvas`; a
    /// display change relays it out) and never changed by Set Date. In notch style it already fits
    /// the tallest schedule state (the calendar, screen-clamped), so growing and shrinking the blob
    /// only animates SwiftUI state: resizing the window mid-spring made AppKit and SwiftUI disagree
    /// for a frame (a blank panel, then the content offset and springing back). The window would
    /// otherwise take every click in its transparent part, so while the panel is open it ignores
    /// the mouse whenever the pointer is outside the black shape (`passesMouseThrough`, driven by
    /// pointer monitors in `PanelController`): those clicks reach the app below, and the global
    /// click monitor closes the panel.
    static func openCanvasSize(openSize: CGSize, tallestScheduleSize: CGSize, style: SetDateStyle) -> CGSize {
        switch style {
        case .notch: return canvasSize(for: CGSize(width: openSize.width, height: max(openSize.height, tallestScheduleSize.height)))
        case .popover: return canvasSize(for: openSize)
        }
    }

    static func canvasSize(for openSize: CGSize) -> CGSize {
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
    /// Pointer must rest on the notch this long before the swell + haptic fire.
    static let hoverDwell: TimeInterval = 0.09
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
