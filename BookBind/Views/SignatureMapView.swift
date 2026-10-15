import SwiftUI

struct SignatureMapView: View {
    let map: SignatureMap

    private var signatureIndices: [Int] {
        Array(Set(map.sides.map(\.signatureIndex))).sorted()
    }

    private var isSheetLayout: Bool {
        !map.plan.impositionScheme.usesFolioImpose
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(isSheetLayout ? "Sheet map" : "Signature map")
                    .font(.headline)
                Spacer()
                Text("\(map.plan.sheetCount) sheets · pages are 1-based book order")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            if map.sides.isEmpty {
                Text("Add PDFs to see sheet layout.")
                    .foregroundStyle(.secondary)
                    .padding(14)
                Spacer()
            } else {
                List {
                    ForEach(signatureIndices, id: \.self) { sig in
                        Section(isSheetLayout ? "Sheet \(sig)" : "Signature \(sig)") {
                            ForEach(map.sides(forSignature: sig)) { side in
                                HStack {
                                    if isSheetLayout {
                                        Text(side.gridLabel != nil ? "Row" : "Sheet \(side.sheetIndex)")
                                            .foregroundStyle(.secondary)
                                            .frame(width: 48, alignment: .leading)
                                    } else {
                                        Text("Sheet \(side.sheetIndex) \(side.face.rawValue)")
                                            .foregroundStyle(.secondary)
                                            .frame(width: 120, alignment: .leading)
                                    }
                                    Text(side.label)
                                        .font(.body.monospacedDigit())
                                    Spacer()
                                }
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }

            Divider()
            Text(map.plan.impositionScheme.printInstruction)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(12)
        }
        .frame(minWidth: 360, minHeight: 420)
    }
}

/// Fold / cut instructions for the current imposition scheme and template.
struct FoldGuideView: View {
    let guide: FoldCutGuide

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(guide.title)
                        .font(.headline)
                    Text(guide.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(guide.overview)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    FoldGuideDiagramView(diagram: guide.diagram)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)

                    if let caption = guide.pageMapCaption {
                        Text(caption)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Steps")
                            .font(.subheadline.weight(.semibold))
                        ForEach(guide.steps) { step in
                            HStack(alignment: .top, spacing: 10) {
                                Text("\(step.id)")
                                    .font(.caption.weight(.bold).monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .frame(width: 18, alignment: .trailing)
                                    .padding(.top, 2)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(step.title)
                                        .font(.body.weight(.medium))
                                    Text(step.detail)
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }

                    if !guide.tips.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Tips")
                                .font(.subheadline.weight(.semibold))
                            ForEach(Array(guide.tips.enumerated()), id: \.offset) { _, tip in
                                HStack(alignment: .top, spacing: 8) {
                                    Text("·")
                                        .foregroundStyle(.tertiary)
                                    Text(tip)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                }
                .padding(14)
            }
        }
        .frame(minWidth: 420, minHeight: 520)
    }
}

private struct FoldGuideDiagramView: View {
    let diagram: FoldCutGuide.Diagram

    var body: some View {
        switch diagram {
        case .none:
            EmptyView()
        case .miniZine8(let template):
            miniZine8Diagram(template)
        case .miniZine16(let template):
            miniZine16Diagram(template)
        case .accordion(let count):
            accordionDiagram(count)
        case .halfFold:
            halfFoldDiagram
        case .folio:
            folioDiagram
        }
    }

    private var foldColor: Color { Color(nsColor: .secondaryLabelColor).opacity(0.55) }
    private var cutColor: Color { Color(nsColor: .labelColor).opacity(0.55) }
    private var panelFill: Color { Color(nsColor: .controlBackgroundColor) }

    private func miniZine8Diagram(_ template: MiniZine8Template) -> some View {
        let top = template.topRowPages.map { $0 + 1 }
        let bottom = template.bottomRowPages.map { $0 + 1 }
        return VStack(alignment: .leading, spacing: 6) {
            Text("Sheet layout (print side up)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ZStack {
                VStack(spacing: 0) {
                    row(pages: top, upsideDown: true)
                    row(pages: bottom, upsideDown: false)
                }
                // Center slit across middle two columns
                GeometryReader { geo in
                    Path { path in
                        let y = geo.size.height / 2
                        let x0 = geo.size.width * 0.25
                        let x1 = geo.size.width * 0.75
                        path.move(to: CGPoint(x: x0, y: y))
                        path.addLine(to: CGPoint(x: x1, y: y))
                    }
                    .stroke(cutColor, style: StrokeStyle(lineWidth: 2))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(foldColor, lineWidth: 1)
            }
            .frame(height: 120)

            legend
        }
    }

    private func miniZine16Diagram(_ template: MiniZine16Template) -> some View {
        let layout = ImpositionService.miniZine16Layout(template: template)
        return VStack(alignment: .leading, spacing: 6) {
            Text("Sheet layout (4×4) · \(template.rawValue)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ZStack {
                VStack(spacing: 0) {
                    // Display top→bottom = PDF rows high→low.
                    ForEach((0..<4).reversed(), id: \.self) { row in
                        HStack(spacing: 0) {
                            ForEach(0..<4, id: \.self) { col in
                                let cell = layout.cells.first { $0.column == col && $0.row == row }
                                let label = cell?.pageIndex.map { String($0 + 1) } ?? "—"
                                let upsideDown = (cell?.rotationDegrees ?? 0) != 0
                                panelCell(label, upsideDown: upsideDown)
                            }
                        }
                    }
                }
                GeometryReader { geo in
                    let w = geo.size.width
                    let h = geo.size.height
                    Path { path in
                        switch template {
                        case .crossCut:
                            path.move(to: CGPoint(x: w * 0.25, y: h * 0.5))
                            path.addLine(to: CGPoint(x: w * 0.75, y: h * 0.5))
                            path.move(to: CGPoint(x: w * 0.5, y: h * 0.25))
                            path.addLine(to: CGPoint(x: w * 0.5, y: h * 0.75))
                        case .horizontalSlits:
                            path.move(to: CGPoint(x: w * 0.25, y: h * 0.25))
                            path.addLine(to: CGPoint(x: w * 0.75, y: h * 0.25))
                            path.move(to: CGPoint(x: w * 0.25, y: h * 0.75))
                            path.addLine(to: CGPoint(x: w * 0.75, y: h * 0.75))
                        }
                    }
                    .stroke(cutColor, style: StrokeStyle(lineWidth: 2))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(foldColor, lineWidth: 1)
            }
            .frame(height: 160)
            legend
        }
    }

    private func accordionDiagram(_ count: Int) -> some View {
        let panels = max(3, min(12, count))
        return VStack(alignment: .leading, spacing: 6) {
            Text("Accordion strip")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 0) {
                ForEach(1...panels, id: \.self) { page in
                    panelCell("\(page)", upsideDown: false)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(foldColor, lineWidth: 1)
            }
            .frame(height: 64)
            Text("Dashed gray = fold · no cut")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private var halfFoldDiagram: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Printer spread (2-up)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 0) {
                panelCell("L", upsideDown: false)
                panelCell("R", upsideDown: false)
            }
            .overlay {
                Rectangle()
                    .fill(foldColor)
                    .frame(width: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(foldColor, lineWidth: 1)
            }
            .frame(height: 80)
            Text("Fold on the center line · stitch through the spine · no cut")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private var folioDiagram: some View {
        halfFoldDiagram
    }

    private var legend: some View {
        HStack(spacing: 14) {
            Label("Fold (dashed on print)", systemImage: "line.diagonal")
            Label("Cut (solid gray on print)", systemImage: "scissors")
        }
        .font(.caption2)
        .foregroundStyle(.tertiary)
        .labelStyle(.titleAndIcon)
    }

    private func row(pages: [Int], upsideDown: Bool) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(pages.enumerated()), id: \.offset) { _, page in
                panelCell("\(page)", upsideDown: upsideDown)
            }
        }
    }

    private func panelCell(_ label: String, upsideDown: Bool) -> some View {
        ZStack {
            panelFill
            Text(label)
                .font(.caption.weight(.semibold).monospacedDigit())
                .rotationEffect(.degrees(upsideDown ? 180 : 0))
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            Rectangle().stroke(foldColor.opacity(0.5), lineWidth: 0.5)
        }
    }
}
