import SwiftUI

/// Square macOS-style color well for stroke / fill paints.
/// Shows the classic diagonal “None” slash when paint is `.none`.
struct PaintColorWell: View {
    let paint: CoverPaint
    var defaultSolid: CodableColor
    var allowsNone: Bool = true
    /// When true, the popover offers regeneratable marbled paper as a fill.
    var allowsMarble: Bool = false
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
                .frame(minWidth: 200)
        }
    }

    private var helpText: String {
        switch paint {
        case .none: return "None — click to choose a color"
        case .solid: return "Click to edit color"
        case .marbled: return "Marbled paper — click to edit or regenerate"
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
            case .marbled:
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.55, green: 0.25, blue: 0.2),
                                Color(red: 0.2, green: 0.35, blue: 0.55),
                                Color(red: 0.85, green: 0.75, blue: 0.45)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
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

            SwatchPaletteGrid(current: paint.solidColor) { color in
                onChange(.solid(color))
            }

            if allowsMarble {
                Divider()
                Button {
                    var spec = paint.marbling ?? MarbledPaperSpec()
                    if paint.marbling == nil {
                        spec.regenerateVariation()
                    }
                    onChange(.marbled(spec))
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "paintbrush.pointed.fill")
                        Text(paint.isMarbled ? "Marbled paper" : "Use marbled paper")
                        Spacer(minLength: 0)
                        if paint.isMarbled {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if var marble = paint.marbling {
                    Button("Regenerate variation") {
                        marble.regenerateVariation()
                        onChange(.marbled(marble))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Text(marble.hasEditableHistory
                         ? "\(marble.operations?.count ?? 0) ops · seed \(marble.seed)"
                         : "Seed \(marble.seed)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
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

/// Saved palette inside a paint popover: click a chip to apply, + to save the current colour,
/// and import / export `.ase` palettes. Right-click a chip to remove it.
struct SwatchPaletteGrid: View {
    @ObservedObject private var store = SwatchStore.shared
    let current: CodableColor?
    let onPick: (CodableColor) -> Void

    private let columns = Array(repeating: GridItem(.fixed(18), spacing: 5), count: 8)

    private func isCurrent(_ swatch: Swatch) -> Bool {
        current.map { SwatchStore.isSame($0, swatch.color) } ?? false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Swatches")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Menu {
                    Button("Import .ase…") { store.runImportPanel() }
                    Button("Export .ase…") { store.runExportPanel() }
                        .disabled(store.swatches.isEmpty)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Import or export Adobe Swatch Exchange palettes")
            }
            LazyVGrid(columns: columns, alignment: .leading, spacing: 5) {
                ForEach(store.swatches) { swatch in
                    Button {
                        onPick(swatch.color)
                    } label: {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(swatch.color.color)
                            .frame(width: 18, height: 18)
                            .overlay(
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .strokeBorder(
                                        isCurrent(swatch) ? Color(nsColor: .labelColor) : Color(nsColor: .separatorColor),
                                        lineWidth: isCurrent(swatch) ? 1.5 : 0.5
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                    .help(swatch.name)
                    .contextMenu {
                        Button("Remove “\(swatch.name)”", role: .destructive) { store.remove(swatch) }
                    }
                }
                if let current, !store.contains(current) {
                    Button {
                        store.add(current)
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 9, weight: .bold))
                            .frame(width: 18, height: 18)
                            .overlay(
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .strokeBorder(Color(nsColor: .separatorColor), style: StrokeStyle(lineWidth: 0.5, dash: [2, 2]))
                            )
                    }
                    .buttonStyle(.plain)
                    .help("Save the current colour as a swatch")
                }
            }
        }
    }
}

/// Fill / stroke color row — square wells with optional None and marble.
struct FillControls: View {
    let fill: CoverPaint
    var defaultSolid: CodableColor
    var allowsMarble: Bool = true
    var onChange: (CoverPaint) -> Void

    var body: some View {
        PaintColorWell(
            paint: fill,
            defaultSolid: defaultSolid,
            allowsNone: true,
            allowsMarble: allowsMarble,
            onChange: onChange
        )
    }
}
