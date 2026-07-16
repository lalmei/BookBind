import AppKit
import SwiftUI

/// Cover-style endsheet workbench: flat 2×trim artboard with pastedown / flyleaf fold guides.
struct EndsheetDesignerView: View {
    @EnvironmentObject private var store: AppStore
    let project: BinderyProject
    @ObservedObject var workspace: BindingWorkspace
    @ObservedObject var chrome: CoverEditorChrome
    @Binding var editingFront: Bool

    @State private var isInspectorVisible = true
    @State private var measurementsExpanded = true
    @State private var designExpanded = true
    @State private var marblingExpanded = true
    @State private var previewImage: NSImage?
    @State private var previewTask: Task<Void, Never>?
    @State private var isRendering = false
    @State private var liveZoom: Double = 1

    private var geometry: EndsheetGeometry {
        EndsheetGeometry.resolving(project: project, trimPoints: workspace.job.resolvedTrimSize)
    }

    private var face: EndpaperFaceDesign {
        editingFront ? workspace.job.endpapers.front : workspace.job.endpapers.back
    }

    private var minimumSplitWidth: CGFloat {
        let canvasMin: CGFloat = 416
        if isInspectorVisible {
            return canvasMin + 300
        }
        return canvasMin + WorkbenchInspectorChrome.collapsedRailWidth
    }

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                canvasToolbar
                Divider()
                canvasHost
            }
            .frame(minWidth: 416)

            if isInspectorVisible {
                inspector
                    .frame(minWidth: 280, idealWidth: 320, maxWidth: 380)
            } else {
                WorkbenchInspectorChrome.CollapsedRail(isVisible: $isInspectorVisible, title: "Endpapers")
            }
        }
        .horizontallyScrollable(minWidth: minimumSplitWidth)
        .onAppear {
            liveZoom = chrome.zoomFactor
            syncFaceFromProject()
            schedulePreview()
        }
        .onChange(of: editingFront) { _ in
            schedulePreview()
        }
        .onChange(of: face) { _ in
            schedulePreview()
        }
        .onChange(of: chrome.zoomFactor) { newValue in
            liveZoom = newValue
        }
        .onChange(of: chrome.viewMode) { _ in
            liveZoom = chrome.zoomFactor
        }
        .onDisappear {
            previewTask?.cancel()
            store.save()
        }
    }

    // MARK: - Toolbar

    private var canvasToolbar: some View {
        HStack(spacing: 12) {
            Picker("", selection: $editingFront) {
                Text("Front").tag(true)
                Text("Back").tag(false)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 180)
            .labelsHidden()
            .help("Which endsheet you are editing")

            Text(face.mode.title)
                .font(.caption)
                .foregroundStyle(.secondary)

            if isRendering {
                ProgressView()
                    .controlSize(.small)
            }

            Spacer(minLength: 0)

            if face.mode == .marbled {
                Button {
                    updateFace { next in
                        next.ensureMarbling()
                        next.marbling?.regenerateVariation()
                    }
                } label: {
                    Label("Regenerate", systemImage: "arrow.triangle.2.circlepath")
                }
                .help("New marbling variation — same palette and settings")
            }

            Text("Flat endsheet — fold guides are print marks, not barriers.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    // MARK: - Canvas

    private var canvasHost: some View {
        GeometryReader { proxy in
            let scale = canvasScale(in: proxy.size)
            let sheetW = geometry.totalW * scale
            let sheetH = geometry.leafH * scale
            let pad: CGFloat = 48

            ZStack {
                Color(nsColor: .windowBackgroundColor)

                ScrollView([.horizontal, .vertical]) {
                    ZStack(alignment: .topLeading) {
                        Color.clear
                            .frame(
                                width: max(proxy.size.width, sheetW + pad * 2),
                                height: max(proxy.size.height, sheetH + pad * 2 + 36)
                            )

                        VStack(alignment: .leading, spacing: 6) {
                            ruler(scale: scale)
                            ZStack(alignment: .topLeading) {
                                sheetBody(sheetW: sheetW, sheetH: sheetH)
                                if face.showFoldGuides {
                                    foldGuideOverlay(sheetW: sheetW, sheetH: sheetH)
                                    zoneLabels(sheetW: sheetW, sheetH: sheetH)
                                }
                            }
                            .frame(width: sheetW, height: sheetH)
                            .shadow(color: .black.opacity(0.16), radius: 12, y: 5)
                        }
                        .padding(.leading, pad)
                        .padding(.top, pad)
                    }
                }

                CoverScrollZoomView { delta in
                    let factor = exp(Double(delta) * 0.01)
                    let next = min(4, max(0.35, chrome.zoomFactor * factor))
                    chrome.zoomFactor = next
                    liveZoom = next
                }
            }
        }
    }

    private func ruler(scale: Double) -> some View {
        let left = geometry.zone(forHalfIndex: 0, isFront: editingFront)
        let right = geometry.zone(forHalfIndex: 1, isFront: editingFront)
        return HStack(spacing: 0) {
            Text(String(format: "%@  %.0f mm", left.title, geometry.leafW))
                .frame(width: geometry.leafW * scale, alignment: .center)
            Text(String(format: "%@  %.0f mm", right.title, geometry.leafW))
                .frame(width: geometry.leafW * scale, alignment: .center)
        }
        .font(.system(size: 10, weight: .medium).monospacedDigit())
        .foregroundStyle(Color(nsColor: .secondaryLabelColor))
    }

    @ViewBuilder
    private func sheetBody(sheetW: CGFloat, sheetH: CGFloat) -> some View {
        ZStack {
            Rectangle()
                .fill(Color.white)
            if let previewImage {
                Image(nsImage: previewImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: sheetW, height: sheetH)
            } else if face.mode == .solidColor {
                Rectangle()
                    .fill(Color(cgColor: face.solidColor.cgColor))
            } else if face.mode == .blank {
                Rectangle()
                    .fill(Color.white)
            } else {
                ProgressView("Rendering…")
            }
        }
        .frame(width: sheetW, height: sheetH)
        .overlay {
            Rectangle()
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
        }
    }

    private func foldGuideOverlay(sheetW: CGFloat, sheetH: CGFloat) -> some View {
        let foldX = geometry.foldXMM / geometry.totalW * sheetW
        return ZStack {
            // Zone tints
            HStack(spacing: 0) {
                Rectangle()
                    .fill(ArtisanTheme.secondary.opacity(0.08))
                    .frame(width: foldX)
                Rectangle()
                    .fill(ArtisanTheme.primary.opacity(0.06))
                    .frame(width: sheetW - foldX)
            }
            Path { path in
                path.move(to: CGPoint(x: foldX, y: 0))
                path.addLine(to: CGPoint(x: foldX, y: sheetH))
            }
            .stroke(Color.black.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
        }
        .allowsHitTesting(false)
    }

    private func zoneLabels(sheetW: CGFloat, sheetH: CGFloat) -> some View {
        let left = geometry.zone(forHalfIndex: 0, isFront: editingFront)
        let right = geometry.zone(forHalfIndex: 1, isFront: editingFront)
        return HStack(spacing: 0) {
            Text(left.title.uppercased())
                .frame(maxWidth: .infinity)
            Text(right.title.uppercased())
                .frame(maxWidth: .infinity)
        }
        .font(.system(size: 11, weight: .semibold))
        .tracking(1.2)
        .foregroundStyle(Color.black.opacity(0.35))
        .frame(width: sheetW, height: sheetH)
        .allowsHitTesting(false)
    }

    private func canvasScale(in size: CGSize) -> Double {
        let pad: CGFloat = 100
        let base: Double
        switch chrome.viewMode {
        case .fit:
            let sx = max(40, size.width - pad) / geometry.totalW
            let sy = max(40, size.height - pad) / geometry.leafH
            base = min(sx, sy, 8)
        case .oneToOne:
            base = 3.78
        }
        return base * liveZoom
    }

    // MARK: - Inspector

    private var inspector: some View {
        WorkbenchInspectorChrome.Panel(title: "Endsheets", isVisible: $isInspectorVisible) {
            VStack(alignment: .leading, spacing: 12) {
                Text("One endsheet is a flat sheet folded once — pastedown glued to the board, flyleaf free. Counts are whole sheets (always 2 leaves each).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                collapsibleSection("Measurements", isExpanded: $measurementsExpanded) {
                    measurementRow("Leaf", String(format: "%.1f × %.1f mm", geometry.leafW, geometry.leafH))
                    measurementRow("Sheet", String(format: "%.1f × %.1f mm", geometry.totalW, geometry.leafH))
                    measurementRow("Fold", String(format: "%.1f mm from left", geometry.foldXMM))
                    endsheetCountStepper(
                        title: editingFront ? "Front endsheets" : "Back endsheets",
                        sheets: editingFront
                            ? endsheetBinding(isFront: true)
                            : endsheetBinding(isFront: false)
                    )
                    Toggle("Fold / zone guides", isOn: faceShowFoldGuidesBinding)
                }

                collapsibleSection("Design", isExpanded: $designExpanded) {
                    modePicker
                    modeDetails
                }

                if face.mode == .marbled {
                    collapsibleSection("Marbling", isExpanded: $marblingExpanded) {
                        marblingControls
                    }
                }
            }
        }
    }

    private func measurementRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.callout.monospacedDigit())
                .foregroundStyle(Color(nsColor: .labelColor))
        }
    }

    private func endsheetCountStepper(title: String, sheets: Binding<Int>) -> some View {
        HStack {
            Text(title)
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
            Stepper(
                value: sheets,
                in: 0...BindingJob.maxEndsheetsPerSide
            ) {
                Text("\(sheets.wrappedValue) (\(sheets.wrappedValue * 2) leaves)")
                    .font(.callout.monospacedDigit())
            }
        }
    }

    private func endsheetBinding(isFront: Bool) -> Binding<Int> {
        Binding(
            get: { isFront ? workspace.job.frontEndsheets : workspace.job.backEndsheets },
            set: {
                if isFront {
                    workspace.job.frontEndsheets = $0
                } else {
                    workspace.job.backEndsheets = $0
                }
                workspace.refreshPlan()
                workspace.markChanged()
            }
        )
    }

    private var modePicker: some View {
        VStack(spacing: 4) {
            ForEach(EndpaperMode.allCases) { mode in
                Button {
                    updateFace { next in
                        next.mode = mode
                        switch mode {
                        case .blank:
                            break
                        case .solidColor:
                            if next.solidColor == .none { next.solidColor = .archivalIvory }
                        case .artwork:
                            break
                        case .marbled:
                            next.ensureMarbling()
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: mode.systemImage)
                            .frame(width: 18)
                        Text(mode.title)
                            .font(.callout.weight(face.mode == mode ? .semibold : .regular))
                        Spacer(minLength: 0)
                        if face.mode == mode {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(ArtisanTheme.secondary)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(face.mode == mode
                                  ? ArtisanTheme.secondary.opacity(0.18)
                                  : Color.clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(mode.help)
            }
        }
    }

    @ViewBuilder
    private var modeDetails: some View {
        switch face.mode {
        case .blank:
            Text("Undecorated endsheet — both halves blank in the book block.")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .solidColor:
            HStack {
                Text("Color")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("", selection: solidColorBinding) {
                    ForEach(EndpaperColor.allCases.filter { $0 != .none }) { swatch in
                        Text(swatch.rawValue).tag(swatch)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 160)
            }
        case .artwork:
            HStack {
                if let artwork = face.artwork {
                    Text(artwork.name)
                        .font(.caption)
                        .lineLimit(1)
                    Spacer()
                    Button("Clear") {
                        if editingFront { workspace.clearFrontEndpaperArtwork() }
                        else { workspace.clearBackEndpaperArtwork() }
                        store.updateSelectedEndsheets { sheets in
                            if editingFront {
                                sheets.front.artwork = nil
                                sheets.front.syncModeFromContents()
                            } else {
                                sheets.back.artwork = nil
                                sheets.back.syncModeFromContents()
                            }
                        }
                    }
                    .buttonStyle(.borderless)
                } else {
                    Text("No artwork")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                Button("Choose…") {
                    if editingFront { workspace.chooseFrontEndpaperArtwork() }
                    else { workspace.chooseBackEndpaperArtwork() }
                    // Lift job artwork into project after picker.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        store.updateSelectedEndsheets { sheets in
                            sheets = workspace.job.endpapers
                        }
                    }
                }
                .buttonStyle(.bordered)
            }
        case .marbled:
            Text(face.marbling?.style.title ?? "Marble paper")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var marblingControls: some View {
        let spec = face.marbling ?? MarbledPaperSpec()
        return VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(MarblingStyle.allCases) { style in
                    let selected = spec.style == style
                    Button {
                        updateMarbling { $0.style = style }
                    } label: {
                        Text(style.title)
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                            .padding(8)
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

            ForEach(MarbledPaperPalette.all) { palette in
                Button {
                    updateMarbling { marble in
                        marble.palette = palette.colors
                        marble.background = palette.background
                    }
                } label: {
                    HStack {
                        Text(palette.name)
                            .font(.callout)
                        Spacer()
                        if palette.colors == spec.palette && palette.background == spec.background {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(ArtisanTheme.secondary)
                        }
                    }
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
                }
                .buttonStyle(.plain)
            }

            sliderRow("Drop size", value: marblingDoubleBinding(\.dropSize, default: 1), range: 0.35...2.5)
            sliderRow("Density", value: marblingDoubleBinding(\.density, default: 0.55), range: 0.1...1)
            sliderRow("Scale", value: marblingDoubleBinding(\.scale, default: 1), range: 0.35...2.5)
            sliderRow("Comb spacing", value: marblingDoubleBinding(\.combSpacing, default: 1), range: 0.35...2.5)
            sliderRow("Comb strength", value: marblingDoubleBinding(\.combStrength, default: 1), range: 0.35...2.5)
            sliderRow("Turbulence", value: marblingDoubleBinding(\.turbulence, default: 0.35), range: 0...1)

            HStack {
                Text("Seed")
                    .font(.callout)
                Spacer()
                Text("\(spec.seed)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
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
        }
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
                Spacer()
                Text(value.wrappedValue, format: .number.precision(.fractionLength(2)))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range)
        }
    }

    private func collapsibleSection<Content: View>(
        _ title: String,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isExpanded.wrappedValue.toggle()
                }
            } label: {
                HStack {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(Color(nsColor: .labelColor))
                    Spacer()
                    Image(systemName: "chevron.down")
                        .rotationEffect(.degrees(isExpanded.wrappedValue ? 0 : -90))
                        .foregroundStyle(.secondary)
                        .font(.caption.weight(.semibold))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded.wrappedValue {
                content()
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Bindings & mutations

    private var faceShowFoldGuidesBinding: Binding<Bool> {
        Binding(
            get: { face.showFoldGuides },
            set: { value in
                updateFace { $0.showFoldGuides = value }
            }
        )
    }

    private var solidColorBinding: Binding<EndpaperColor> {
        Binding(
            get: { face.solidColor },
            set: { color in
                updateFace {
                    $0.solidColor = color
                    $0.mode = .solidColor
                }
            }
        )
    }

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

    private func updateFace(_ mutate: (inout EndpaperFaceDesign) -> Void) {
        store.updateSelectedEndsheets { sheets in
            if editingFront {
                mutate(&sheets.front)
            } else {
                mutate(&sheets.back)
            }
        }
    }

    private func updateMarbling(_ mutate: (inout MarbledPaperSpec) -> Void) {
        updateFace { next in
            var marble = next.marbling ?? MarbledPaperSpec()
            mutate(&marble)
            next.marbling = marble
            next.mode = .marbled
        }
    }

    private func syncFaceFromProject() {
        workspace.job.endpapers = project.endsheets
    }

    // MARK: - Preview

    private func schedulePreview() {
        previewTask?.cancel()
        previewTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }
            await renderPreview()
        }
    }

    @MainActor
    private func renderPreview() async {
        let faceSnapshot = face
        let sheetSize = geometry.sheetSizePoints
        // Solid / blank use live SwiftUI fills — skip raster.
        if faceSnapshot.mode == .blank || faceSnapshot.mode == .solidColor {
            previewImage = nil
            return
        }

        isRendering = true
        defer { isRendering = false }

        let image: NSImage? = await Task.detached(priority: .userInitiated) {
            EndsheetRenderService.nsImage(face: faceSnapshot, sheetSizePoints: sheetSize, dpi: 120)
        }.value
        if !Task.isCancelled {
            previewImage = image
        }
    }
}
