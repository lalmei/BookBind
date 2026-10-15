import SwiftUI

private func mm(_ value: Double) -> String {
    String(format: "%.1f", value)
}

// MARK: - Case & boards

/// Flat covering-material layout: boards, joints, spine stiffener, turn-ins, and corner cuts.
struct CaseBlueprint: View {
    let plan: CalculatorMath.CasePlan

    var body: some View {
        BlueprintCanvas(
            title: "Case layout",
            extent: CGSize(width: plan.coverWidth, height: plan.coverHeight),
            margin: 64
        ) { context, s in
            let t = plan.turnIn
            let j = plan.jointGap
            let bw = plan.boardWidth
            let bh = plan.boardHeight
            let sw = plan.spineWidth
            let w = plan.coverWidth
            let h = plan.coverHeight
            // Corner cut sits `cornerCutOffset` off each board corner along the diagonal.
            let c = max(0, min(t * 2 - plan.cornerCutOffset * 2.squareRoot(), min(w, h) / 2))

            // Covering material with mitred corners.
            var material = Path()
            material.addLines([
                s.point(c, 0), s.point(w - c, 0), s.point(w, c), s.point(w, h - c),
                s.point(w - c, h), s.point(c, h), s.point(0, h - c), s.point(0, c)
            ])
            material.closeSubpath()
            context.fill(material, with: .color(BlueprintStyle.fill))
            context.stroke(material, with: .color(BlueprintStyle.ink), style: BlueprintStyle.outline)
            if c > 0 {
                for (a, b) in [
                    (s.point(c, 0), s.point(0, c)), (s.point(w - c, 0), s.point(w, c)),
                    (s.point(w, h - c), s.point(w - c, h)), (s.point(c, h), s.point(0, h - c))
                ] {
                    context.line(a, b, color: BlueprintStyle.cut, style: BlueprintStyle.cutLine)
                }
            }

            // Turn-in fold.
            context.strokeRect(s.rect(t, t, w - 2 * t, h - 2 * t), color: BlueprintStyle.dimension, style: BlueprintStyle.fold)

            // Boards and spine stiffener.
            let front = s.rect(t + bw + 2 * j + sw, t, bw, bh)
            let back = s.rect(t, t, bw, bh)
            let spine = s.rect(t + bw + j, t, sw, bh)
            for r in [back, front, spine] {
                context.fill(Path(r), with: .color(BlueprintStyle.boardFill))
                context.strokeRect(r, color: BlueprintStyle.ink)
            }
            context.label("BACK BOARD", at: CGPoint(x: back.midX, y: back.midY), color: BlueprintStyle.ink)
            context.label("FRONT BOARD", at: CGPoint(x: front.midX, y: front.midY), color: BlueprintStyle.ink)
            if spine.width > 12 {
                context.label("SPINE", at: CGPoint(x: spine.midX, y: spine.midY), color: BlueprintStyle.ink, size: 9, rotation: .degrees(-90))
            }

            // Overall size.
            context.dimension(from: s.point(0, 0), to: s.point(w, 0), offset: 24, text: "\(mm(w)) material", color: BlueprintStyle.cut)
            context.dimension(from: s.point(0, h), to: s.point(0, 0), offset: 24, text: "\(mm(h))", color: BlueprintStyle.cut)

            // Components along the bottom.
            let bottom = h - t
            let row1 = -(CGFloat(t) * s.scale + 16)
            context.dimension(from: s.point(t, bottom), to: s.point(t + bw, bottom), offset: row1, text: mm(bw))
            context.dimension(from: s.point(t + bw + j, bottom), to: s.point(t + bw + j + sw, bottom), offset: row1, text: mm(sw))
            context.dimension(from: s.point(t + bw + 2 * j + sw, bottom), to: s.point(t + 2 * bw + 2 * j + sw, bottom), offset: row1, text: mm(bw))
            context.dimension(from: s.point(t + bw, bottom), to: s.point(t + bw + j, bottom), offset: row1 - 18, text: "joint \(mm(j))")

            // Board height and turn-in on the right.
            let right = w - t
            let side = -(CGFloat(t) * s.scale + 16)
            context.dimension(from: s.point(right, t + bh), to: s.point(right, t), offset: side, text: mm(bh))
            context.dimension(from: s.point(w, t), to: s.point(w, 0), offset: -16, text: "turn-in \(mm(t))")
        }
    }
}

// MARK: - Signatures

/// Schematic cross-section of one signature (showing why inner sheets creep) beside the
/// book block's signature count, with padding blanks hatched.
struct SignatureBlueprint: View {
    let plan: CalculatorMath.SignaturePlan
    let sheetsPerSignature: Int

    var body: some View {
        BlueprintCanvas(
            title: "Signature section",
            extent: CGSize(width: 220, height: 120),
            margin: 48,
            note: "SCHEMATIC · NOT TO SCALE"
        ) { context, s in
            drawCrossSection(&context, s)
            drawBlock(&context, s)
        }
    }

    private func drawCrossSection(_ context: inout GraphicsContext, _ s: BlueprintSpace) {
        let drawn = min(max(1, sheetsPerSignature), 12)
        let gap = 5.0
        let mid = 60.0
        let outerRadius = Double(drawn) * gap / 2
        let center = 6 + outerRadius
        // Every sheet is the same length; tighter inner folds leave longer arms → creep.
        let sheetLength = .pi * outerRadius + 2 * 72

        var foreEdges: [Double] = []
        for i in 0..<drawn {
            let r = Double(drawn - i) * gap / 2
            let arm = (sheetLength - .pi * r) / 2
            let fore = center + arm
            foreEdges.append(fore)
            var path = Path()
            path.move(to: s.point(fore, mid - r))
            path.addLine(to: s.point(center, mid - r))
            path.addArc(
                center: s.point(center, mid),
                radius: CGFloat(r) * s.scale,
                startAngle: .degrees(-90),
                endAngle: .degrees(90),
                clockwise: true
            )
            path.addLine(to: s.point(fore, mid + r))
            let isInner = i == drawn - 1 && drawn > 1
            context.stroke(path, with: .color(isInner ? BlueprintStyle.cut : BlueprintStyle.ink), style: BlueprintStyle.outline)
        }

        guard let outer = foreEdges.first, let inner = foreEdges.last else { return }
        let top = mid - outerRadius
        context.line(s.point(outer, top - 14), s.point(outer, mid + outerRadius + 14), color: BlueprintStyle.dimension, style: BlueprintStyle.fold)
        context.label("TRIM", at: s.point(outer, mid + outerRadius + 16), anchor: .top, size: 9)
        context.label("FOLD", at: s.point(center - outerRadius - 2, mid), anchor: .trailing, size: 9)
        if drawn > 1 {
            context.dimension(
                from: s.point(outer, top),
                to: s.point(inner, top),
                offset: 22,
                text: String(format: "creep %.2f mm · %.1f pt", plan.creepMM, plan.creepPoints),
                color: BlueprintStyle.cut
            )
        }
        if sheetsPerSignature > drawn {
            context.label("showing \(drawn) of \(sheetsPerSignature) sheets", at: s.point(6, mid + outerRadius + 16), anchor: .topLeading, size: 9)
        }
    }

    private func drawBlock(_ context: inout GraphicsContext, _ s: BlueprintSpace) {
        let originX = 150.0
        let blockW = 66.0
        let blockH = 80.0
        let top = 20.0
        let count = max(0, plan.signatureCount)
        guard count > 0 else {
            context.label("No pages", at: s.point(originX + blockW / 2, 60))
            return
        }
        let slab = blockW / Double(count)
        for i in 0..<count {
            let r = s.rect(originX + Double(i) * slab, top, slab, blockH)
            context.fill(Path(r), with: .color(BlueprintStyle.boardFill))
            context.strokeRect(r, color: BlueprintStyle.ink, style: slab * Double(s.scale) < 4 ? BlueprintStyle.thin : BlueprintStyle.outline)
        }
        if plan.blankPages > 0 {
            let fraction = Double(plan.blankPages) / Double(plan.pagesPerSignature)
            let last = s.rect(originX + Double(count - 1) * slab, top + blockH * (1 - fraction), slab, blockH * fraction)
            context.hatch(last, color: BlueprintStyle.cut, spacing: 4)
        }
        context.dimension(
            from: s.point(originX, top + blockH),
            to: s.point(originX + blockW, top + blockH),
            offset: -16,
            text: "\(count) × \(plan.pagesPerSignature) pp"
        )
        if plan.blankPages > 0 {
            context.label("+\(plan.blankPages) blank", at: s.point(originX + blockW, top - 4), anchor: .bottomTrailing, color: BlueprintStyle.cut)
        }
        context.label("BOOK BLOCK", at: s.point(originX, top - 4), anchor: .bottomLeading, color: BlueprintStyle.ink, size: 9)
    }
}

// MARK: - Sewing stations

/// Signature spine fold with station holes and chained dimensions from the head.
struct SewingBlueprint: View {
    let plan: CalculatorMath.SewingPlan
    let spineHeight: Double

    var body: some View {
        let depth = max(30, spineHeight * 0.16)
        BlueprintCanvas(
            title: "Sewing stations",
            extent: CGSize(width: spineHeight, height: depth),
            margin: 64
        ) { context, s in
            let strip = s.rect(0, 0, spineHeight, depth)
            context.fill(Path(strip), with: .color(BlueprintStyle.fill))
            context.strokeRect(strip, color: BlueprintStyle.ink)
            let fold = depth / 2
            context.line(s.point(0, fold), s.point(spineHeight, fold), color: BlueprintStyle.dimension, style: BlueprintStyle.fold)
            context.label("HEAD", at: s.point(0, -2), anchor: .bottomLeading, color: BlueprintStyle.ink, size: 9)
            context.label("TAIL", at: s.point(spineHeight, -2), anchor: .bottomTrailing, color: BlueprintStyle.ink, size: 9)
            context.label("FOLD", at: s.point(spineHeight + 2, fold), anchor: .leading, size: 9)

            let radius = max(2.5, 0.8 * s.scale)
            for (index, x) in plan.stations.enumerated() {
                let isKettle = index == 0 || index == plan.stations.count - 1
                let center = s.point(x, fold)
                let hole = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
                context.fill(hole, with: .color(isKettle ? BlueprintStyle.cut : BlueprintStyle.ink))
                context.label(isKettle ? "K" : "\(index)", at: CGPoint(x: center.x, y: center.y - radius - 3), anchor: .bottom, color: isKettle ? BlueprintStyle.cut : BlueprintStyle.ink, size: 9)
            }

            // Chained dimensions from the head, so each hole can be marked with a ruler.
            let marks = [0] + plan.stations + [spineHeight]
            for (a, b) in zip(marks, marks.dropFirst()) where b - a > 0.01 {
                let showsText = CGFloat(b - a) * s.scale > 26
                context.dimension(from: s.point(a, depth), to: s.point(b, depth), offset: -16, text: showsText ? mm(b - a) : "")
            }
            context.dimension(from: s.point(0, 0), to: s.point(spineHeight, 0), offset: 24, text: "\(mm(spineHeight)) spine", color: BlueprintStyle.cut)
        }
    }
}

// MARK: - Sheet yield

/// Parent sheet with grain direction, the grain-correct folio grid, and hatched waste.
struct YieldBlueprint: View {
    let plan: CalculatorMath.YieldPlan
    let parentWidth: Double
    let parentHeight: Double
    let grainAlongHeight: Bool

    var body: some View {
        BlueprintCanvas(
            title: "Parent sheet yield",
            extent: CGSize(width: parentWidth, height: parentHeight),
            margin: 60
        ) { context, s in
            let sheet = s.rect(0, 0, parentWidth, parentHeight)
            context.fill(Path(sheet), with: .color(BlueprintStyle.fill))

            // Grain texture.
            var grain = Path()
            let step = 12.0
            if grainAlongHeight {
                var x = step
                while x < parentWidth {
                    grain.move(to: s.point(x, 0)); grain.addLine(to: s.point(x, parentHeight)); x += step
                }
            } else {
                var y = step
                while y < parentHeight {
                    grain.move(to: s.point(0, y)); grain.addLine(to: s.point(parentWidth, y)); y += step
                }
            }
            context.stroke(grain, with: .color(BlueprintStyle.ink.opacity(0.16)), lineWidth: 0.6)

            let pw = plan.rotated ? plan.folioHeight : plan.folioWidth
            let ph = plan.rotated ? plan.folioWidth : plan.folioHeight
            let usedW = Double(plan.columns) * pw
            let usedH = Double(plan.rows) * ph

            // Waste strips.
            let wasteRight = s.rect(usedW, 0, parentWidth - usedW, parentHeight)
            let wasteBottom = s.rect(0, usedH, usedW, parentHeight - usedH)
            for waste in [wasteRight, wasteBottom] {
                context.fill(Path(waste), with: .color(ArtisanTheme.canvasBackground.opacity(0.55)))
                context.hatch(waste, color: BlueprintStyle.dimension.opacity(0.7), spacing: 7)
            }
            let largestWaste = [wasteRight, wasteBottom].max { $0.width * $0.height < $1.width * $1.height }
            if let largestWaste, largestWaste.width > 60, largestWaste.height > 24 {
                let tag = CGRect(x: largestWaste.midX - 26, y: largestWaste.midY - 9, width: 52, height: 18)
                context.fill(Path(tag), with: .color(ArtisanTheme.canvasBackground))
                context.label("WASTE", at: CGPoint(x: tag.midX, y: tag.midY), size: 9)
            }

            for row in 0..<plan.rows {
                for column in 0..<plan.columns {
                    let x = Double(column) * pw
                    let y = Double(row) * ph
                    let folio = s.rect(x, y, pw, ph)
                    context.fill(Path(folio), with: .color(BlueprintStyle.boardFill.opacity(0.6)))
                    context.strokeRect(folio, color: BlueprintStyle.ink)
                    // The fold runs with the grain.
                    if plan.rotated {
                        context.line(s.point(x, y + ph / 2), s.point(x + pw, y + ph / 2), color: BlueprintStyle.dimension, style: BlueprintStyle.fold)
                    } else {
                        context.line(s.point(x + pw / 2, y), s.point(x + pw / 2, y + ph), color: BlueprintStyle.dimension, style: BlueprintStyle.fold)
                    }
                }
            }
            context.strokeRect(sheet, color: BlueprintStyle.ink)

            if plan.perSheet == 0 {
                context.label("FOLIO DOES NOT FIT WITH THE GRAIN", at: CGPoint(x: sheet.midX, y: sheet.midY), color: BlueprintStyle.cut, size: 11)
            } else {
                // Folio size along the grid's bottom-left and right edges, clear of the folios.
                context.dimension(from: s.point(0, usedH), to: s.point(pw, usedH), offset: -14, text: "folio \(mm(pw))", color: BlueprintStyle.ink)
                context.dimension(from: s.point(usedW, ph), to: s.point(usedW, 0), offset: -14, text: mm(ph), color: BlueprintStyle.ink)
            }

            context.dimension(from: s.point(0, 0), to: s.point(parentWidth, 0), offset: 22, text: mm(parentWidth), color: BlueprintStyle.cut)
            context.dimension(from: s.point(0, parentHeight), to: s.point(0, 0), offset: 22, text: mm(parentHeight), color: BlueprintStyle.cut)
            context.label(
                grainAlongHeight ? "GRAIN ↕" : "GRAIN ↔",
                at: s.point(parentWidth, parentHeight + 2),
                anchor: .topTrailing,
                color: BlueprintStyle.ink,
                size: 9
            )
        }
    }
}

// MARK: - Paper reference

/// Common text and cover weights with caliper, PPI, and bond, highlighting the current GSM.
struct PaperReferenceTable: View {
    let currentGSM: Double

    private let rows: [(gsm: Double, use: String)] = [
        (60, "Thin text, bibles"),
        (70, "Light text"),
        (80, "Standard text"),
        (90, "Premium text"),
        (100, "Heavy text, endpapers"),
        (120, "Endpapers, light covers"),
        (170, "Covers, flyleaves"),
        (250, "Card covers")
    ]

    var body: some View {
        ScrollView {
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 0) {
                GridRow {
                    header("GSM"); header("Bond lb"); header("Caliper"); header("PPI"); header("Typical use")
                }
                .padding(.bottom, 8)
                ForEach(rows, id: \.gsm) { row in
                    let isCurrent = abs(row.gsm - currentGSM) < 5
                    GridRow {
                        value(String(format: "%.0f", row.gsm), isCurrent)
                        value(String(format: "%.0f", BindingMath.gsmToBondLb(row.gsm)), isCurrent)
                        value(String(format: "%.3f mm", CalculatorMath.sheetCaliper(gsm: row.gsm)), isCurrent)
                        value(String(format: "%.0f", CalculatorMath.pagesPerInch(gsm: row.gsm)), isCurrent)
                        Text(row.use)
                            .foregroundStyle(isCurrent ? ArtisanTheme.textPrimary : ArtisanTheme.textSecondary)
                    }
                    .padding(.vertical, 7)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(ArtisanTheme.separator).frame(height: 0.5)
                    }
                }
            }
            .padding(32)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)

            Text("Caliper is estimated for uncoated book paper (≈ GSM ÷ 800). Measure a stack of your stock with calipers for exact spines.")
                .font(.caption)
                .foregroundStyle(ArtisanTheme.textSecondary)
                .padding(.horizontal, 32)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(ArtisanTheme.canvasBackground)
    }

    private func header(_ title: String) -> some View {
        WorkbenchInspectorChrome.SectionTitle(title)
    }

    private func value(_ text: String, _ highlighted: Bool) -> some View {
        Text(text)
            .font(ArtisanTheme.technicalFont)
            .monospacedDigit()
            .foregroundStyle(highlighted ? ArtisanTheme.secondary : ArtisanTheme.textPrimary)
    }
}
