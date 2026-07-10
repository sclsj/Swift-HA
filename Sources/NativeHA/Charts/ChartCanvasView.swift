import SwiftUI

struct ChartCanvasView<Overlay: View>: View {
    var minimumHeight: CGFloat
    var render: (inout GraphicsContext, CGSize) -> Void
    var overlay: () -> Overlay

    init(
        minimumHeight: CGFloat = 200,
        render: @escaping (inout GraphicsContext, CGSize) -> Void,
        @ViewBuilder overlay: @escaping () -> Overlay
    ) {
        self.minimumHeight = minimumHeight
        self.render = render
        self.overlay = overlay
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Canvas(opaque: false, colorMode: .nonLinear, rendersAsynchronously: true) { context, size in
                render(&context, size)
            }
            overlay()
        }
        .frame(minHeight: minimumHeight)
    }
}

extension ChartCanvasView where Overlay == EmptyView {
    init(
        minimumHeight: CGFloat = 200,
        render: @escaping (inout GraphicsContext, CGSize) -> Void
    ) {
        self.minimumHeight = minimumHeight
        self.render = render
        self.overlay = { EmptyView() }
    }
}
