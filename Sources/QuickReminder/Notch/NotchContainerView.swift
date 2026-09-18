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

            QuickReminderView(
                notchBandHeight: state.notchBandHeight,
                saveNamespace: saveNamespace,
                isSaving: state.isSaving
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
            if state.isSaving {
                SavedCheckView()
                    .matchedGeometryEffect(id: "save", in: saveNamespace)
                    .frame(width: state.savedSize.width, height: state.savedSize.height, alignment: .trailing)
                    .padding(.trailing, (NotchLayout.savedExtension - NotchLayout.savedBadgeSize) / 2 + NotchLayout.closedTopRadius / 2)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: NotchLayout.canvasSize.width, height: NotchLayout.canvasSize.height, alignment: .top)
    }
}
