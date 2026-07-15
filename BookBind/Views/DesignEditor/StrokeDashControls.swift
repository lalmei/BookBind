import SwiftUI

/// Stroke style chips + Dash / Gap scales (Figma / Affinity-style).
struct StrokeDashControls: View {
    let selected: CoverStrokeStyle
    let strokeColor: Color
    let dashLengthScale: Double
    let dashGapScale: Double
    var strokeWidthMM: Double = 0.8
    var onStyleChange: (CoverStrokeStyle) -> Void
    var onDashLengthChange: (Double) -> Void
    var onDashGapChange: (Double) -> Void
    var onEditingChanged: ((Bool) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 36), spacing: 4)], spacing: 4) {
                ForEach(CoverStrokeStyle.allCases) { style in
                    Button {
                        onStyleChange(style)
                    } label: {
                        CoverStrokeStylePreview(style: style, color: strokeColor)
                            .frame(height: 22)
                            .padding(.horizontal, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(selected == style
                                          ? Color.accentColor.opacity(0.18)
                                          : Color(nsColor: .controlBackgroundColor))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .strokeBorder(
                                        selected == style ? Color.accentColor : Color.clear,
                                        lineWidth: 1
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                    .help(style.help)
                }
            }

            if selected.allowsDashScaling {
                HStack(spacing: 8) {
                    Text("Dash")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: 28, alignment: .leading)
                    CoverInspectorNumberField(
                        value: dashLengthScale,
                        fractionDigits: 2,
                        width: 48,
                        onCommit: { onDashLengthChange(min(4, max(0.25, $0))) },
                        onEditingChanged: onEditingChanged
                    )
                    Text("Gap")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: 28, alignment: .leading)
                    CoverInspectorNumberField(
                        value: dashGapScale,
                        fractionDigits: 2,
                        width: 48,
                        onCommit: { onDashGapChange(min(4, max(0.25, $0))) },
                        onEditingChanged: onEditingChanged
                    )
                }
                .help("Dash length and gap relative to the default pattern (1 = default)")
            }
        }
    }
}

/// Mini swatch for stroke-style pickers.
struct CoverStrokeStylePreview: View {
    let style: CoverStrokeStyle
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            let rect = CGRect(x: 4, y: proxy.size.height / 2, width: max(8, proxy.size.width - 8), height: 0)
            ZStack {
                if style.isDoubleStroke {
                    Path { path in
                        path.move(to: CGPoint(x: rect.minX, y: rect.minY - 2))
                        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY - 2))
                    }
                    .stroke(color, lineWidth: 1)
                    Path { path in
                        path.move(to: CGPoint(x: rect.minX, y: rect.minY + 2))
                        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + 2))
                    }
                    .stroke(color, lineWidth: 1)
                } else {
                    Path { path in
                        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
                        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
                    }
                    .stroke(
                        color,
                        style: StrokeStyle(
                            lineWidth: 1.5,
                            lineCap: style.usesRoundCap ? .round : .butt,
                            dash: style.dashPatternMM(strokeWidthMM: 0.8).map { CGFloat($0 * 2) }
                        )
                    )
                    if style.drawsOrnamentMarks {
                        ForEach(ornamentMarkPositions(width: rect.width), id: \.self) { x in
                            Circle()
                                .fill(color)
                                .frame(width: 3, height: 3)
                                .position(x: rect.minX + x, y: rect.minY)
                        }
                    }
                }
            }
        }
    }

    private func ornamentMarkPositions(width: CGFloat) -> [CGFloat] {
        stride(from: CGFloat(10), through: max(10, width - 4), by: 14).map { $0 }
    }
}
