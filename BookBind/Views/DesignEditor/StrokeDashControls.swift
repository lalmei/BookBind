import SwiftUI

/// Stroke style chips (Solid / Double / Ornate) plus ornament pattern picker.
struct StrokeDashControls: View {
    let selected: CoverStrokeStyle
    let ornamentPattern: CoverOrnamentPattern
    let strokeColor: Color
    let dashLengthScale: Double
    let dashGapScale: Double
    var strokeWidthMM: Double = 0.8
    var onStyleChange: (CoverStrokeStyle) -> Void
    var onPatternChange: (CoverOrnamentPattern) -> Void
    var onDashLengthChange: (Double) -> Void
    var onDashGapChange: (Double) -> Void
    var onEditingChanged: ((Bool) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                ForEach(CoverStrokeStyle.allCases) { style in
                    Button {
                        onStyleChange(style)
                    } label: {
                        CoverStrokeStylePreview(
                            style: style,
                            pattern: style == .ornament ? ornamentPattern : .dots,
                            color: strokeColor
                        )
                        .frame(height: 22)
                        .frame(maxWidth: .infinity)
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

            if selected == .ornament {
                Text("Pattern")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 36), spacing: 4)], spacing: 4) {
                    ForEach(CoverOrnamentPattern.allCases) { pattern in
                        Button {
                            onPatternChange(pattern)
                        } label: {
                            CoverOrnamentPatternPreview(pattern: pattern, color: strokeColor)
                                .frame(height: 22)
                                .padding(.horizontal, 4)
                                .background(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(ornamentPattern == pattern
                                              ? Color.accentColor.opacity(0.18)
                                              : Color(nsColor: .controlBackgroundColor))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .strokeBorder(
                                            ornamentPattern == pattern ? Color.accentColor : Color.clear,
                                            lineWidth: 1
                                        )
                                )
                        }
                        .buttonStyle(.plain)
                        .help(pattern.help)
                    }
                }

                if ornamentPattern.allowsDashScaling {
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
}

/// Mini swatch for top-level stroke styles.
struct CoverStrokeStylePreview: View {
    let style: CoverStrokeStyle
    var pattern: CoverOrnamentPattern = .dots
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            let midY = proxy.size.height / 2
            let minX: CGFloat = 4
            let maxX = max(8, proxy.size.width - 4)
            ZStack {
                switch style {
                case .solid:
                    Path { path in
                        path.move(to: CGPoint(x: minX, y: midY))
                        path.addLine(to: CGPoint(x: maxX, y: midY))
                    }
                    .stroke(color, lineWidth: 1.5)
                case .double:
                    Path { path in
                        path.move(to: CGPoint(x: minX, y: midY - 2))
                        path.addLine(to: CGPoint(x: maxX, y: midY - 2))
                    }
                    .stroke(color, lineWidth: 1)
                    Path { path in
                        path.move(to: CGPoint(x: minX, y: midY + 2))
                        path.addLine(to: CGPoint(x: maxX, y: midY + 2))
                    }
                    .stroke(color, lineWidth: 1)
                case .ornament:
                    CoverOrnamentPatternPreview(pattern: pattern, color: color)
                }
            }
        }
    }
}

/// Mini swatch for ornate stamp / dash patterns.
struct CoverOrnamentPatternPreview: View {
    let pattern: CoverOrnamentPattern
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            let midY = proxy.size.height / 2
            let minX: CGFloat = 4
            let maxX = max(8, proxy.size.width - 4)
            ZStack {
                Path { path in
                    path.move(to: CGPoint(x: minX, y: midY))
                    path.addLine(to: CGPoint(x: maxX, y: midY))
                }
                .stroke(
                    color,
                    style: StrokeStyle(
                        lineWidth: 1.25,
                        lineCap: pattern.usesRoundCap ? .round : .butt,
                        dash: pattern.dashPatternMM(strokeWidthMM: 0.8).map { CGFloat($0 * 2) }
                    )
                )

                if pattern.drawsStamps {
                    ForEach(stampPositions(width: maxX - minX), id: \.self) { x in
                        CoverOrnamentStampShape(pattern: pattern, color: color, size: 4)
                            .position(x: minX + x, y: midY)
                    }
                }
            }
        }
    }

    private func stampPositions(width: CGFloat) -> [CGFloat] {
        stride(from: CGFloat(8), through: max(8, width - 4), by: 12).map { $0 }
    }
}

/// Single ornament stamp used in previews and canvas accents.
struct CoverOrnamentStampShape: View {
    let pattern: CoverOrnamentPattern
    let color: Color
    let size: CGFloat

    var body: some View {
        switch pattern {
        case .dots:
            Circle()
                .fill(color)
                .frame(width: size, height: size)
        case .diamonds:
            Rectangle()
                .fill(color)
                .frame(width: size * 0.85, height: size * 0.85)
                .rotationEffect(.degrees(45))
        case .squares:
            Rectangle()
                .fill(color)
                .frame(width: size * 0.9, height: size * 0.9)
        case .crosses:
            ZStack {
                Rectangle()
                    .fill(color)
                    .frame(width: size, height: size * 0.28)
                Rectangle()
                    .fill(color)
                    .frame(width: size * 0.28, height: size)
            }
        case .dashes, .dashDots:
            EmptyView()
        }
    }
}
