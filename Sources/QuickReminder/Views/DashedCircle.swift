import SwiftUI

struct DashedCircle: Shape {
    func path(in rect: CGRect) -> Path {
        Path(ellipseIn: rect)
    }
}

struct DashedCircleView: View {
    var body: some View {
        DashedCircle()
            .stroke(
                Color.secondary.opacity(0.6),
                style: StrokeStyle(lineWidth: 1.5, dash: [3.5, 3])
            )
            .frame(width: 24, height: 24)
    }
}
