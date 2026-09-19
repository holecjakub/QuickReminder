import SwiftUI

/// Blue badge with a checkmark that draws itself in, then gives a small bounce.
/// Used as the landing target of the save button during the "saved" phase.
struct SavedCheckView: View {
    var size: CGFloat = NotchLayout.savedBadgeSize
    var accent: Color = Theme.accent
    @State private var progress: CGFloat = 0
    @State private var bounce: CGFloat = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle().fill(accent)
            CheckmarkShape()
                .trim(from: 0, to: progress)
                .stroke(Color.white, style: StrokeStyle(lineWidth: size * 0.11, lineCap: .round, lineJoin: .round))
                .padding(size * 0.27)
        }
        .frame(width: size, height: size)
        .scaleEffect(bounce)
        .onAppear {
            if reduceMotion {
                progress = 1
                return
            }
            // Wait for the flight into the notch, then draw the tick and pop.
            withAnimation(.easeOut(duration: 0.28).delay(0.32)) { progress = 1 }
            withAnimation(.spring(response: 0.28, dampingFraction: 0.45).delay(0.55)) { bounce = 1.18 }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7).delay(0.72)) { bounce = 1 }
        }
        .accessibilityLabel("Saved")
    }
}

/// Checkmark drawn as a single open path so it can be trimmed left-to-right.
struct CheckmarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY + rect.height * 0.05))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.38, y: rect.maxY - rect.height * 0.08))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.12))
        return path
    }
}
