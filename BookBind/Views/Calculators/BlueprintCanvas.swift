import SwiftUI

/// Line work vocabulary shared by every calculator drawing, so a fold, a cut, and a
/// dimension look the same on the case layout, the sewing template, and the sheet yield.
enum BlueprintStyle {
    static let ink = ArtisanTheme.primary
    static let dimension = ArtisanTheme.textSecondary
    /// Cuts and the one number the binder is here for.
    static let cut = ArtisanTheme.secondary
    static let fill = ArtisanTheme.primary.opacity(0.07)
    static let boardFill = ArtisanTheme.primary.opacity(0.11)
    static let grid = ArtisanTheme.primary.opacity(0.05)

    static let outline = StrokeStyle(lineWidth: 1.25)
    static let fold = StrokeStyle(lineWidth: 0.9, dash: [5, 3])
    static let cutLine = StrokeStyle(lineWidth: 1.1, dash: [7, 2, 1.5, 2])
    static let thin = StrokeStyle(lineWidth: 0.6)

    static func labelFont(_ size: CGFloat = 10) -> Font {
        .system(size: size, weight: .medium, design: .monospaced)
    }
}

/// Maps drawing millimeters onto the canvas, fitted and centered with room for dimensions.
struct BlueprintSpace {
    let scale: CGFloat
    let origin: CGPoint

    init(extent: CGSize, in size: CGSize, margin: CGFloat) {
        let availW = max(1, size.width - 2 * margin)
        let availH = max(1, size.height - 2 * margin)
        let w = max(extent.width, 1)
        let h = max(extent.height, 1)
        scale = min(availW / w, availH / h)
        origin = CGPoint(
            x: (size.width - w * scale) / 2,
            y: (size.height - h * scale) / 2
        )
    }

    func point(_ x: Double, _ y: Double) -> CGPoint {
        CGPoint(x: origin.x + CGFloat(x) * scale, y: origin.y + CGFloat(y) * scale)
    }

    func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> CGRect {
        CGRect(origin: point(x, y), size: CGSize(width: CGFloat(w) * scale, height: CGFloat(h) * scale))
    }

    /// Nearest "1 : N" ratio for the title block (screen points are 1/72 in).
    var ratioLabel: String {
        let mmPerPoint = 25.4 / 72
        let ratio = 1 / (Double(scale) * mmPerPoint)
        if ratio <= 1.05 { return "1 : 1" }
        return "1 : \(Int(ratio.rounded()))"
    }
}

extension GraphicsContext {
    func strokeRect(_ rect: CGRect, color: Color, style: StrokeStyle = BlueprintStyle.outline) {
        stroke(Path(rect), with: .color(color), style: style)
    }

    func line(_ a: CGPoint, _ b: CGPoint, color: Color, style: StrokeStyle) {
        var path = Path()
        path.move(to: a)
        path.addLine(to: b)
        stroke(path, with: .color(color), style: style)
    }

    /// Diagonal hatching clipped to `rect` — used for waste and board cores.
    func hatch(_ rect: CGRect, color: Color, spacing: CGFloat = 6) {
        guard rect.width > 0, rect.height > 0 else { return }
        var copy = self
        copy.clip(to: Path(rect))
        var path = Path()
        var x = rect.minX - rect.height
        while x < rect.maxX {
            path.move(to: CGPoint(x: x, y: rect.maxY))
            path.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
            x += spacing
        }
        copy.stroke(path, with: .color(color), style: BlueprintStyle.thin)
    }

    func label(
        _ string: String,
        at point: CGPoint,
        anchor: UnitPoint = .center,
        color: Color = BlueprintStyle.dimension,
        size: CGFloat = 10,
        rotation: Angle = .zero
    ) {
        let text = Text(string).font(BlueprintStyle.labelFont(size)).foregroundColor(color)
        if rotation == .zero {
            draw(text, at: point, anchor: anchor)
        } else {
            var copy = self
            copy.translateBy(x: point.x, y: point.y)
            copy.rotate(by: rotation)
            copy.draw(text, at: .zero, anchor: anchor)
        }
    }

    /// Architectural dimension: extension lines, a dimension line `offset` points to the
    /// left of a→b, 45° slash ticks, and the value centered above the line.
    func dimension(
        from a: CGPoint,
        to b: CGPoint,
        offset: CGFloat,
        text: String,
        color: Color = BlueprintStyle.dimension
    ) {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let length = max(0.001, hypot(dx, dy))
        let d = CGPoint(x: dx / length, y: dy / length)
        let n = CGPoint(x: d.y, y: -d.x)
        let sign: CGFloat = offset >= 0 ? 1 : -1

        func shifted(_ p: CGPoint, _ k: CGFloat) -> CGPoint {
            CGPoint(x: p.x + n.x * k, y: p.y + n.y * k)
        }

        let a2 = shifted(a, offset)
        let b2 = shifted(b, offset)
        line(shifted(a, sign * 3), shifted(a, offset + sign * 4), color: color.opacity(0.7), style: BlueprintStyle.thin)
        line(shifted(b, sign * 3), shifted(b, offset + sign * 4), color: color.opacity(0.7), style: BlueprintStyle.thin)
        line(a2, b2, color: color, style: BlueprintStyle.thin)

        let tick = CGPoint(x: (d.x + n.x) * 3.5, y: (d.y + n.y) * 3.5)
        for p in [a2, b2] {
            line(
                CGPoint(x: p.x - tick.x, y: p.y - tick.y),
                CGPoint(x: p.x + tick.x, y: p.y + tick.y),
                color: color,
                style: StrokeStyle(lineWidth: 1)
            )
        }

        var angle = atan2(dy, dx)
        // Keep text upright: read left-to-right or bottom-to-top.
        if angle >= .pi / 2 - 0.001 || angle < -.pi / 2 - 0.001 { angle += .pi }
        if angle > .pi { angle -= 2 * .pi }
        let mid = CGPoint(x: (a2.x + b2.x) / 2, y: (a2.y + b2.y) / 2)
        let upright = CGPoint(x: -sin(angle), y: cos(angle))
        let labelPoint = CGPoint(x: mid.x - upright.x * 2, y: mid.y - upright.y * 2)
        label(text, at: labelPoint, anchor: .bottom, color: color, rotation: .radians(Double(angle)))
    }
}

/// Drafting sheet: canvas backdrop, 10 mm grid in drawing space, and a title block.
struct BlueprintCanvas: View {
    let title: String
    /// Drawing extent in millimeters.
    let extent: CGSize
    var margin: CGFloat = 56
    var note: String?
    let draw: (inout GraphicsContext, BlueprintSpace) -> Void

    var body: some View {
        Canvas { context, size in
            let space = BlueprintSpace(extent: extent, in: size, margin: margin)
            drawGrid(context, size: size, space: space)
            draw(&context, space)
            drawTitleBlock(context, size: size, space: space)
        }
        .background(ArtisanTheme.canvasBackground)
        .accessibilityLabel(title)
    }

    private func drawGrid(_ context: GraphicsContext, size: CGSize, space: BlueprintSpace) {
        let step = 10 * space.scale
        guard step >= 4 else { return }
        var path = Path()
        var x = space.origin.x.truncatingRemainder(dividingBy: step)
        while x < size.width {
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: size.height))
            x += step
        }
        var y = space.origin.y.truncatingRemainder(dividingBy: step)
        while y < size.height {
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
            y += step
        }
        context.stroke(path, with: .color(BlueprintStyle.grid), lineWidth: 0.5)
    }

    private func drawTitleBlock(_ context: GraphicsContext, size: CGSize, space: BlueprintSpace) {
        let box = CGRect(x: size.width - 196, y: size.height - 46, width: 180, height: 32)
        guard box.minX > 0, box.minY > 0 else { return }
        context.fill(Path(box), with: .color(ArtisanTheme.canvasBackground))
        context.strokeRect(box, color: BlueprintStyle.ink.opacity(0.5), style: BlueprintStyle.thin)
        context.line(
            CGPoint(x: box.minX, y: box.midY),
            CGPoint(x: box.maxX, y: box.midY),
            color: BlueprintStyle.ink.opacity(0.35),
            style: BlueprintStyle.thin
        )
        context.label(title.uppercased(), at: CGPoint(x: box.minX + 8, y: box.minY + 8), anchor: .topLeading, color: BlueprintStyle.ink, size: 9)
        context.label(
            note ?? "MM · SCALE \(space.ratioLabel)",
            at: CGPoint(x: box.minX + 8, y: box.midY + 4),
            anchor: .topLeading,
            size: 9
        )
    }
}
