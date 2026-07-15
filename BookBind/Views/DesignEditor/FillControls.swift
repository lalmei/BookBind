import SwiftUI

/// Square macOS-style color well for stroke / fill paints.
/// Shows the classic diagonal “None” slash when paint is `.none`.
struct PaintColorWell: View {
    let paint: CoverPaint
    var defaultSolid: CodableColor
    var allowsNone: Bool = true
    var onChange: (CoverPaint) -> Void

    @State private var showingPicker = false

    private let wellSize: CGFloat = 22

    var body: some View {
        Button {
            showingPicker = true
        } label: {
            wellSwatch
        }
        .buttonStyle(.plain)
        .help(helpText)
        .popover(isPresented: $showingPicker, arrowEdge: .bottom) {
            popoverContent
                .padding(12)
                .frame(minWidth: 180)
        }
    }

    private var helpText: String {
        switch paint {
        case .none: return "None — click to choose a color"
        case .solid: return "Click to edit color"
        }
    }

    private var wellSwatch: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))

            switch paint {
            case .none:
                noneSlash
            case let .solid(color):
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .fill(color.color)
                    .padding(2)
            }
        }
        .frame(width: wellSize, height: wellSize)
        .overlay(
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.08), radius: 0.5, y: 0.5)
    }

    private var noneSlash: some View {
        GeometryReader { proxy in
            Path { path in
                let inset: CGFloat = 4
                path.move(to: CGPoint(x: inset, y: proxy.size.height - inset))
                path.addLine(to: CGPoint(x: proxy.size.width - inset, y: inset))
            }
            .stroke(Color.red.opacity(0.85), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
        }
        .padding(1)
    }

    private var popoverContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            if allowsNone {
                Button {
                    onChange(.none)
                    showingPicker = false
                } label: {
                    HStack(spacing: 8) {
                        nonePreviewChip
                        Text("None")
                            .foregroundStyle(Color(nsColor: .labelColor))
                        Spacer(minLength: 0)
                        if case .none = paint {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Divider()
            }

            HStack(spacing: 10) {
                Text("Color")
                    .foregroundStyle(Color(nsColor: .labelColor))
                Spacer(minLength: 0)
                ColorPicker(
                    "",
                    selection: Binding(
                        get: { paint.solidColor?.color ?? defaultSolid.color },
                        set: { onChange(.solid(CodableColor(color: $0))) }
                    ),
                    supportsOpacity: true
                )
                .labelsHidden()
                .frame(width: 36, height: 24)
            }

            if case .none = paint, allowsNone {
                Text("Pick a color to enable.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var nonePreviewChip: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
            GeometryReader { proxy in
                Path { path in
                    let inset: CGFloat = 3
                    path.move(to: CGPoint(x: inset, y: proxy.size.height - inset))
                    path.addLine(to: CGPoint(x: proxy.size.width - inset, y: inset))
                }
                .stroke(Color.red.opacity(0.85), lineWidth: 1.25)
            }
            .padding(1)
        }
        .frame(width: 16, height: 16)
        .overlay(
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }
}

/// Fill / stroke color row — square wells with optional None.
struct FillControls: View {
    let fill: CoverPaint
    var defaultSolid: CodableColor
    var onChange: (CoverPaint) -> Void

    var body: some View {
        PaintColorWell(
            paint: fill,
            defaultSolid: defaultSolid,
            allowsNone: true,
            onChange: onChange
        )
    }
}
