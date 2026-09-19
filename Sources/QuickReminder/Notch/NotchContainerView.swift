import SwiftUI

/// Draws the black notch silhouette and hosts the quick-reminder UI inside it.
/// The silhouette animates between the physical notch size and the open panel size;
/// the content fades/blurs in slightly after the shape leads.
struct NotchContainerView: View {
    @EnvironmentObject private var state: NotchState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Shared between the save button and the saved badge so the ✓ flies between them.
    @Namespace private var saveNamespace

    private var silhouette: NotchShape {
        NotchShape(
            topCornerRadius: state.isOpen ? NotchLayout.openTopRadius : NotchLayout.closedTopRadius,
            bottomCornerRadius: state.isOpen ? NotchLayout.openBottomRadius : NotchLayout.closedBottomRadius
        )
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.clear.allowsHitTesting(false)

            silhouette
                .fill(Color.black)
                .frame(width: state.currentSize.width, height: state.currentSize.height)
                .contentShape(silhouette)
                .onHover { PanelController.shared.notchHoverChanged($0) }
                // Open on mouse-down (like the old global-monitor path), not on mouse-up.
                .gesture(DragGesture(minimumDistance: 0).onChanged { _ in PanelController.shared.notchTapped() })

            QuickReminderView(
                notchBandHeight: state.notchBandHeight,
                saveNamespace: saveNamespace,
                saveButtonYielded: state.savedBadgeShown
            )
                .frame(width: state.openSize.width, height: state.openSize.height)
                .opacity(state.contentVisible ? 1 : 0)
                .blur(radius: state.contentVisible || reduceMotion ? 0 : 8)
                .scaleEffect(state.contentVisible || reduceMotion ? 1 : 0.94, anchor: .top)
                .allowsHitTesting(state.isOpen)
                .accessibilityHidden(!state.isOpen)
                // Never let content pixels spill outside the black body mid-animation.
                // Once settled the content sits fully inside the body, so the mask is dropped.
                .mask(
                    Group {
                        if state.isSettled {
                            Rectangle()
                        } else {
                            silhouette
                                .frame(width: state.currentSize.width, height: state.currentSize.height)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        }
                    }
                )

            // "Saved" badge: lands in the right-hand extension of the collapsed notch.
            if state.savedBadgeShown {
                SavedCheckView()
                    // Fades out in place, a little ahead of the notch shrinking back around it.
                    .opacity(state.isSaving ? 1 : 0)
                    .animation(.easeOut(duration: 0.16), value: state.isSaving)
                    .matchedGeometryEffect(id: "save", in: saveNamespace)
                    // Centre of the right-hand extension: the top fillet eats the full radius,
                    // then half of the remaining room. Padding goes on the badge, frame outside.
                    .padding(.trailing, NotchLayout.closedTopRadius + (NotchLayout.savedExtension - NotchLayout.savedBadgeSize) / 2)
                    .frame(width: state.savedSize.width, height: state.savedSize.height, alignment: .trailing)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: state.canvasSize.width, height: state.canvasSize.height, alignment: .top)
    }
}
