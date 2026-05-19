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
                Color.white.opacity(0.55),
                style: StrokeStyle(lineWidth: 1.5, dash: [3, 2.5])
            )
            .frame(width: 22, height: 22)
    }
}
