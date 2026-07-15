import AppKit
import PDFKit
import SwiftUI

/// Dedicated endpaper design surface (page trim geometry — not the cover wrap).
struct EndpaperDesignerView: View {
    @ObservedObject var workspace: BindingWorkspace
    @Binding var isPresented: Bool
    var initiallyEditingFront: Bool = true

    @State private var editingFront = true
    @State private var previewImage: NSImage?
    @State private var previewTask: Task<Void, Never>?
    @State private var isRendering = false

    private var faceBinding: Binding<EndpaperFaceDesign> {
        Binding(
            get: { editingFront ? workspace.job.endpapers.front : workspace.job.endpapers.back },
            set: { newValue in
                if editingFront {
                    workspace.job.endpapers.front = newValue
                } else {
                    workspace.job.endpapers.back = newValue
                }
                workspace.markChanged()
                schedulePreview()
            }
        )
    }

    private var face: EndpaperFaceDesign {
        editingFront ? workspace.job.endpapers.front : workspace.job.endpapers.back
    }

    private var spec: MarbledPaperSpec {
        face.marbling ?? MarbledPaperSpec()
    }

    private var pageSize: CGSize {
        if let trim = workspace.job.resolvedTrimSize {
            return CGSize(
                width: trim.width + workspace.job.bleedPoints * 2,
                height: trim.height + workspace.job.bleedPoints * 2
            )
        }
        return CGSize(width: 612, height: 792)
    }

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                toolbar
                Divider()
                previewCanvas
            }
            .frame(minWidth: 440)

            inspector
                .frame(minWidth: 320, idealWidth: 360, maxWidth: 420)
        }
        .frame(minWidth: 880, minHeight: 560)
        .onAppear {
            editingFront = initiallyEditingFront
            var next = editingFront ? workspace.job.endpapers.front : workspace.job.endpapers.back
            if next.mode != .marbled || next.marbling == nil {
                next.ensureMarbling()
                if editingFront {
                    workspace.job.endpapers.front = next
                } else {
                    workspace.job.endpapers.back = next
                }
                workspace.markChanged()
            }
            schedulePreview()
        }
        .onChange(of: editingFront) { _ in
            schedulePreview()
        }
        .onDisappear {
            previewTask?.cancel()
        }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Text("Marble paper generator")
                .font(.headline)
                .foregroundStyle(Color(nsColor: .labelColor))

            Picker("", selection: $editingFront) {
                Text("Front").tag(true)
                Text("Back").tag(false)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 180)
            .labelsHidden()
            .help("Which endpaper face you are editing")

            Spacer()

            if isRendering {
                ProgressView()
                    .controlSize(.small)
            }

            Button {
                updateMarbling { $0.regenerateVariation() }
            } label: {
                Label("Regenerate", systemImage: "arrow.triangle.2.circlepath")
            }
            .help("New variation — same palette and settings, new seed")

            Button("Done") { isPresented = false }
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var previewCanvas: some View {
        GeometryReader { proxy in
            let aspect = pageSize.width / max(1, pageSize.height)
            let fitW = min(proxy.size.width - 48, (proxy.size.height - 48) * aspect)
            let fitH = fitW / aspect
            ZStack {
                Color(nsColor: .windowBackgroundColor)
                Group {
                    if let previewImage {
                        Image(nsImage: previewImage)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: fitW, height: fitH)
                            .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
                    } else {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(Color(nsColor: .textBackgroundColor))
                            .frame(width: fitW, height: fitH)
                            .overlay {
                                ProgressView("Rendering…")
                            }
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 1, style: .continuous)
                        .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
                        .frame(width: fitW, height: fitH)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var inspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                sectionHeader("Pattern", subtitle: spec.style.help)
                styleGrid

                sectionHeader("Colors", subtitle: "Presets fill the ink wells; edit any color below.")
                palettePresets
                inkWells
                paperColorRow

                sectionHeader("Drops", subtitle: "How ink is laid on the bath before combing.")
                sliderRow("Drop size", value: marblingDoubleBinding(\.dropSize, default: 1), range: 0.35...2.5)
                sliderRow("Drop density", value: marblingDoubleBinding(\.density, default: 0.55), range: 0.1...1)
                sliderRow("Ink vs paper", value: marblingDoubleBinding(\.colorBalance, default: 0.5), range: 0...1)

                sectionHeader("Combs & rake", subtitle: "Marblizer-style tine spacing and pull strength.")
                flowRow
                sliderRow("Overall scale", value: marblingDoubleBinding(\.scale, default: 1), range: 0.35...2.5)
                sliderRow("Comb spacing", value: marblingDoubleBinding(\.combSpacing, default: 1), range: 0.35...2.5)
                sliderRow("Comb strength", value: marblingDoubleBinding(\.combStrength, default: 1), range: 0.35...2.5)
                sliderRow("Turbulence", value: marblingDoubleBinding(\.turbulence, default: 0.35), range: 0...1)

                sectionHeader("Variation", subtitle: "Seed is saved with the project for exact reprints.")
                variationRow
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Sections

    private func sectionHeader(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.headline)
                .foregroundStyle(Color(nsColor: .labelColor))
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var styleGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            ForEach(MarblingStyle.allCases) { style in
                let selected = spec.style == style
                Button {
                    updateMarbling { $0.style = style }
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(style.title)
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(Color(nsColor: .labelColor))
                            .multilineTextAlignment(.leading)
                        Text(shortStyleBlurb(style))
                            .font(.caption2)
                            .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, minHeight: 54, alignment: .topLeading)
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(selected
                                  ? ArtisanTheme.secondary.opacity(0.22)
                                  : Color(nsColor: .controlBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(
                                selected ? ArtisanTheme.secondary : Color(nsColor: .separatorColor),
                                lineWidth: selected ? 1.5 : 1
                            )
                    )
                }
                .buttonStyle(.plain)
                .help(style.help)
            }
        }
    }

    private func shortStyleBlurb(_ style: MarblingStyle) -> String {
        switch style {
        case .stone: return "Random drops"
        case .nonpareil: return "Fine parallel combs"
        case .peacock: return "Circular bouquet rakes"
        case .combed: return "Wide directional rake"
        }
    }

    private var palettePresets: some View {
        VStack(spacing: 6) {
            ForEach(MarbledPaperPalette.all) { palette in
                let active = paletteMatches(palette)
                Button {
                    updateMarbling { marble in
                        marble.palette = palette.colors
                        marble.background = palette.background
                    }
                } label: {
                    HStack(spacing: 10) {
                        HStack(spacing: 3) {
                            ForEach(Array(palette.colors.prefix(4).enumerated()), id: \.offset) { _, color in
                                Circle()
                                    .fill(color.color)
                                    .frame(width: 14, height: 14)
                                    .overlay(Circle().strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5))
                            }
                        }
                        Text(palette.name)
                            .font(.callout.weight(active ? .semibold : .regular))
                            .foregroundStyle(Color(nsColor: .labelColor))
                        Spacer(minLength: 0)
                        if active {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(ArtisanTheme.secondary)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(
                                active ? ArtisanTheme.secondary.opacity(0.8) : Color(nsColor: .separatorColor),
                                lineWidth: 1
                            )
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func paletteMatches(_ palette: MarbledPaperPalette) -> Bool {
        spec.palette == palette.colors && spec.background == palette.background
    }

    private var inkWells: some View {
        VStack(spacing: 8) {
            ForEach(Array(spec.palette.enumerated()), id: \.offset) { index, color in
                HStack(spacing: 10) {
                    Text("Ink \(index + 1)")
                        .font(.callout)
                        .foregroundStyle(Color(nsColor: .labelColor))
                        .frame(width: 52, alignment: .leading)
                    ColorPicker(
                        "",
                        selection: Binding(
                            get: { color.color },
                            set: { newColor in
                                updateMarbling { marble in
                                    guard index < marble.palette.count else { return }
                                    marble.palette[index] = CodableColor(color: newColor)
                                }
                            }
                        ),
                        supportsOpacity: false
                    )
                    .labelsHidden()
                    Spacer(minLength: 0)
                    if spec.palette.count > 2 {
                        Button {
                            updateMarbling { marble in
                                guard marble.palette.count > 2, index < marble.palette.count else { return }
                                marble.palette.remove(at: index)
                            }
                        } label: {
                            Image(systemName: "minus.circle")
                                .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                        }
                        .buttonStyle(.borderless)
                        .help("Remove this ink")
                    }
                }
            }

            if spec.palette.count < 6 {
                Button {
                    updateMarbling { marble in
                        marble.palette.append(CodableColor.inkBlack)
                    }
                } label: {
                    Label("Add ink", systemImage: "plus")
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private var paperColorRow: some View {
        HStack {
            Text("Paper / bath")
                .font(.callout)
                .foregroundStyle(Color(nsColor: .labelColor))
            Spacer()
            ColorPicker(
                "",
                selection: Binding(
                    get: { spec.background.color },
                    set: { newColor in
                        updateMarbling { $0.background = CodableColor(color: newColor) }
                    }
                ),
                supportsOpacity: false
            )
            .labelsHidden()
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private var flowRow: some View {
        HStack(alignment: .center, spacing: 8) {
            Text("Flow direction")
                .font(.callout)
                .foregroundStyle(Color(nsColor: .labelColor))
            Spacer(minLength: 0)
            AngleControl(
                degrees: spec.flowDegrees,
                onCommit: { degrees in
                    updateMarbling { $0.flowDegrees = degrees }
                }
            )
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private func sliderRow(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.callout)
                    .foregroundStyle(Color(nsColor: .labelColor))
                Spacer()
                Text(value.wrappedValue, format: .number.precision(.fractionLength(2)))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
            }
            Slider(value: value, in: range)
        }
    }

    private var variationRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Seed")
                    .font(.callout)
                    .foregroundStyle(Color(nsColor: .labelColor))
                Spacer()
                Text("\(spec.seed)")
                    .font(.caption.monospaced())
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                    .textSelection(.enabled)
            }

            Button {
                updateMarbling { $0.regenerateVariation() }
            } label: {
                Label("Regenerate variation", systemImage: "arrow.triangle.2.circlepath")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(ArtisanTheme.secondary)
            .foregroundStyle(Color.black)

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(String(spec.seed), forType: .string)
            } label: {
                Label("Copy seed", systemImage: "doc.on.doc")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    // MARK: - Mutations

    private func marblingDoubleBinding(
        _ keyPath: WritableKeyPath<MarbledPaperSpec, Double>,
        default defaultValue: Double
    ) -> Binding<Double> {
        Binding(
            get: { face.marbling?[keyPath: keyPath] ?? defaultValue },
            set: { value in
                updateMarbling { marble in marble[keyPath: keyPath] = value }
            }
        )
    }

    private func updateMarbling(_ mutate: (inout MarbledPaperSpec) -> Void) {
        var next = face
        var marble = next.marbling ?? MarbledPaperSpec()
        mutate(&marble)
        next.marbling = marble
        next.mode = .marbled
        faceBinding.wrappedValue = next
    }

    // MARK: - Preview

    private func schedulePreview() {
        previewTask?.cancel()
        previewTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 100_000_000)
            guard !Task.isCancelled else { return }
            await renderPreview()
        }
    }

    @MainActor
    private func renderPreview() async {
        let size = pageSize
        let marble = face.marbling ?? MarbledPaperSpec()
        isRendering = true
        defer { isRendering = false }

        let previewW = min(900, max(240, Int(size.width * 1.2)))
        let previewH = max(8, Int(Double(previewW) * size.height / max(1, size.width)))
        let image: NSImage? = await Task.detached(priority: .userInitiated) {
            guard let cg = MarbledPaperGenerator.render(spec: marble, width: previewW, height: previewH) else {
                return nil
            }
            return NSImage(cgImage: cg, size: size)
        }.value
        if !Task.isCancelled {
            previewImage = image
        }
    }
}
