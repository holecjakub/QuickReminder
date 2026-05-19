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
                Color.white.opacity(0.5),
                style: StrokeStyle(lineWidth: 1.5, dash: [2.5, 2.5])
            )
            .frame(width: 20, height: 20)
    }
}
