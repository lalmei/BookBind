import SwiftUI

/// Renders a shape element with fill + border brush (dash pattern / double rule).
struct CoverShapeElementView: View {
    let shapeType: CoverShapeType
    let strokeStyle: CoverStrokeStyle
    let strokeWidthPx: CGFloat
    let dashPx: [CGFloat]
    let isFilled: Bool
    let strokeColor: Color
    var fillColor: Color?

    init(
        shapeType: CoverShapeType,
        strokeStyle: CoverStrokeStyle,
        strokeWidthPx: CGFloat,
        dashPx: [CGFloat],
        isFilled: Bool,
        color: Color,
        fillColor: Color? = nil
    ) {
        self.shapeType = shapeType
        self.strokeStyle = strokeStyle
        self.strokeWidthPx = strokeWidthPx
        self.dashPx = dashPx
        self.isFilled = isFilled
        self.strokeColor = color
        self.fillColor = fillColor
    }

    var body: some View {
        GeometryReader { proxy in
            let rect = CGRect(origin: .zero, size: proxy.size)
                .insetBy(dx: strokeWidthPx / 2, dy: strokeWidthPx / 2)
            let path = Self.path(shapeType, in: rect)
            ZStack {
                if isFilled, shapeType != .line {
                    path.fill((fillColor ?? strokeColor).opacity(0.9))
                }
                path.stroke(
                    strokeColor,
                    style: StrokeStyle(
                        lineWidth: strokeWidthPx,
                        lineCap: strokeStyle.usesRoundCap ? .round : .butt,
                        dash: dashPx
                    )
                )
                if strokeStyle.isDoubleStroke {
                    innerPath(in: rect)
                        .stroke(strokeColor, style: StrokeStyle(lineWidth: strokeWidthPx))
                }
                if strokeStyle.drawsOrnamentMarks {
                    ornamentMarks(in: rect)
                }
            }
        }
    }

    @ViewBuilder
    private func ornamentMarks(in rect: CGRect) -> some View {
        let spacing = max(6, strokeWidthPx * 8)
        let count = max(2, Int(rect.width / spacing))
        ForEach(0..<count, id: \.self) { index in
            let t = CGFloat(index + 1) / CGFloat(count + 1)
            let x = rect.minX + rect.width * t
            let y = rect.midY
            Circle()
                .fill(strokeColor)
                .frame(width: strokeWidthPx * 1.2, height: strokeWidthPx * 1.2)
                .position(x: x, y: y)
        }
    }

    private func innerPath(in rect: CGRect) -> Path {
        let inset = strokeWidthPx * 2.5
        switch shapeType {
        case .rectangle, .ellipse:
            return Self.path(shapeType, in: rect.insetBy(dx: inset, dy: inset))
        case .line:
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: rect.midY + inset))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY + inset))
            return path
        }
    }

    static func path(_ type: CoverShapeType, in rect: CGRect) -> Path {
        switch type {
        case .rectangle:
            return Path(rect)
        case .ellipse:
            return Path(ellipseIn: rect)
        case .line:
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            return path
        }
    }
}
