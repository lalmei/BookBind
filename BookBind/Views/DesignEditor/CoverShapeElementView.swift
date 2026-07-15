import SwiftUI

/// Renders a shape element with fill + border brush (dash pattern / double rule / ornate stamps).
struct CoverShapeElementView: View {
    let shapeType: CoverShapeType
    let strokeStyle: CoverStrokeStyle
    var ornamentPattern: CoverOrnamentPattern = .dots
    let strokeWidthPx: CGFloat
    let dashPx: [CGFloat]
    let isFilled: Bool
    let strokeColor: Color
    var fillColor: Color?

    init(
        shapeType: CoverShapeType,
        strokeStyle: CoverStrokeStyle,
        ornamentPattern: CoverOrnamentPattern = .dots,
        strokeWidthPx: CGFloat,
        dashPx: [CGFloat],
        isFilled: Bool,
        color: Color,
        fillColor: Color? = nil
    ) {
        self.shapeType = shapeType
        self.strokeStyle = strokeStyle
        self.ornamentPattern = ornamentPattern
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
                if strokeWidthPx > 0 {
                    path.stroke(
                        strokeColor,
                        style: StrokeStyle(
                            lineWidth: strokeWidthPx,
                            lineCap: strokeUsesRoundCap ? .round : .butt,
                            dash: dashPx
                        )
                    )
                    if strokeStyle.isDoubleStroke {
                        innerPath(in: rect)
                            .stroke(strokeColor, style: StrokeStyle(lineWidth: strokeWidthPx))
                    }
                    if strokeStyle.drawsOrnamentMarks, ornamentPattern.drawsStamps {
                        ornamentMarks(in: rect)
                    }
                }
            }
        }
    }

    private var strokeUsesRoundCap: Bool {
        strokeStyle == .ornament && ornamentPattern.usesRoundCap
    }

    @ViewBuilder
    private func ornamentMarks(in rect: CGRect) -> some View {
        let spacing = max(8, strokeWidthPx * 7)
        let points = Self.samplePoints(along: shapeType, in: rect, spacing: spacing)
        ForEach(Array(points.enumerated()), id: \.offset) { _, point in
            CoverOrnamentStampShape(
                pattern: ornamentPattern,
                color: strokeColor,
                size: strokeWidthPx * 1.6
            )
            .position(point)
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

    /// Evenly spaced points along the stroke path for ornament stamps.
    static func samplePoints(
        along type: CoverShapeType,
        in rect: CGRect,
        spacing: CGFloat
    ) -> [CGPoint] {
        switch type {
        case .line:
            let length = max(1, rect.width)
            let count = max(2, Int(length / spacing))
            return (1...count).map { index in
                let t = CGFloat(index) / CGFloat(count + 1)
                return CGPoint(x: rect.minX + rect.width * t, y: rect.midY)
            }
        case .rectangle:
            let peri = max(1, 2 * (rect.width + rect.height))
            let count = max(4, Int(peri / spacing))
            return (0..<count).map { index in
                pointOnRectPerimeter(rect, t: CGFloat(index) / CGFloat(count))
            }
        case .ellipse:
            let peri = .pi * (3 * (rect.width + rect.height)
                - sqrt((3 * rect.width + rect.height) * (rect.width + 3 * rect.height)))
            let count = max(6, Int(max(1, peri) / spacing))
            return (0..<count).map { index in
                let angle = CGFloat(index) / CGFloat(count) * 2 * .pi
                return CGPoint(
                    x: rect.midX + cos(angle) * rect.width / 2,
                    y: rect.midY + sin(angle) * rect.height / 2
                )
            }
        }
    }

    private static func pointOnRectPerimeter(_ rect: CGRect, t: CGFloat) -> CGPoint {
        let peri = max(0.001, 2 * (rect.width + rect.height))
        var d = ((t.truncatingRemainder(dividingBy: 1) + 1).truncatingRemainder(dividingBy: 1)) * peri
        if d <= rect.width {
            return CGPoint(x: rect.minX + d, y: rect.minY)
        }
        d -= rect.width
        if d <= rect.height {
            return CGPoint(x: rect.maxX, y: rect.minY + d)
        }
        d -= rect.height
        if d <= rect.width {
            return CGPoint(x: rect.maxX - d, y: rect.maxY)
        }
        d -= rect.width
        return CGPoint(x: rect.minX, y: rect.maxY - d)
    }
}
