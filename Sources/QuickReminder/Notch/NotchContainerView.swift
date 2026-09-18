import SwiftUI

/// Draws the black notch silhouette and hosts the quick-reminder UI inside it.
/// The silhouette animates between the physical notch size and the open panel size;
/// the content fades/blurs in slightly after the shape leads.
struct NotchContainerView: View {
    @EnvironmentObject private var state: NotchState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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

            QuickReminderView()
                .frame(width: state.openSize.width, height: state.openSize.height)
                .opacity(state.contentVisible ? 1 : 0)
                .blur(radius: state.contentVisible || reduceMotion ? 0 : 8)
                .scaleEffect(state.contentVisible || reduceMotion ? 1 : 0.94, anchor: .top)
                .allowsHitTesting(state.isOpen)
                .accessibilityHidden(!state.isOpen)
                // Never let content pixels spill outside the black body mid-animation.
                .mask(
                    silhouette
                        .frame(width: state.currentSize.width, height: state.currentSize.height)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                )
        }
        .frame(width: state.openSize.width, height: state.openSize.height, alignment: .top)
    }
}
