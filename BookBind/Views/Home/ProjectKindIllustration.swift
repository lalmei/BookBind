import SwiftUI

/// Mini technical drawing of a project kind.
///
/// Folds show the printed sheet (page order, upside-down panels, dashed folds, gold cuts) and
/// what it folds into; books show a head-on cross-section of how the block and cover are built.
struct ProjectKindIllustration: View {
    enum Detail {
        /// Card thumbnail: shapes only.
        case thumbnail
        /// Preview pane: page numbers, labels, and the folded result.
        case full
    }

    let kind: ProjectKind
    var detail: Detail = .full
    var stock: StockSheet = .letter

    private var isFull: Bool { detail == .full }

    var body: some View {
        Canvas { context, size in
            switch kind {
            case .miniZine8: drawMiniZine8(&context, size)
            case .miniZine16: drawMiniZine16(&context, size)
            case .halfFoldBooklet: drawHalfFold(&context, size)
            case .accordion: drawAccordion(&context, size)
            case .caseBound, .sectionSewn, .perfectBound, .coptic, .pamphlet:
                drawBookSection(&context, size)
            }
        }
        .accessibilityLabel("\(kind.title) diagram")
    }

    // MARK: - Fold layouts

    private struct Cell {
        var column: Int
        var row: Int
        var label: String
        var upsideDown: Bool
        var isCover = false
    }

    /// Splits the canvas: sheet on the left, folded result on the right (full detail only).
    private func layoutRects(_ size: CGSize, sheetAspect: CGFloat) -> (sheet: CGRect, result: CGRect?) {
        let pad: CGFloat = isFull ? 18 : 6
        let resultWidth: CGFloat = isFull ? size.width * 0.24 : 0
        let area = CGRect(x: pad, y: pad, width: size.width - 2 * pad - resultWidth, height: size.height - 2 * pad - (isFull ? 14 : 0))
        var w = area.width
        var h = w / sheetAspect
        if h > area.height {
            h = area.height
            w = h * sheetAspect
        }
        let sheet = CGRect(x: area.minX + (area.width - w) / 2, y: area.minY + (area.height - h) / 2, width: w, height: h)
        let result = isFull ? CGRect(x: area.maxX + 12, y: area.minY, width: resultWidth - 12, height: area.height) : nil
        return (sheet, result)
    }

    private func drawSheet(
        _ context: inout GraphicsContext,
        in sheet: CGRect,
        columns: Int,
        rows: Int,
        cells: [Cell],
        cuts: [(CGPoint, CGPoint)]
    ) {
        let cw = sheet.width / CGFloat(columns)
        let ch = sheet.height / CGFloat(rows)
        context.fill(Path(sheet), with: .color(BlueprintStyle.fill))

        for cell in cells {
            let r = CGRect(x: sheet.minX + CGFloat(cell.column) * cw, y: sheet.minY + CGFloat(cell.row) * ch, width: cw, height: ch)
            if cell.isCover {
                context.fill(Path(r), with: .color(BlueprintStyle.cut.opacity(0.14)))
            }
            if isFull {
                context.label(
                    cell.label,
                    at: CGPoint(x: r.midX, y: r.midY),
                    color: cell.isCover ? BlueprintStyle.cut : BlueprintStyle.ink,
                    size: min(13, ch * 0.28),
                    rotation: cell.upsideDown ? .degrees(180) : .zero
                )
            }
        }

        // Every panel edge is a fold; cuts are drawn over them.
        for c in 1..<columns {
            let x = sheet.minX + CGFloat(c) * cw
            context.line(CGPoint(x: x, y: sheet.minY), CGPoint(x: x, y: sheet.maxY), color: BlueprintStyle.dimension, style: BlueprintStyle.fold)
        }
        for r in 1..<max(rows, 1) {
            let y = sheet.minY + CGFloat(r) * ch
            context.line(CGPoint(x: sheet.minX, y: y), CGPoint(x: sheet.maxX, y: y), color: BlueprintStyle.dimension, style: BlueprintStyle.fold)
        }
        for (a, b) in cuts {
            let p1 = CGPoint(x: sheet.minX + a.x * sheet.width, y: sheet.minY + a.y * sheet.height)
            let p2 = CGPoint(x: sheet.minX + b.x * sheet.width, y: sheet.minY + b.y * sheet.height)
            context.line(p1, p2, color: BlueprintStyle.cut, style: StrokeStyle(lineWidth: isFull ? 2.2 : 1.6, lineCap: .round))
        }
        context.strokeRect(sheet, color: BlueprintStyle.ink, style: StrokeStyle(lineWidth: isFull ? 1.25 : 1))

        if isFull {
            context.label(
                "\(stock.rawValue.uppercased()) · PRINT SIDE UP",
                at: CGPoint(x: sheet.minX, y: sheet.minY - 4),
                anchor: .bottomLeading,
                size: 8
            )
            context.label(
                cuts.isEmpty ? "- - fold" : "- - fold   ── cut",
                at: CGPoint(x: sheet.midX, y: sheet.maxY + 12),
                anchor: .center,
                color: cuts.isEmpty ? BlueprintStyle.dimension : BlueprintStyle.cut,
                size: 9
            )
        }
    }

    private var stockAspect: CGFloat { CGFloat(stock.longMM / stock.shortMM) }

    private func drawMiniZine8(_ context: inout GraphicsContext, _ size: CGSize) {
        let template = MiniZine8Template.classicNested
        var cells: [Cell] = []
        for (column, page) in template.topRowPages.enumerated() {
            cells.append(Cell(column: column, row: 0, label: "\(page + 1)", upsideDown: true, isCover: page == 0))
        }
        for (column, page) in template.bottomRowPages.enumerated() {
            cells.append(Cell(column: column, row: 1, label: "\(page + 1)", upsideDown: false, isCover: page == 0))
        }
        let rects = layoutRects(size, sheetAspect: stockAspect)
        drawSheet(&context, in: rects.sheet, columns: 4, rows: 2, cells: cells, cuts: [
            (CGPoint(x: 0.25, y: 0.5), CGPoint(x: 0.75, y: 0.5))
        ])
        if let result = rects.result {
            drawBooklet(&context, in: result, pageAspect: (stock.longMM / 4) / (stock.shortMM / 2), caption: "8 pp booklet", staples: false)
        }
    }

    private func drawMiniZine16(_ context: inout GraphicsContext, _ size: CGSize) {
        let layout = ImpositionService.miniZine16Layout(template: .crossCut)
        let cells = layout.cells.map { cell in
            Cell(
                column: cell.column,
                // Layout rows count bottom→top (PDF space); the drawing counts top→bottom.
                row: layout.rows - 1 - cell.row,
                label: cell.pageIndex.map { "\($0 + 1)" } ?? "",
                upsideDown: cell.rotationDegrees != 0,
                isCover: cell.pageIndex == 0
            )
        }
        let rects = layoutRects(size, sheetAspect: stockAspect)
        drawSheet(&context, in: rects.sheet, columns: 4, rows: 4, cells: cells, cuts: [
            (CGPoint(x: 0.25, y: 0.5), CGPoint(x: 0.75, y: 0.5)),
            (CGPoint(x: 0.5, y: 0.25), CGPoint(x: 0.5, y: 0.75))
        ])
        if let result = rects.result {
            drawBooklet(&context, in: result, pageAspect: (stock.longMM / 4) / (stock.shortMM / 4), caption: "16 pp booklet", staples: false)
        }
    }

    private func drawHalfFold(_ context: inout GraphicsContext, _ size: CGSize) {
        let rects = layoutRects(size, sheetAspect: stockAspect)
        drawSheet(&context, in: rects.sheet, columns: 2, rows: 1, cells: [
            Cell(column: 0, row: 0, label: "8", upsideDown: false),
            Cell(column: 1, row: 0, label: "1", upsideDown: false, isCover: true)
        ], cuts: [])
        if let result = rects.result {
            drawBooklet(&context, in: result, pageAspect: (stock.longMM / 2) / stock.shortMM, caption: "nest + staple", staples: true)
        }
    }

    private func drawAccordion(_ context: inout GraphicsContext, _ size: CGSize) {
        let panels = 6
        let cells = (0..<panels).map { Cell(column: $0, row: 0, label: "\($0 + 1)", upsideDown: false, isCover: $0 == 0) }
        let rects = layoutRects(size, sheetAspect: stockAspect)
        drawSheet(&context, in: rects.sheet, columns: panels, rows: 1, cells: cells, cuts: [])
        guard let result = rects.result else { return }

        // Zig-zag profile seen from above, plus "mountain / valley" cue.
        let segments = panels
        let width = result.width * 0.9
        let step = width / CGFloat(segments)
        let depth = min(result.height * 0.18, step * 0.9)
        let originX = result.minX + (result.width - width) / 2
        let midY = result.midY
        var path = Path()
        path.move(to: CGPoint(x: originX, y: midY))
        for i in 1...segments {
            path.addLine(to: CGPoint(x: originX + CGFloat(i) * step, y: midY + (i.isMultiple(of: 2) ? 0 : depth)))
        }
        context.stroke(path, with: .color(BlueprintStyle.ink), style: StrokeStyle(lineWidth: 1.4, lineJoin: .round))
        context.label("folded strip", at: CGPoint(x: result.midX, y: midY + depth + 16), size: 9)
    }

    /// Small closed booklet: cover with page 1, spine on the left, optional staples.
    private func drawBooklet(_ context: inout GraphicsContext, in area: CGRect, pageAspect: Double, caption: String, staples: Bool) {
        let maxW = area.width * 0.7
        let maxH = area.height * 0.62
        var w = maxW
        var h = w / CGFloat(pageAspect)
        if h > maxH {
            h = maxH
            w = h * CGFloat(pageAspect)
        }
        let cover = CGRect(x: area.midX - w / 2, y: area.midY - h / 2 - 6, width: w, height: h)
        // Page edges peeking out behind the cover.
        for i in (1...2).reversed() {
            let offset = CGFloat(i) * 2
            context.strokeRect(cover.offsetBy(dx: offset, dy: offset), color: BlueprintStyle.ink.opacity(0.4), style: BlueprintStyle.thin)
        }
        context.fill(Path(cover), with: .color(BlueprintStyle.cut.opacity(0.14)))
        context.strokeRect(cover, color: BlueprintStyle.ink)
        context.line(
            CGPoint(x: cover.minX, y: cover.minY),
            CGPoint(x: cover.minX, y: cover.maxY),
            color: BlueprintStyle.ink,
            style: StrokeStyle(lineWidth: 2.4)
        )
        context.label("1", at: CGPoint(x: cover.midX, y: cover.midY), color: BlueprintStyle.cut, size: 12)
        if staples {
            for y in [cover.minY + h * 0.25, cover.minY + h * 0.75] {
                context.line(CGPoint(x: cover.minX - 2, y: y - 5), CGPoint(x: cover.minX - 2, y: y + 5), color: BlueprintStyle.cut, style: StrokeStyle(lineWidth: 2, lineCap: .round))
            }
        }
        context.label("→", at: CGPoint(x: area.minX - 2, y: cover.midY), size: 12)
        context.label(caption, at: CGPoint(x: area.midX, y: cover.maxY + 14), size: 9)
    }

    // MARK: - Book cross-sections

    /// Head-on cross-section: spine on the left, fore-edge on the right, 100 × 64 units.
    private func drawBookSection(_ context: inout GraphicsContext, _ size: CGSize) {
        // Full detail leaves room left and right of the 100-unit drawing for callouts.
        let inset = isFull ? 46.0 : 0
        let space = BlueprintSpace(extent: CGSize(width: 100 + inset * 2, height: 64), in: size, margin: isFull ? 18 : 6)
        let lineWidth: CGFloat = isFull ? 1.2 : 0.9
        let ink = StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
        let thread = StrokeStyle(lineWidth: isFull ? 1.6 : 1.1, lineCap: .round)

        func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> CGRect { space.rect(x + inset, y, w, h) }
        func p(_ x: Double, _ y: Double) -> CGPoint { space.point(x + inset, y) }

        /// One signature: `sheets` nested U-folds with the fold at `foldX`.
        func signature(foldX: Double, centerY: Double, sheets: Int, gap: Double, foreX: Double) {
            for i in 0..<sheets {
                let r = Double(sheets - i) * gap / 2
                var path = Path()
                path.move(to: p(foreX, centerY - r))
                path.addLine(to: p(foldX + r, centerY - r))
                path.addArc(center: p(foldX + r, centerY), radius: CGFloat(r) * space.scale, startAngle: .degrees(-90), endAngle: .degrees(90), clockwise: true)
                path.addLine(to: p(foreX, centerY + r))
                context.stroke(path, with: .color(BlueprintStyle.ink), style: ink)
            }
        }

        func signatureStack(count: Int, top: Double, bottom: Double, foldX: Double, foreX: Double, sheets: Int = 3) -> [Double] {
            let pitch = (bottom - top) / Double(count)
            let gap = pitch * 0.9 / Double(sheets)
            return (0..<count).map { i in
                let centerY = top + pitch * (Double(i) + 0.5)
                signature(foldX: foldX, centerY: centerY, sheets: sheets, gap: gap, foreX: foreX)
                return centerY
            }
        }

        func board(_ r: CGRect) {
            context.fill(Path(r), with: .color(BlueprintStyle.boardFill))
            context.stroke(Path(r), with: .color(BlueprintStyle.ink), style: ink)
        }

        func callout(_ text: String, at point: CGPoint, anchor: UnitPoint = .leading, color: Color = BlueprintStyle.dimension) {
            guard isFull else { return }
            context.label(text, at: point, anchor: anchor, color: color, size: 9)
        }

        switch kind {
        case .caseBound:
            board(rect(16, 2, 82, 5))
            board(rect(16, 57, 82, 5))
            // Covering wraps both boards and the spine with turn-ins inside.
            var cover = Path()
            cover.move(to: p(99, 1))
            cover.addLine(to: p(10, 1))
            cover.addQuadCurve(to: p(10, 63), control: p(-4, 32))
            cover.addLine(to: p(99, 63))
            context.stroke(cover, with: .color(BlueprintStyle.ink), style: ink)
            let centers = signatureStack(count: 4, top: 10, bottom: 54, foldX: 8, foreX: 96)
            for y in centers {
                context.line(p(7, y - 2), p(7, y + 2), color: BlueprintStyle.cut, style: thread)
            }
            callout("boards", at: p(99, 4.5))
            callout("sewn signatures", at: p(99, 32))
            callout("spine", at: p(1, 32), anchor: .trailing)
        case .sectionSewn:
            var cover = Path()
            cover.move(to: p(97, 4))
            cover.addLine(to: p(10, 4))
            cover.addQuadCurve(to: p(10, 60), control: p(0, 32))
            cover.addLine(to: p(97, 60))
            context.stroke(cover, with: .color(BlueprintStyle.ink), style: ink)
            let centers = signatureStack(count: 4, top: 8, bottom: 56, foldX: 7, foreX: 95)
            for y in centers {
                context.line(p(6, y - 2), p(6, y + 2), color: BlueprintStyle.cut, style: thread)
            }
            callout("soft cover", at: p(98, 4))
            callout("thread through folds", at: p(98, 32), color: BlueprintStyle.cut)
        case .perfectBound:
            var cover = Path()
            cover.move(to: p(97, 4))
            cover.addLine(to: p(6, 4))
            cover.addLine(to: p(6, 60))
            cover.addLine(to: p(97, 60))
            context.stroke(cover, with: .color(BlueprintStyle.ink), style: ink)
            let leaves = isFull ? 16 : 9
            for i in 0..<leaves {
                let y = 8 + Double(i) * (48 / Double(leaves - 1))
                context.line(p(9, y), p(95, y), color: BlueprintStyle.ink.opacity(0.85), style: ink)
            }
            context.fill(Path(rect(6.5, 6, 2.6, 52)), with: .color(BlueprintStyle.cut.opacity(0.85)))
            callout("glued spine", at: p(12, 62), color: BlueprintStyle.cut)
            callout("single leaves", at: p(98, 32))
        case .coptic:
            board(rect(12, 3, 84, 5))
            board(rect(12, 56, 84, 5))
            let centers = signatureStack(count: 4, top: 12, bottom: 52, foldX: 10, foreX: 93)
            // Chain stitches link each signature to the next and the boards at the spine.
            let anchors = [5.5] + centers + [58.5]
            for (a, b) in zip(anchors, anchors.dropFirst()) {
                var loop = Path()
                loop.move(to: p(10, a))
                loop.addQuadCurve(to: p(10, b), control: p(2, (a + b) / 2))
                context.stroke(loop, with: .color(BlueprintStyle.cut), style: thread)
            }
            callout("chain stitch", at: p(1, 32), anchor: .trailing, color: BlueprintStyle.cut)
            callout("separate boards", at: p(98, 6))
        case .pamphlet:
            signature(foldX: 10, centerY: 32, sheets: isFull ? 6 : 4, gap: 7, foreX: 94)
            // Staple through the fold.
            var staple = Path()
            staple.move(to: p(16, 24))
            staple.addLine(to: p(9, 24))
            staple.addLine(to: p(9, 40))
            staple.addLine(to: p(16, 40))
            context.stroke(staple, with: .color(BlueprintStyle.cut), style: thread)
            callout("one nested signature", at: p(97, 32))
            callout("stitched at fold", at: p(6, 32), anchor: .trailing, color: BlueprintStyle.cut)
        default:
            break
        }

        if isFull {
            context.label("CROSS-SECTION FROM HEAD", at: CGPoint(x: size.width - 10, y: size.height - 8), anchor: .bottomTrailing, size: 8)
        }
    }
}
