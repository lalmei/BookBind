import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct CoverDesignerView: View {
    @EnvironmentObject private var store: AppStore
    let project: BinderyProject
    @ObservedObject var workspace: BindingWorkspace
    @ObservedObject var chrome: CoverEditorChrome

    @State private var selectedElementID: UUID?
    @State private var canvasTool: DesignCanvasTool = .select
    @GestureState private var pinchMagnification: CGFloat = 1.0
    @State private var isDraggingElement = false
    @State private var elementDragOrigin: CGSize = .zero
    @State private var resizeStartBounds: CoverElementBounds?
    @State private var resizingElementID: UUID?
    @State private var resizeStartFontSize: Double = CoverFontStyle.body.defaultSizeMM
    @State private var rotateGestureStartAngle: Double?
    @State private var rotateElementStartDegrees: Double = 0
    @State private var measurementsExpanded = true
    @State private var layersExpanded = true
    @State private var selectionExpanded = true
    @State private var isInspectorVisible = true
    @State private var pendingImagePlacement: (wrapX: Double, wrapY: Double)?
    @State private var showImageImporter = false
    @State private var showJointGuides = true
    @State private var collapsedLayerIDs: Set<UUID> = []
    /// Finish channel for newly placed elements (Illustrator-style active swatch).
    @State private var activeFinish: CoverElementLayer = .ink
    /// When set, only this finish channel is shown on the canvas.
    @State private var soloFinish: CoverElementLayer?
    @State private var shapeDragStart: CGPoint?
    @State private var shapeDragCurrent: CGPoint?
    @State private var isInspectorEditing = false

    private var liveZoom: Double {
        chrome.zoomFactor * Double(pinchMagnification)
    }

    private var pageCount: Int {
        let fromWorkspace = workspace.assembledPageCount
        if fromWorkspace > 0 { return fromWorkspace }
        return max(0, project.estimatedPageCount)
    }

    /// Live imposition binding when available; otherwise the project architecture.
    private var coverArchitecture: BindingArchitecture {
        if project.allows(.imposition) {
            return store.workspace(for: project.id).job.bindingStyle.architecture
        }
        return project.architecture
    }

    private var coverMeasurementDefaults: CoverMeasurementDefaults {
        coverArchitecture.coverDefaults
    }

    private var bindingStyleLabel: String {
        if project.allows(.imposition) {
            return store.workspace(for: project.id).job.bindingStyle.rawValue
        }
        return project.architecture.rawValue
    }

    /// Imposition job for plan estimates — live workspace when available, else architecture defaults.
    private var effectiveBindingJob: BindingJob {
        let workspace = store.workspace(for: project.id)
        if project.allows(.imposition) {
            return workspace.job
        }
        var job = BindingJob()
        job.applyArchitecture(coverArchitecture)
        return job
    }

    /// Signature layout for spine notes — cached impose plan when assembled, else computed.
    private var resolvedBindingPlan: BindingPlan? {
        guard pageCount > 0 else { return nil }
        let workspace = store.workspace(for: project.id)
        if workspace.assembledPageCount > 0, let plan = workspace.plan {
            return plan
        }
        return ImpositionService.plan(contentPageCount: pageCount, job: effectiveBindingJob)
    }

    private var signatureSummaryLabel: String? {
        guard let plan = resolvedBindingPlan, plan.signatureCount > 0 else { return nil }
        if effectiveBindingJob.bindingStyle == .saddleStitch {
            return "1 nested · \(plan.pagesPerSignature)-page"
        }
        return "\(plan.signatureCount) × \(plan.pagesPerSignature)-page"
    }

    private var minimumBoardSize: CGSize {
        let workspace = store.workspace(for: project.id)
        if let trim = workspace.job.resolvedTrimSize ?? workspace.sources.first?.pageSize {
            return CGSize(
                width: BindingMath.millimeters(fromPoints: trim.width),
                height: BindingMath.millimeters(fromPoints: trim.height)
            )
        }
        return CGSize(width: project.widthMM, height: project.heightMM)
    }

    private var minimumBoardWidthMM: Double {
        max(40, (Double(minimumBoardSize.width) * 10).rounded() / 10)
    }

    private var minimumBoardHeightMM: Double {
        max(40, (Double(minimumBoardSize.height) * 10).rounded() / 10)
    }

    /// Spine width the current book block requires — the lower bound for manual overrides.
    private var requiredSpineWidth: Double {
        BindingMath.spineWidthMM(
            architecture: coverArchitecture,
            pageCount: pageCount,
            gsm: project.textPaperGSM,
            boardThicknessMM: project.boardThicknessMM,
            hingeGapMM: project.hingeGapMM
        )
    }

    /// Spine width used for layout and export (manual override when set).
    private var spineWidth: Double {
        project.effectiveSpineWidthMM(pageCount: pageCount)
    }

    private var measurementWarnings: [String] {
        CoverEditorMath.measurementWarnings(
            boardWidthMM: project.widthMM,
            boardHeightMM: project.heightMM,
            minimumBoardWidthMM: minimumBoardWidthMM,
            minimumBoardHeightMM: minimumBoardHeightMM,
            spineWidthMM: spineWidth,
            requiredSpineWidthMM: requiredSpineWidth
        )
    }

    private var textBlock: Double {
        BindingMath.textBlockThicknessMM(pageCount: pageCount, gsm: project.textPaperGSM)
    }

    private var geometry: CoverBlueprintService.Geometry {
        CoverBlueprintService.Geometry(project: project, spineWidthMM: spineWidth)
    }

    private var selectedElement: CoverDesignElement? {
        guard let id = selectedElementID else { return nil }
        return project.coverElements.first { $0.id == id }
    }

    /// Canvas + inspector split width.
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
                WorkbenchInspectorChrome.CollapsedRail(isVisible: $isInspectorVisible, title: "Cover")
            }
        }
        .horizontallyScrollable(minWidth: minimumSplitWidth)
        .onAppear {
            // Sizes are user-editable with soft bounds; warn instead of clamping.
            store.updateSelectedProject {
                $0.seedCoverElementsIfNeeded(spineWidthMM: spineWidth)
            }
        }
        .fileImporter(
            isPresented: $showImageImporter,
            allowedContentTypes: [.png, .jpeg, .tiff, .heic],
            allowsMultipleSelection: false
        ) { result in
            handleImageImport(result)
        }
    }

    // MARK: - Canvas toolbar

    private var canvasToolbar: some View {
        HStack(spacing: 12) {
            canvasToolStrip

            Divider()
                .frame(height: 22)

            finishToolStrip

            if let finish = soloFinish {
                Divider()
                    .frame(height: 22)

                Label("Solo \(finish.title)", systemImage: "eye")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Show All") { soloFinish = nil }
                    .buttonStyle(.borderless)
                    .font(.caption)
            }

            if selectedElementID != nil {
                Divider()
                    .frame(height: 22)

                Button {
                    duplicateSelected()
                } label: {
                    Label("Duplicate", systemImage: "plus.square.on.square")
                }
                .help("Duplicate selected element (⌘D)")

                Button("Delete", role: .destructive) {
                    deleteSelected()
                }
                .keyboardShortcut(.delete, modifiers: [])
                .help("Delete selected element (Delete)")
            }

            Text(toolHint)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .tint(Color(nsColor: .labelColor))
        .background(.bar)
    }

    private var canvasToolStrip: some View {
        HStack(spacing: 2) {
            ForEach(DesignCanvasTool.allCases) { tool in
                Button {
                    // Creation tool only — never mutates the current selection's type.
                    canvasTool = tool
                } label: {
                    Image(systemName: tool.systemImage)
                        .font(.system(size: 13, weight: canvasTool == tool ? .semibold : .regular))
                        .frame(width: 28, height: 26)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(canvasTool == tool
                                      ? Color.accentColor.opacity(0.2)
                                      : Color.clear)
                        )
                }
                .buttonStyle(.plain)
                .foregroundStyle(canvasTool == tool ? Color.accentColor : Color.secondary)
                .help(tool.title)
            }
        }
    }

    private var finishToolStrip: some View {
        HStack(spacing: 6) {
            ForEach(CoverElementLayer.allCases) { finish in
                finishSwatchButton(finish)
            }
        }
    }

    private func finishSwatchButton(_ finish: CoverElementLayer) -> some View {
        let isActive = activeFinish == finish
        let isSolo = soloFinish == finish
        return Button {
            activeFinish = finish
            if finish == .foil {
                store.updateSelectedProject { $0.showFoilLayer = true }
            }
            if finish == .deboss {
                store.updateSelectedProject { $0.showDebossLayer = true }
            }
        } label: {
            ZStack {
                Circle()
                    .fill(finishSwatchColor(finish))
                    .frame(width: 22, height: 22)
                if isSolo {
                    Circle()
                        .strokeBorder(Color.accentColor, lineWidth: 2)
                        .frame(width: 26, height: 26)
                } else if isActive {
                    Circle()
                        .strokeBorder(Color.primary.opacity(0.45), lineWidth: 1.5)
                        .frame(width: 24, height: 24)
                }
                Text(finish.badge)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(finish == .foil ? Color.white : Color.white.opacity(0.92))
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(isSolo ? "Show All Finishes" : "Solo \(finish.title)") {
                soloFinish = isSolo ? nil : finish
            }
            if finish != .ink {
                Button(finish == .foil ? "Hide Foil Layer" : "Hide Deboss Layer") {
                    if finish == .foil {
                        store.updateSelectedProject { $0.showFoilLayer = false }
                    } else {
                        store.updateSelectedProject { $0.showDebossLayer = false }
                    }
                    if soloFinish == finish { soloFinish = nil }
                }
            }
        }
        .help("\(finish.title) — active finish for new elements. Right-click to solo.")
    }

    private func finishSwatchColor(_ finish: CoverElementLayer) -> Color {
        switch finish {
        case .ink: return Color(nsColor: .systemGray)
        case .foil: return ArtisanTheme.secondary
        case .deboss: return Color(nsColor: .secondaryLabelColor)
        }
    }

    // MARK: - Canvas

    private let wrapSideRulerColumnWidth: CGFloat = 28
    private let wrapRulerSpacing: CGFloat = 8

    private var canvasHost: some View {
        GeometryReader { geo in
            let scale = canvasScale(in: geo.size)
            let wrapW = geometry.totalW * scale
            let wrapH = geometry.boardH * scale

            ZStack {
                Color(nsColor: .textBackgroundColor)

                ScrollView([.horizontal, .vertical], showsIndicators: true) {
                    VStack(spacing: 8) {
                        if showJointGuides {
                            HStack(alignment: .top, spacing: wrapRulerSpacing) {
                                Color.clear
                                    .frame(width: wrapSideRulerColumnWidth)
                                wrapTopRuler(wrapW: wrapW, scale: scale)
                            }
                            .fixedSize(horizontal: false, vertical: true)
                        } else {
                            dimensionBar(totalWidth: wrapW)
                        }

                        HStack(alignment: .top, spacing: wrapRulerSpacing) {
                            if showJointGuides {
                                wrapSideRuler(wrapH: wrapH)
                            }
                            wrapCanvas(wrapW: wrapW, wrapH: wrapH, scale: scale)
                        }

                        Text(showJointGuides
                             ? "Zone labels sit outside the artboard · dashed lines are joint guides only"
                             : "Full wrap · place art anywhere")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(
                        minWidth: max(geo.size.width, wrapW + (showJointGuides ? 108 : 80)),
                        minHeight: max(geo.size.height, wrapH + (showJointGuides ? 140 : 100)),
                        alignment: .top
                    )
                }

                CoverScrollZoomView { delta in
                    chrome.zoomFactor = CoverEditorMath.zoomFactor(
                        afterScrollDelta: delta,
                        current: chrome.zoomFactor
                    )
                }
            }
            .gesture(magnificationGesture)
            .onChange(of: chrome.viewMode) { _ in
                chrome.zoomFactor = 1.0
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .focusable()
        .modifier(CoverFocusRingDisabled())
        .onDeleteCommand {
            guard !isInspectorEditing else { return }
            deleteSelected()
        }
        .onExitCommand {
            guard !isInspectorEditing else { return }
            selectedElementID = nil
            canvasTool = .select
        }
        .onMoveCommand { direction in
            guard !isInspectorEditing else { return }
            let step = NSEvent.modifierFlags.contains(.shift) ? 10.0 : 1.0
            switch direction {
            case .left: nudgeSelected(dxMM: -step, dyMM: 0)
            case .right: nudgeSelected(dxMM: step, dyMM: 0)
            case .up: nudgeSelected(dxMM: 0, dyMM: -step)
            case .down: nudgeSelected(dxMM: 0, dyMM: step)
            @unknown default: break
            }
        }
        .background {
            Button("") { deleteSelected() }
                .keyboardShortcut(.delete, modifiers: [])
                .opacity(0)
                .allowsHitTesting(false)
            Button("") { deleteSelected() }
                .keyboardShortcut(.deleteForward, modifiers: [])
                .opacity(0)
                .allowsHitTesting(false)
            Button("") { duplicateSelected() }
                .keyboardShortcut("d", modifiers: [.command])
                .opacity(0)
                .allowsHitTesting(false)
        }
    }

    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .updating($pinchMagnification) { value, state, _ in
                state = value
            }
            .onEnded { value in
                chrome.zoomFactor = min(8, max(0.25, chrome.zoomFactor * Double(value)))
            }
    }

    private func dimensionBar(totalWidth: CGFloat) -> some View {
        VStack(spacing: 4) {
            Text(String(format: "TOTAL WIDTH: %.1f mm · spine face %.1f · joints %.1f · %.0f%%",
                         geometry.totalW, geometry.spineFace, geometry.hinge, liveZoom * 100))
                .font(ArtisanTheme.technicalCaption)
                .foregroundStyle(.secondary)

            ZStack {
                Rectangle()
                    .fill(Color.primary.opacity(0.25))
                    .frame(height: 1)
                HStack {
                    Rectangle().fill(Color.primary.opacity(0.35)).frame(width: 1, height: 8)
                    Spacer()
                    Rectangle().fill(Color.primary.opacity(0.35)).frame(width: 1, height: 8)
                }
            }
            .frame(width: totalWidth)
        }
    }

    /// Zone names and widths above the artboard, aligned to panel columns.
    private func wrapTopRuler(wrapW: CGFloat, scale: Double) -> some View {
        let midsectionCramped = midsectionPanelsAreCramped(scale: scale)
        let rulerHeight: CGFloat = midsectionCramped ? 40 : 48

        return VStack(spacing: 4) {
            Text(String(format: "Total wrap %.1f mm · %.0f%% zoom", geometry.totalW, liveZoom * 100))
                .font(.caption2)
                .foregroundStyle(.tertiary)

            if midsectionCramped {
                Text(midsectionLegendText())
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: max(wrapW, 220))
                    .fixedSize(horizontal: false, vertical: true)
            }

            ZStack(alignment: .topLeading) {
                panelBoundaryTicks(width: wrapW, scale: scale, tickHeight: 7)
                    .frame(width: wrapW, height: rulerHeight, alignment: .bottomLeading)

                ForEach(geometry.layoutPanels) { panel in
                    let origin = geometry.panelOriginX(panel) * scale
                    let pixelWidth = max(1, geometry.panelWidth(panel) * scale)
                    if panelRulerLabelMode(panel: panel, pixelWidth: pixelWidth, midsectionCramped: midsectionCramped) != nil {
                        panelRulerLabel(panel: panel, pixelWidth: pixelWidth, midsectionCramped: midsectionCramped)
                            .position(
                                x: origin + pixelWidth / 2,
                                y: rulerCenterY(for: panel, pixelWidth: pixelWidth, rulerHeight: rulerHeight, midsectionCramped: midsectionCramped)
                            )
                    }
                }
            }
            .frame(width: wrapW, height: rulerHeight)
        }
    }

    /// Midsection bands are too narrow to read when any joint/spine column is under ~44 pt.
    private func midsectionPanelsAreCramped(scale: Double) -> Bool {
        geometry.layoutPanels
            .filter(\.prefersVerticalText)
            .contains { geometry.panelWidth($0) * scale < 44 }
    }

    private func midsectionLegendText() -> String {
        geometry.layoutPanels
            .filter(\.prefersVerticalText)
            .map { "\($0.canvasLabel) \(panelDimensionText($0))" }
            .joined(separator: "  ·  ")
    }

    private enum PanelRulerLabelMode {
        case stacked
        case inline
        case angled
    }

    private func panelRulerLabelMode(panel: CoverPanel, pixelWidth: CGFloat, midsectionCramped: Bool) -> PanelRulerLabelMode? {
        if panel.prefersVerticalText, midsectionCramped { return nil }

        if pixelWidth >= 72 { return .stacked }
        if pixelWidth >= 44 { return .inline }
        if pixelWidth >= 18 { return .angled }
        return panel.prefersVerticalText ? nil : .angled
    }

    private func rulerCenterY(
        for panel: CoverPanel,
        pixelWidth: CGFloat,
        rulerHeight: CGFloat,
        midsectionCramped: Bool
    ) -> CGFloat {
        switch panelRulerLabelMode(panel: panel, pixelWidth: pixelWidth, midsectionCramped: midsectionCramped) {
        case .angled:
            return rulerHeight / 2 + 4
        case .stacked, .inline, .none:
            return rulerHeight / 2 - 2
        }
    }

    @ViewBuilder
    private func panelRulerLabel(panel: CoverPanel, pixelWidth: CGFloat, midsectionCramped: Bool) -> some View {
        if let mode = panelRulerLabelMode(panel: panel, pixelWidth: pixelWidth, midsectionCramped: midsectionCramped) {
            Group {
                switch mode {
                case .stacked:
                    VStack(spacing: 1) {
                        Text(panel.canvasLabel)
                            .fontWeight(panel == .spine ? .semibold : .regular)
                        Text(panelDimensionText(panel))
                    }
                    .font(ArtisanTheme.technicalCaption)
                case .inline:
                    Text("\(panel.canvasLabel) \(panelDimensionText(panel))")
                        .font(.caption2)
                case .angled:
                    Text("\(panel.canvasLabel) \(panelDimensionText(panel))")
                        .font(.caption2)
                        .rotationEffect(.degrees(-58))
                        .fixedSize()
                }
            }
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: true, vertical: true)
        }
    }

    /// Board height label to the left of the artboard.
    private func wrapSideRuler(wrapH: CGFloat) -> some View {
        VStack(spacing: 6) {
            Text("H")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
            Text(String(format: "%.0f mm", geometry.boardH))
                .font(ArtisanTheme.technicalCaption)
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(-90))
                .fixedSize()
        }
        .frame(width: wrapSideRulerColumnWidth)
        .frame(height: wrapH, alignment: .center)
    }

    /// Wrap-mm positions for ruler ticks — every panel origin plus the wrap's right edge.
    private var rulerBoundaryXsMM: [Double] {
        var xs = geometry.layoutPanels.map { geometry.panelOriginX($0) }
        xs.append(geometry.totalW)
        return Array(Set(xs.map { ($0 * 100).rounded() / 100 })).sorted()
    }

    private func panelBoundaryTicks(width: CGFloat, scale: Double, tickHeight: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Color.primary.opacity(0.22))
                .frame(width: width, height: 1)

            ForEach(rulerBoundaryXsMM, id: \.self) { xMM in
                let x = CGFloat(xMM * scale)
                let clampedX = min(max(0, x), width)
                Rectangle()
                    .fill(Color.primary.opacity(0.35))
                    .frame(width: 1, height: tickHeight)
                    .position(x: clampedX, y: tickHeight / 2)
            }
        }
        .frame(width: width, height: tickHeight)
    }

    private func panelDimensionText(_ panel: CoverPanel) -> String {
        switch panel {
        case .back, .front:
            return String(format: "%.0f×%.0f mm", geometry.boardW, geometry.boardH)
        case .spine:
            return String(format: "%.1f mm", geometry.spineFace)
        case .backHinge, .frontHinge:
            return String(format: "%.1f mm", geometry.hinge)
        }
    }

    private func wrapCanvas(wrapW: CGFloat, wrapH: CGFloat, scale: Double) -> some View {
        ZStack(alignment: .topLeading) {
            // Shadow only on the artboard surface — not on placed images/text/shapes.
            Rectangle()
                .fill(materialBaseFill)
                .frame(width: wrapW, height: wrapH)
                .overlay {
                    Rectangle()
                        .strokeBorder(Color.black.opacity(0.55), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.35), radius: 12, y: 4)

            if showJointGuides {
                ForEach(geometry.layoutPanels) { panel in
                    let x = geometry.panelOriginX(panel) * scale
                    let w = geometry.panelWidth(panel) * scale
                    Rectangle()
                        .fill(zoneTint(for: panel))
                        .frame(width: max(1, w), height: wrapH)
                        .offset(x: x)
                        .allowsHitTesting(false)
                }

                jointGuideOverlay(wrapH: wrapH, scale: scale)
            }

            // Full-wrap hit target (under elements so selection still works).
            Color.clear
                .contentShape(Rectangle())
                .frame(width: wrapW, height: wrapH)
                .onTapGesture { location in
                    handleWrapTap(at: location, scale: scale)
                }

            ForEach(project.orderedCoverElementsForRendering()) { element in
                if element.isVisible, layerVisible(element.designLayerID) {
                    elementView(element, scale: scale)
                }
            }

            if let selectedElement,
               selectedElement.isVisible,
               !isLayerLocked(selectedElement.designLayerID) {
                selectionOverlay(for: selectedElement, scale: scale)
            }

            if let shapeType = canvasTool.shapeType,
               let start = shapeDragStart,
               let current = shapeDragCurrent {
                shapeDrawPreview(shapeType: shapeType, start: start, current: current, scale: scale)
            }
        }
        .frame(width: wrapW, height: wrapH)
        .clipped()
        .gesture(shapeDrawGesture(scale: scale))
    }

    private func layerVisible(_ layerID: UUID) -> Bool {
        project.coverDesignLayers.first { $0.id == layerID }?.isVisible ?? true
    }

    private func shapeDrawPreview(
        shapeType: CoverShapeType,
        start: CGPoint,
        current: CGPoint,
        scale: Double
    ) -> some View {
        let x1 = min(start.x, current.x)
        let y1 = min(start.y, current.y)
        let w = max(4, abs(current.x - start.x))
        let h = max(4, abs(current.y - start.y))
        let stroke = defaultStrokeStyle(for: activeFinish)
        let filled = shapeType != .line && activeFinish == .deboss
        return CoverShapeElementView(
            shapeType: shapeType,
            strokeStyle: stroke,
            strokeWidthPx: max(0.5, 0.8 * scale),
            dashPx: stroke.dashPatternMM(strokeWidthMM: 0.8).map { CGFloat($0 * scale) },
            isFilled: filled,
            color: finishSwatchColor(activeFinish),
            fillColor: filled ? CodableColor.finishDefault(for: activeFinish).color : nil
        )
        .frame(width: w, height: h)
        .opacity(0.55)
        .position(x: x1 + w / 2, y: y1 + h / 2)
        .allowsHitTesting(false)
        .zIndex(2)
    }

    private func shapeDrawGesture(scale: Double) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                guard canvasTool.shapeType != nil else { return }
                if shapeDragStart == nil {
                    shapeDragStart = value.startLocation
                }
                shapeDragCurrent = value.location
            }
            .onEnded { value in
                defer {
                    shapeDragStart = nil
                    shapeDragCurrent = nil
                }
                guard let shapeType = canvasTool.shapeType else { return }
                let start = shapeDragStart ?? value.startLocation
                let end = value.location
                let dx = abs(end.x - start.x)
                let dy = abs(end.y - start.y)
                if dx < 6 && dy < 6 {
                    let wrapX = clampWrapX(Double(end.x) / scale)
                    let wrapY = clampWrapY(Double(end.y) / scale)
                    placeShape(shapeType, wrapX: wrapX, wrapY: wrapY, zone: geometry.panel(containingWrapX: wrapX))
                    return
                }
                let x1 = min(start.x, end.x)
                let y1 = min(start.y, end.y)
                let wMM = max(CoverEditorMath.minimumElementSizeMM, Double(dx) / scale)
                let hMM = max(CoverEditorMath.minimumElementSizeMM, Double(dy) / scale)
                let centerX = clampWrapX(Double(x1 + dx / 2) / scale)
                let centerY = clampWrapY(Double(y1 + dy / 2) / scale)
                placeShape(
                    shapeType,
                    wrapX: centerX,
                    wrapY: centerY,
                    zone: geometry.panel(containingWrapX: centerX),
                    widthMM: wMM,
                    heightMM: shapeType == .line ? 4 : hMM
                )
            }
    }

    private var materialBaseFill: Color {
        switch project.coverMaterial {
        case .moroccanGoat:
            return Color(red: 0.92, green: 0.88, blue: 0.82)
        case .bookram, .buckram:
            return Color(white: 0.93)
        case .bookCloth:
            return Color.white
        case .paper:
            return Color(red: 0.96, green: 0.95, blue: 0.92)
        }
    }

    private func zoneTint(for panel: CoverPanel) -> Color {
        switch panel {
        case .spine:
            return Color.black.opacity(0.06)
        case .backHinge, .frontHinge:
            return Color.black.opacity(0.03)
        case .back, .front:
            return .clear
        }
    }

    private func jointGuideOverlay(wrapH: CGFloat, scale: Double) -> some View {
        Path { path in
            for xMM in geometry.guideXsMM {
                let x = xMM * scale
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: wrapH))
            }
        }
        .stroke(Color.black.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
        .allowsHitTesting(false)
    }

    private var visibleElements: [CoverDesignElement] {
        project.orderedCoverElementsForRendering().filter { finishVisible($0.layer) }
    }

    private func finishVisible(_ layer: CoverElementLayer) -> Bool {
        if let soloFinish {
            return layer == soloFinish
        }
        switch layer {
        case .ink: return true
        case .foil: return project.showFoilLayer
        case .deboss: return project.showDebossLayer
        }
    }

    private func elementCanvasOpacity(_ element: CoverDesignElement) -> Double {
        guard finishVisible(element.layer) else { return 0.22 }
        return element.opacity
    }

    @ViewBuilder
    private func elementView(_ element: CoverDesignElement, scale: Double) -> some View {
        let wrapX = element.wrapCenterX(geometry: geometry)
        let x = wrapX * scale
        let y = element.yMM * scale
        let bounds = CoverEditorMath.displayBounds(for: element, geometry: geometry)

        Group {
            switch element.kind {
            case .text:
                textElementLabel(element, pixelWidth: bounds.width * scale, pixelHeight: bounds.height * scale, scale: scale)
            case .image:
                imageElementView(element, pixelWidth: bounds.width * scale, pixelHeight: bounds.height * scale)
            case .shape:
                shapeElementView(element, pixelWidth: bounds.width * scale, pixelHeight: bounds.height * scale, scale: scale)
            }
        }
        .contentShape(Rectangle())
        .opacity(elementCanvasOpacity(element))
        .rotationEffect(.degrees(element.rotationDegrees))
        .position(x: x, y: y)
        .zIndex(1)
        .gesture(elementDragGesture(element, scale: scale))
        .highPriorityGesture(
            TapGesture().onEnded {
                selectedElementID = element.id
                canvasTool = .select
                activeFinish = element.layer
            }
        )
        .allowsHitTesting(!isLayerLocked(element.designLayerID))
    }

    private func isLayerLocked(_ layerID: UUID) -> Bool {
        project.coverDesignLayers.first { $0.id == layerID }?.isLocked ?? false
    }

    private func shapeElementView(
        _ element: CoverDesignElement,
        pixelWidth: CGFloat,
        pixelHeight: CGFloat,
        scale: Double
    ) -> some View {
        let strokePx = max(0.5, element.strokeWidthMM * scale)
        let dashPx = element.strokeDashPatternMM().map { CGFloat($0 * scale) }
        return CoverShapeElementView(
            shapeType: element.shapeType,
            strokeStyle: element.strokeStyle,
            strokeWidthPx: strokePx,
            dashPx: dashPx,
            isFilled: element.isFilled,
            color: elementColor(element.layer),
            fillColor: element.fill.solidColor?.color
        )
        .frame(width: pixelWidth, height: pixelHeight)
    }

    private func selectionOverlay(for element: CoverDesignElement, scale: Double) -> some View {
        let bounds = CoverEditorMath.displayBounds(for: element, geometry: geometry)
        return CoverSelectionChrome(
            width: max(16, bounds.width * scale),
            height: max(16, bounds.height * scale),
            onResizeChanged: { handle, translation in
                resizeElement(element, handle: handle, translation: translation, scale: scale)
            },
            onResizeEnded: {
                resizeStartBounds = nil
                resizingElementID = nil
                store.updateSelectedProject { $0.syncFolioStampTextFromElements() }
            },
            onRotateChanged: { localPoint in
                rotateElement(element, localPoint: localPoint, chromeWidth: max(16, bounds.width * scale), chromeHeight: max(16, bounds.height * scale))
            },
            onRotateEnded: {
                rotateGestureStartAngle = nil
                store.updateSelectedProject { $0.syncFolioStampTextFromElements() }
            },
            onDelete: {
                deleteSelected()
            }
        )
        .rotationEffect(.degrees(element.rotationDegrees))
        .position(x: bounds.centerX * scale, y: bounds.centerY * scale)
        .zIndex(3)
    }

    private func textElementLabel(
        _ element: CoverDesignElement,
        pixelWidth: CGFloat,
        pixelHeight: CGFloat,
        scale: Double
    ) -> some View {
        // 1 mm fontSize → `scale` points so the glyph box matches displayBounds / SVG.
        let fontSize = max(4, element.fontSizeMM * scale * CoverEditorMath.textDisplayFactor)
        return Text(element.text)
            .font(elementFont(element.fontStyle, size: fontSize))
            .foregroundStyle(elementColor(element.layer))
            .multilineTextAlignment(.center)
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: false)
            .frame(width: pixelWidth, height: pixelHeight, alignment: .center)
            .clipped()
    }

    private func imageElementView(_ element: CoverDesignElement, pixelWidth: CGFloat, pixelHeight: CGFloat) -> some View {
        Group {
            if let image = loadImage(for: element) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: pixelWidth, height: pixelHeight)
                    .clipped()
            } else {
                ZStack {
                    Rectangle().fill(Color.black.opacity(0.08))
                    Image(systemName: "photo")
                        .foregroundStyle(.black.opacity(0.4))
                }
                .frame(width: pixelWidth, height: pixelHeight)
            }
        }
    }

    private func elementDragGesture(_ element: CoverDesignElement, scale: Double) -> some Gesture {
        DragGesture()
            .onChanged { value in
                guard canvasTool == .select, !isLayerLocked(element.designLayerID) else { return }
                if !isDraggingElement {
                    isDraggingElement = true
                    selectedElementID = element.id
                    let originX = element.wrapCenterX(geometry: geometry)
                    elementDragOrigin = CGSize(width: originX, height: element.yMM)
                }
                let dxMM = value.translation.width / scale
                let dyMM = value.translation.height / scale
                updateElement(element.id, syncStamp: false, save: false) { el in
                    var wrapX = elementDragOrigin.width + dxMM
                    var wrapY = elementDragOrigin.height + dyMM
                    wrapX = clampWrapX(wrapX)
                    wrapY = clampWrapY(wrapY)
                    el.usesWrapCoordinates = true
                    el.xMM = wrapX
                    el.yMM = wrapY
                    el.panel = geometry.panel(containingWrapX: wrapX)
                }
            }
            .onEnded { _ in
                isDraggingElement = false
                store.updateSelectedProject { $0.syncFolioStampTextFromElements() }
            }
    }

    private func resizeElement(
        _ element: CoverDesignElement,
        handle: CoverResizeHandle,
        translation: CGSize,
        scale: Double
    ) {
        guard canvasTool == .select else { return }
        if resizingElementID != element.id || resizeStartBounds == nil {
            resizingElementID = element.id
            resizeStartBounds = CoverEditorMath.displayBounds(for: element, geometry: geometry)
            resizeStartFontSize = element.fontSizeMM
            selectedElementID = element.id
        }
        guard let start = resizeStartBounds else { return }

        // Convert drag from screen into the element's unrotated local axes.
        let radians = element.rotationDegrees * .pi / 180
        let cosA = cos(radians)
        let sinA = sin(radians)
        let localDX = (Double(translation.width) * cosA + Double(translation.height) * sinA) / scale
        let localDY = (-Double(translation.width) * sinA + Double(translation.height) * cosA) / scale

        let resized = CoverEditorMath.resizedBounds(
            from: start,
            handle: handle,
            deltaX: localDX,
            deltaY: localDY,
            locksAspectRatio: element.kind != .text && NSEvent.modifierFlags.contains(.shift)
        )

        updateElement(element.id, syncStamp: false, save: false) { el in
            el.usesWrapCoordinates = true
            el.xMM = clampWrapX(resized.centerX)
            el.yMM = clampWrapY(resized.centerY)
            el.panel = geometry.panel(containingWrapX: el.xMM)
            if el.kind == .text {
                let original = max(CoverEditorMath.minimumElementSizeMM, start.height)
                let ratio = max(0.2, resized.height / original)
                el.fontSizeMM = max(1, resizeStartFontSize * ratio)
                let measured = CoverEditorMath.measuredTextSizeMM(
                    text: el.text.isEmpty ? " " : el.text,
                    fontSizeMM: el.fontSizeMM,
                    fontStyle: el.fontStyle
                )
                el.widthMM = measured.width
                el.heightMM = measured.height
            } else {
                el.widthMM = max(CoverEditorMath.minimumElementSizeMM, resized.width)
                el.heightMM = max(CoverEditorMath.minimumElementSizeMM, resized.height)
            }
        }
    }

    private func rotateElement(
        _ element: CoverDesignElement,
        localPoint: CGPoint,
        chromeWidth: CGFloat,
        chromeHeight: CGFloat
    ) {
        let pointerAngle = CoverEditorMath.pointerAngleDegrees(
            localX: Double(localPoint.x),
            localY: Double(localPoint.y),
            width: Double(chromeWidth),
            height: Double(chromeHeight)
        )
        if rotateGestureStartAngle == nil {
            rotateGestureStartAngle = pointerAngle
            rotateElementStartDegrees = element.rotationDegrees
            selectedElementID = element.id
        }
        guard let startAngle = rotateGestureStartAngle else { return }
        let degrees = CoverEditorMath.rotationDegrees(
            pointerAngle: pointerAngle,
            gestureStartPointerAngle: startAngle,
            elementStartRotation: rotateElementStartDegrees
        )
        updateElement(element.id, syncStamp: false, save: false) { el in
            el.rotationDegrees = degrees
        }
    }

    private func loadImage(for element: CoverDesignElement) -> NSImage? {
        guard let url = element.resolvedImageURL() else { return nil }
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        return NSImage(contentsOf: url)
    }

    private func elementFont(_ style: CoverFontStyle, size: CGFloat) -> Font {
        Font(CoverEditorMath.nsFont(for: style, sizePoints: size))
    }

    private func elementColor(_ layer: CoverElementLayer) -> Color {
        finishSwatchColor(layer)
    }

    private func defaultStrokeStyle(for finish: CoverElementLayer) -> CoverStrokeStyle {
        switch finish {
        case .deboss: return .ornament
        case .foil: return .double
        case .ink: return .solid
        }
    }

    private func defaultFinishForPlacement() -> CoverElementLayer {
        activeFinish
    }

    private func placeShape(
        _ type: CoverShapeType,
        wrapX: Double,
        wrapY: Double,
        zone: CoverPanel,
        widthMM: Double? = nil,
        heightMM: Double? = nil
    ) {
        let layerID = project.activeCoverLayerID ?? project.coverDesignLayers.last?.id ?? UUID()
        let finish = defaultFinishForPlacement()
        let size: (w: Double, h: Double)
        switch type {
        case .rectangle:
            size = (widthMM ?? geometry.boardW * 0.4, heightMM ?? geometry.boardH * 0.25)
        case .ellipse:
            let side = widthMM ?? geometry.boardW * 0.3
            size = (side, heightMM ?? side)
        case .line:
            size = (widthMM ?? geometry.boardW * 0.4, 4)
        }
        let stroke = defaultStrokeStyle(for: finish)
        let fill: CoverPaint = (finish == .deboss && type != .line)
            ? .solid(.finishDefault(for: finish))
            : .none
        let new = CoverDesignElement(
            kind: .shape,
            panel: zone,
            xMM: wrapX,
            yMM: wrapY,
            widthMM: size.w,
            heightMM: size.h,
            layer: finish,
            designLayerID: layerID,
            usesWrapCoordinates: true,
            isPanelLocked: false,
            shapeType: type,
            strokeWidthMM: finish == .deboss ? 1.0 : 0.8,
            strokeStyle: stroke,
            fill: fill
        )
        store.updateSelectedProject { project in
            project.ensureCoverDesignLayers()
            if finish == .foil { project.showFoilLayer = true }
            if finish == .deboss { project.showDebossLayer = true }
            project.coverElements.append(new)
        }
        selectedElementID = new.id
        canvasTool = .select
    }

    private func handleWrapTap(at location: CGPoint, scale: Double) {
        let wrapX = clampWrapX(Double(location.x) / scale)
        let wrapY = clampWrapY(Double(location.y) / scale)
        let zone = geometry.panel(containingWrapX: wrapX)

        switch canvasTool {
        case .text:
            placeText(wrapX: wrapX, wrapY: wrapY, zone: zone)
        case .image:
            pendingImagePlacement = (wrapX, wrapY)
            showImageImporter = true
        case .rectangle, .ellipse, .line:
            if let shapeType = canvasTool.shapeType {
                placeShape(shapeType, wrapX: wrapX, wrapY: wrapY, zone: zone)
            }
        case .select:
            selectedElementID = nil
        }
    }

    private func placeText(wrapX: Double, wrapY: Double, zone: CoverPanel) {
        let layerID = project.activeCoverLayerID ?? project.coverDesignLayers.last?.id ?? UUID()
        let vertical = zone == .spine
        let fontStyle: CoverFontStyle = vertical ? .body : .subtitle
        let fontSize = vertical ? 3.5 : CoverFontStyle.subtitle.defaultSizeMM
        let label = zone == .spine ? "SPINE" : "New Text"
        let measured = CoverEditorMath.measuredTextSizeMM(
            text: label,
            fontSizeMM: fontSize,
            fontStyle: fontStyle
        )
        let new = CoverDesignElement(
            kind: .text,
            panel: zone,
            text: label,
            xMM: wrapX,
            yMM: wrapY,
            widthMM: measured.width,
            heightMM: measured.height,
            fontSizeMM: fontSize,
            rotationDegrees: vertical ? -90 : 0,
            layer: defaultFinishForPlacement(),
            fontStyle: fontStyle,
            designLayerID: layerID,
            usesWrapCoordinates: true,
            isPanelLocked: false
        )
        store.updateSelectedProject { project in
            project.ensureCoverDesignLayers()
            let finish = defaultFinishForPlacement()
            if finish == .foil { project.showFoilLayer = true }
            if finish == .deboss { project.showDebossLayer = true }
            project.coverElements.append(new)
            project.syncFolioStampTextFromElements()
        }
        selectedElementID = new.id
        canvasTool = .select
    }

    private func handleImageImport(_ result: Result<[URL], Error>) {
        let placement = pendingImagePlacement
        defer { pendingImagePlacement = nil }
        guard case .success(let urls) = result, let url = urls.first else { return }
        let wrapX = placement?.wrapX ?? geometry.totalW * 0.5
        let wrapY = placement?.wrapY ?? geometry.boardH * 0.5
        placeImage(url: url, wrapX: wrapX, wrapY: wrapY)
    }

    private func placeImage(url: URL, wrapX: Double, wrapY: Double) {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        let bookmark = try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )

        // Default: sizable art that can span onto spine/joints (full-cover print).
        let widthMM = min(geometry.totalW * 0.35, geometry.boardW * 0.75)
        var heightMM = widthMM
        if let image = NSImage(contentsOf: url), image.size.width > 0 {
            let aspect = image.size.height / image.size.width
            heightMM = min(geometry.boardH * 0.85, widthMM * Double(aspect))
        }

        let zone = geometry.panel(containingWrapX: wrapX)
        let newID = UUID()
        store.updateSelectedProject { project in
            project.ensureCoverDesignLayers()
            let layerID = project.activeCoverLayerID
                ?? project.coverDesignLayers.first?.id
                ?? UUID()
            project.coverElements.append(
                CoverDesignElement(
                    id: newID,
                    kind: .image,
                    panel: zone,
                    text: "",
                    xMM: clampWrapX(wrapX),
                    yMM: clampWrapY(wrapY),
                    widthMM: widthMM,
                    heightMM: heightMM,
                    fontSizeMM: 4,
                    layer: .ink,
                    designLayerID: layerID,
                    usesWrapCoordinates: true,
                    isPanelLocked: false,
                    imageBookmarkData: bookmark,
                    imagePathHint: url.path,
                    imageName: url.lastPathComponent
                )
            )
        }
        selectedElementID = newID
        canvasTool = .select
    }

    private func clampWrapX(_ value: Double) -> Double {
        min(max(1, value), max(1, geometry.totalW - 1))
    }

    private func clampWrapY(_ value: Double) -> Double {
        min(max(4, value), max(4, geometry.boardH - 4))
    }

    private func canvasScale(in size: CGSize) -> Double {
        let pad: CGFloat = 100
        let base: Double
        switch chrome.viewMode {
        case .fit:
            let sx = max(40, size.width - pad) / geometry.totalW
            let sy = max(40, size.height - pad) / geometry.boardH
            base = min(sx, sy, 8)
        case .oneToOne:
            base = 3.78
        }
        return base * liveZoom
    }

    private var toolHint: String {
        switch canvasTool {
        case .text: return "Click the wrap to place text · \(activeFinish.title) finish"
        case .image: return "Click the wrap to place an image"
        case .rectangle, .ellipse, .line:
            return "Drag to draw a \(canvasTool.title.lowercased()) · \(activeFinish.title) finish · click for default size"
        case .select:
            if let selected = selectedElement {
                return "\(selected.displayLabel) · \(selected.layer.title)"
            }
            return "Arrow keys nudge 1 mm (⇧10) · ⌘D duplicate · pinch or ⌘-scroll zoom"
        }
    }

    // MARK: - Inspector

    private var inspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Cover & spine")
                            .font(ArtisanTheme.sectionFont)
                            .foregroundStyle(Color(nsColor: .labelColor))

                        Text("Full wrap canvas — place art anywhere. Joint guides are print marks, not barriers.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    WorkbenchInspectorChrome.ToggleButton(isVisible: $isInspectorVisible)
                }

                collapsibleSection("Measurements", isExpanded: $measurementsExpanded, trailing: {
                    Button("Auto", action: resetAllMeasurements)
                        .buttonStyle(.borderless)
                        .font(.caption)
                        .foregroundStyle(Color(nsColor: .linkColor))
                        .help(measurementsAutoHelp)
                }) {
                    labeledControl("Board (mm)") {
                        CoverInspectorNumberField(
                            value: project.boardThicknessMM,
                            fractionDigits: 1,
                            onCommit: { setBoardThickness($0) },
                            onEditingChanged: { isInspectorEditing = $0 }
                        )
                    }
                    labeledControl("Groove (mm)") {
                        CoverInspectorNumberField(
                            value: project.hingeGapMM,
                            fractionDigits: 1,
                            onCommit: { setHingeGap($0) },
                            onEditingChanged: { isInspectorEditing = $0 }
                        )
                    }
                    labeledControl("Spine (mm)") {
                        CoverInspectorNumberField(
                            value: spineWidth,
                            fractionDigits: 1,
                            onCommit: { setSpineWidth($0) },
                            onEditingChanged: { isInspectorEditing = $0 }
                        )
                    }
                    labeledControl("Cover W") {
                        CoverInspectorNumberField(
                            value: project.widthMM,
                            fractionDigits: 0,
                            onCommit: { setCoverWidth($0) },
                            onEditingChanged: { isInspectorEditing = $0 }
                        )
                    }
                    labeledControl("Cover H") {
                        CoverInspectorNumberField(
                            value: project.heightMM,
                            fractionDigits: 0,
                            onCommit: { setCoverHeight($0) },
                            onEditingChanged: { isInspectorEditing = $0 }
                        )
                    }
                    if store.workspace(for: project.id).totalSourcePages == 0 {
                        labeledControl("Est. pages") {
                            CoverInspectorNumberField(
                                value: Double(project.estimatedPageCount),
                                fractionDigits: 0,
                                onCommit: { setEstimatedPages($0) },
                                onEditingChanged: { isInspectorEditing = $0 }
                            )
                        }
                    }
                    labeledControl("GSM") {
                        CoverInspectorNumberField(
                            value: project.textPaperGSM,
                            fractionDigits: 0,
                            onCommit: { setTextPaperGSM($0) },
                            onEditingChanged: { isInspectorEditing = $0 }
                        )
                    }

                    Divider()

                    metricRow("Binding style", bindingStyleLabel)
                    if let signatureSummaryLabel {
                        metricRow("Signatures", signatureSummaryLabel)
                    }

                    metricRow(
                        "Minimum for signatures",
                        String(format: "%.1f × %.1f mm", minimumBoardWidthMM, minimumBoardHeightMM)
                    )
                    metricRow("Text block", String(format: "%.2f mm", textBlock))
                    metricRow("Spine face", String(format: "%.1f mm", geometry.spineFace))
                    metricRow("Each joint", String(format: "%.1f mm", geometry.hinge))
                    metricRow("Midsection", String(format: "%.1f mm", geometry.midsection))
                    metricRow("Total wrap", String(format: "%.1f mm", geometry.totalW))

                    ForEach(measurementWarnings, id: \.self) { warning in
                        Label(warning, systemImage: "exclamationmark.triangle")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Text("Imposition binding style sets the Auto targets and spine formula. Trim and the book block set the recommended minimums.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                collapsibleSection("Layers", isExpanded: $layersExpanded) {
                    finishChannelBar

                    layersList

                    HStack {
                        Button {
                            store.updateSelectedProject { $0.addCoverDesignLayer() }
                        } label: {
                            Label("Add Layer", systemImage: "plus")
                        }
                        .buttonStyle(.borderless)

                        Spacer()
                    }

                    labeledControl("Material") {
                        Picker("", selection: materialBinding) {
                            ForEach(CoverMaterial.allCases) { material in
                                Text(material.rawValue).tag(material)
                            }
                        }
                        .labelsHidden()
                    }
                    Toggle("Joint / spine guides", isOn: $showJointGuides)

                    Text("Pick a tool from the toolbar, then click or drag on the wrap. Use the I/F/D swatches to set the active finish for new shapes.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if selectedElement != nil {
                    collapsibleSection("Selected", isExpanded: $selectionExpanded) {
                        selectionContent
                    }
                }

                Text(noteText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }
            .padding(16)
        }
        .background(.background)
        .tint(Color(nsColor: .controlAccentColor))
        .onDisappear {
            store.save()
        }
    }

    private var finishChannelBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Finish channels")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(CoverElementLayer.allCases) { finish in
                finishChannelRow(finish)
            }
        }
    }

    private func finishChannelRow(_ finish: CoverElementLayer) -> some View {
        let count = project.coverElements.filter { $0.layer == finish }.count
        let isVisible = finishVisible(finish)
        let isSolo = soloFinish == finish

        return HStack(spacing: 8) {
            Circle()
                .fill(finishSwatchColor(finish))
                .frame(width: 10, height: 10)

            Text(finish.title)
                .font(.caption)
                .fontWeight(isSolo ? .semibold : .regular)

            Text("\(count)")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Spacer()

            if finish != .ink {
                Button {
                    if finish == .foil {
                        store.updateSelectedProject { $0.showFoilLayer.toggle() }
                    } else {
                        store.updateSelectedProject { $0.showDebossLayer.toggle() }
                    }
                    if !finishVisible(finish), soloFinish == finish {
                        soloFinish = nil
                    }
                } label: {
                    Image(systemName: isVisible ? "eye" : "eye.slash")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .help(isVisible ? "Hide \(finish.title) on canvas" : "Show \(finish.title)")
            }

            Button {
                soloFinish = isSolo ? nil : finish
            } label: {
                Image(systemName: isSolo ? "eye.fill" : "eye")
                    .font(.caption2)
            }
            .buttonStyle(.borderless)
            .help(isSolo ? "Show all finishes" : "Solo \(finish.title)")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(isSolo ? Color.accentColor.opacity(0.12) : Color.clear)
        )
    }

    private var layersList: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(project.coverDesignLayers.sorted(by: { $0.zIndex > $1.zIndex })) { layer in
                layerRow(layer)
                if !collapsedLayerIDs.contains(layer.id) {
                    ForEach(elementsInLayer(layer.id)) { element in
                        elementRow(element, layerLocked: layer.isLocked)
                    }
                }
            }
        }
    }

    /// Layer contents, topmost element first (Illustrator/Affinity convention).
    private func elementsInLayer(_ layerID: UUID) -> [CoverDesignElement] {
        project.coverElements.filter { $0.designLayerID == layerID }.reversed()
    }

    private func layerRow(_ layer: CoverDesignLayer) -> some View {
        let isActive = project.activeCoverLayerID == layer.id
        let count = project.coverElements.filter { $0.designLayerID == layer.id }.count
        let isCollapsed = collapsedLayerIDs.contains(layer.id)

        return HStack(spacing: 6) {
            Button {
                if isCollapsed {
                    collapsedLayerIDs.remove(layer.id)
                } else {
                    collapsedLayerIDs.insert(layer.id)
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                    .foregroundStyle(.secondary)
                    .frame(width: 12)
            }
            .buttonStyle(.borderless)
            .help(isCollapsed ? "Show layer contents" : "Hide layer contents")

            Button {
                toggleLayerVisibility(layer.id)
            } label: {
                Image(systemName: layer.isVisible ? "eye" : "eye.slash")
                    .foregroundStyle(layer.isVisible ? Color.primary : Color.secondary)
            }
            .buttonStyle(.borderless)
            .help(layer.isVisible ? "Hide layer" : "Show layer")

            Button {
                toggleLayerLock(layer.id)
            } label: {
                Image(systemName: layer.isLocked ? "lock.fill" : "lock.open")
                    .foregroundStyle(layer.isLocked ? Color.primary : Color.secondary.opacity(0.55))
            }
            .buttonStyle(.borderless)
            .help(layer.isLocked ? "Unlock layer" : "Lock layer — its artwork can’t be selected or moved")

            CoverInspectorTextField(
                value: layer.name,
                placeholder: "Layer",
                isBold: isActive,
                onCommit: { name in
                    store.updateSelectedProject { $0.renameCoverDesignLayer(layer.id, to: name) }
                },
                onEditingChanged: { isInspectorEditing = $0 }
            )

            Spacer(minLength: 4)

            Button {
                store.updateSelectedProject { $0.activeCoverLayerID = layer.id }
            } label: {
                Text("\(count)")
                    .font(.caption2)
                    .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
            .help(isActive ? "Active layer — new elements land here" : "Click to make this the active layer")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isActive
                      ? Color(nsColor: .selectedContentBackgroundColor).opacity(0.22)
                      : Color(nsColor: .controlBackgroundColor).opacity(0.55))
        )
        .contextMenu {
            Button("Bring Forward") { moveLayer(layer.id, direction: 1) }
            Button("Send Backward") { moveLayer(layer.id, direction: -1) }
            Divider()
            Button("Delete Layer", role: .destructive) { deleteLayer(layer.id) }
                .disabled(project.coverDesignLayers.count <= 1)
        }
        .help(isActive ? "Active layer — new elements are added here" : "Click to make this the active layer")
    }

    private func elementRow(_ element: CoverDesignElement, layerLocked: Bool) -> some View {
        let isSelected = element.id == selectedElementID
        let finishHidden = !finishVisible(element.layer)
        return HStack(spacing: 8) {
            Image(systemName: element.listIconName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 14)

            finishBadge(element.layer)

            Text(element.displayLabel)
                .lineLimit(1)
                .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                .fontWeight(isSelected ? .semibold : .regular)
            Spacer()
            Button {
                toggleElementVisibility(element.id)
            } label: {
                Image(systemName: element.isVisible ? "eye" : "eye.slash")
                    .font(.caption2)
            }
            .buttonStyle(.borderless)
            .help(element.isVisible ? "Hide element" : "Show element")
        }
        .padding(.leading, 30)
        .padding(.trailing, 8)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.14) : Color.clear)
        )
        .opacity(layerLocked || finishHidden ? 0.45 : 1)
        .contentShape(Rectangle())
        .onTapGesture {
            guard !layerLocked else { return }
            selectedElementID = element.id
            canvasTool = .select
            activeFinish = element.layer
            store.updateSelectedProject { $0.activeCoverLayerID = element.designLayerID }
        }
        .contextMenu {
            Button("Duplicate") { duplicateElement(element.id) }
                .disabled(layerLocked)
            Button("Bring Forward") { moveElementInStack(element.id, direction: 1) }
            Button("Send Backward") { moveElementInStack(element.id, direction: -1) }
            Menu("Move to Layer") {
                ForEach(project.coverDesignLayers.sorted(by: { $0.zIndex > $1.zIndex })) { layer in
                    Button(layer.name) {
                        store.updateSelectedProject { $0.moveCoverElement(element.id, toLayer: layer.id) }
                    }
                    .disabled(layer.id == element.designLayerID)
                }
            }
            Divider()
            Button("Delete", role: .destructive) {
                store.updateSelectedProject { project in
                    project.coverElements.removeAll { $0.id == element.id }
                    project.syncFolioStampTextFromElements()
                }
                if selectedElementID == element.id {
                    selectedElementID = nil
                }
            }
        }
    }

    private func finishBadge(_ finish: CoverElementLayer) -> some View {
        Text(finish.badge)
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: 16, height: 16)
            .background(
                Circle().fill(finishSwatchColor(finish))
            )
            .help(finish.title)
    }

    @ViewBuilder
    private var selectionContent: some View {
        if let element = selectedElement {
            labeledControl("Finish") {
                HStack(spacing: 6) {
                    ForEach(CoverElementLayer.allCases) { finish in
                        Button {
                            updateElement(element.id) { $0.layer = finish }
                            activeFinish = finish
                            if finish == .foil {
                                store.updateSelectedProject { $0.showFoilLayer = true }
                            }
                            if finish == .deboss {
                                store.updateSelectedProject { $0.showDebossLayer = true }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(finishSwatchColor(finish))
                                    .frame(width: 8, height: 8)
                                Text(finish.title)
                                    .font(.caption)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(element.layer == finish
                                          ? Color.accentColor.opacity(0.18)
                                          : Color(nsColor: .controlBackgroundColor).opacity(0.5))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            labeledControl("Layer") {
                Picker("", selection: elementDesignLayerBinding(element.id)) {
                    ForEach(project.coverDesignLayers.sorted(by: { $0.zIndex > $1.zIndex })) { layer in
                        Text(layer.name).tag(layer.id)
                    }
                }
                .labelsHidden()
            }

            Divider()

            switch element.kind {
            case .text:
                labeledControl("Text") {
                    CoverInspectorTextField(
                        value: element.text,
                        placeholder: "Stamp text",
                        onCommit: { text in
                            updateElement(element.id) { el in
                                el.text = text
                                let measured = CoverEditorMath.measuredTextSizeMM(
                                    text: text.isEmpty ? " " : text,
                                    fontSizeMM: el.fontSizeMM,
                                    fontStyle: el.fontStyle
                                )
                                el.widthMM = measured.width
                                el.heightMM = measured.height
                            }
                        },
                        onEditingChanged: { isInspectorEditing = $0 }
                    )
                }
                labeledControl("Style") {
                    Picker("", selection: elementStyleBinding(element.id)) {
                        ForEach(CoverFontStyle.allCases) { style in
                            Text(style.title).tag(style)
                        }
                    }
                    .labelsHidden()
                }
                labeledControl("Size mm") {
                    CoverInspectorNumberField(
                        value: element.fontSizeMM,
                        fractionDigits: 1,
                        onCommit: { size in
                            updateElement(element.id) { el in
                                el.fontSizeMM = max(1, size)
                                let measured = CoverEditorMath.measuredTextSizeMM(
                                    text: el.text.isEmpty ? " " : el.text,
                                    fontSizeMM: el.fontSizeMM,
                                    fontStyle: el.fontStyle
                                )
                                el.widthMM = measured.width
                                el.heightMM = measured.height
                            }
                        },
                        onEditingChanged: { isInspectorEditing = $0 }
                    )
                }
            case .image:
                labeledControl("Image") {
                    Text(element.imageName.isEmpty ? "Embedded image" : element.imageName)
                        .foregroundStyle(.secondary)
                }
                labeledControl("Width mm") {
                    CoverInspectorNumberField(
                        value: element.widthMM,
                        fractionDigits: 1,
                        onCommit: { value in
                            updateElement(element.id, syncStamp: false) { $0.widthMM = max(4, value) }
                        },
                        onEditingChanged: { isInspectorEditing = $0 }
                    )
                }
                labeledControl("Height mm") {
                    CoverInspectorNumberField(
                        value: element.heightMM,
                        fractionDigits: 1,
                        onCommit: { value in
                            updateElement(element.id, syncStamp: false) { $0.heightMM = max(4, value) }
                        },
                        onEditingChanged: { isInspectorEditing = $0 }
                    )
                }
            case .shape:
                Text(element.shapeType.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help("Shape type is set at creation. Use the toolbar to draw a different shape.")
                labeledControl("Width mm") {
                    CoverInspectorNumberField(
                        value: element.widthMM,
                        fractionDigits: 1,
                        onCommit: { value in
                            updateElement(element.id, syncStamp: false) { $0.widthMM = max(4, value) }
                        },
                        onEditingChanged: { isInspectorEditing = $0 }
                    )
                }
                if element.shapeType != .line {
                    labeledControl("Height mm") {
                        CoverInspectorNumberField(
                            value: element.heightMM,
                            fractionDigits: 1,
                            onCommit: { value in
                                updateElement(element.id, syncStamp: false) { $0.heightMM = max(4, value) }
                            },
                            onEditingChanged: { isInspectorEditing = $0 }
                        )
                    }
                }
            }

            Divider()

            Text("Transform")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            labeledControl("Position") {
                HStack(spacing: 8) {
                    Text("X")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    CoverInspectorNumberField(
                        value: element.wrapCenterX(geometry: geometry),
                        fractionDigits: 1,
                        width: 56,
                        onCommit: { value in
                            updateElement(element.id, syncStamp: false) { el in
                                el.usesWrapCoordinates = true
                                el.xMM = clampWrapX(value)
                                el.panel = geometry.panel(containingWrapX: el.xMM)
                            }
                        },
                        onEditingChanged: { isInspectorEditing = $0 }
                    )
                    Text("Y")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    CoverInspectorNumberField(
                        value: element.yMM,
                        fractionDigits: 1,
                        width: 56,
                        onCommit: { value in
                            updateElement(element.id, syncStamp: false) { $0.yMM = clampWrapY(value) }
                        },
                        onEditingChanged: { isInspectorEditing = $0 }
                    )
                }
                .help("Element center in millimeters from the wrap’s top-left corner")
            }
            labeledControl("Zone") {
                Picker("", selection: elementPanelBinding(element.id)) {
                    ForEach(CoverPanel.allCases) { panel in
                        Text(panel.title).tag(panel)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .help("Snaps the element center to this zone. Art can still span across joints.")
            }
            labeledControl("Rotate") {
                AngleControl(
                    degrees: element.rotationDegrees,
                    onCommit: { value in
                        updateElement(element.id) { $0.rotationDegrees = value }
                    },
                    onEditingChanged: { isInspectorEditing = $0 }
                )
            }
            labeledControl("Opacity") {
                Slider(
                    value: elementOpacityBinding(element.id),
                    in: 0.1...1
                ) { editing in
                    if !editing {
                        store.save()
                    }
                }
            }

            if element.kind == .shape {
                Divider()

                Text("Appearance")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                labeledControl("Stroke") {
                    StrokeDashControls(
                        selected: element.strokeStyle,
                        strokeColor: finishSwatchColor(element.layer),
                        dashLengthScale: element.dashLengthScale,
                        dashGapScale: element.dashGapScale,
                        strokeWidthMM: element.strokeWidthMM,
                        onStyleChange: { style in
                            updateElement(element.id, syncStamp: false) { $0.strokeStyle = style }
                        },
                        onDashLengthChange: { value in
                            updateElement(element.id, syncStamp: false) { $0.dashLengthScale = value }
                        },
                        onDashGapChange: { value in
                            updateElement(element.id, syncStamp: false) { $0.dashGapScale = value }
                        },
                        onEditingChanged: { isInspectorEditing = $0 }
                    )
                }
                labeledControl("Stroke mm") {
                    CoverInspectorNumberField(
                        value: element.strokeWidthMM,
                        fractionDigits: 2,
                        onCommit: { value in
                            updateElement(element.id, syncStamp: false) {
                                $0.strokeWidthMM = min(10, max(0.1, value))
                            }
                        },
                        onEditingChanged: { isInspectorEditing = $0 }
                    )
                }
                if element.shapeType != .line {
                    labeledControl("Fill") {
                        FillControls(
                            fill: element.fill,
                            defaultSolid: .finishDefault(for: element.layer),
                            onChange: { paint in
                                updateElement(element.id, syncStamp: false) { $0.fill = paint }
                            }
                        )
                    }
                }
            }

            Divider()

            HStack {
                Spacer()

                Button(role: .destructive) {
                    deleteSelected()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .keyboardShortcut(.delete, modifiers: [])
                .help("Delete selected element (Delete key)")
            }
        }
    }

    private var noteText: String {
        let pages = max(pageCount, 0)
        guard pages > 0 else {
            return "Enter estimated pages (or assemble a book block) to calculate spine width for \(coverArchitecture.rawValue)."
        }

        let job = effectiveBindingJob
        if job.bindingStyle == .saddleStitch {
            let nestedPages = resolvedBindingPlan?.pagesPerSignature ?? pages
            return String(
                format: "%@ spine — 1 nested %d-page signature, %.0f gsm, %.1f mm cover. Text block ≈ %.2f mm.",
                coverArchitecture.rawValue,
                nestedPages,
                project.textPaperGSM,
                project.boardThicknessMM,
                textBlock
            )
        }

        if let plan = resolvedBindingPlan, plan.signatureCount > 0 {
            return String(
                format: "%@ spine — %d × %d-page signatures, %.0f gsm, %.1f mm board, %.1f mm grooves. Text block ≈ %.2f mm.",
                coverArchitecture.rawValue,
                plan.signatureCount,
                plan.pagesPerSignature,
                project.textPaperGSM,
                project.boardThicknessMM,
                project.hingeGapMM,
                textBlock
            )
        }

        return String(
            format: "%@ spine — %.0f gsm, %.1f mm board, %.1f mm grooves. Text block ≈ %.2f mm.",
            coverArchitecture.rawValue,
            project.textPaperGSM,
            project.boardThicknessMM,
            project.hingeGapMM,
            textBlock
        )
    }

    private var measurementsAutoHelp: String {
        String(
            format: "Reset board, groove, spine, cover trim, and paper to %@ defaults",
            bindingStyleLabel
        )
    }

    private func collapsibleSection<Content: View>(
        _ title: String,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: () -> Content
    ) -> some View {
        collapsibleSection(title, isExpanded: isExpanded, trailing: { EmptyView() }, content: content)
    }

    private func collapsibleSection<Content: View, Trailing: View>(
        _ title: String,
        isExpanded: Binding<Bool>,
        @ViewBuilder trailing: () -> Trailing,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        isExpanded.wrappedValue.toggle()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(isExpanded.wrappedValue ? 90 : 0))
                        Text(title.uppercased())
                            .font(ArtisanTheme.labelFont)
                            .tracking(0.6)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)

                Spacer(minLength: 0)

                trailing()
            }
            .padding(.vertical, 6)

            if isExpanded.wrappedValue {
                VStack(alignment: .leading, spacing: 10) {
                    content()
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: ArtisanTheme.controlRadius, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor).opacity(0.55))
                )
                .overlay {
                    RoundedRectangle(cornerRadius: ArtisanTheme.controlRadius, style: .continuous)
                        .strokeBorder(Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 1)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func labeledControl<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 78, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
    }

    private func metricRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(ArtisanTheme.technicalFont)
        }
    }

    // MARK: - Mutations

    private func setBoardThickness(_ value: Double) {
        store.updateSelectedProject { $0.boardThicknessMM = max(0.5, value) }
    }

    private func setHingeGap(_ value: Double) {
        store.updateSelectedProject { $0.hingeGapMM = max(0, value) }
    }

    private func setSpineWidth(_ value: Double) {
        store.updateSelectedProject {
            $0.spineWidthOverrideMM = CoverEditorMath.spineWidthOverride(proposed: value)
        }
    }

    private func setCoverWidth(_ value: Double) {
        store.updateSelectedProject {
            $0.widthMM = CoverEditorMath.boardSize(current: $0.widthMM, proposed: value)
        }
    }

    private func setCoverHeight(_ value: Double) {
        store.updateSelectedProject {
            $0.heightMM = CoverEditorMath.boardSize(current: $0.heightMM, proposed: value)
        }
    }

    private func setEstimatedPages(_ value: Double) {
        store.updateSelectedProject { $0.estimatedPageCount = max(0, Int(value.rounded())) }
    }

    private func setTextPaperGSM(_ value: Double) {
        store.updateSelectedProject { $0.textPaperGSM = max(1, value) }
    }

    private func resetAllMeasurements() {
        let defaults = coverMeasurementDefaults
        let clearPageEstimate = store.workspace(for: project.id).totalSourcePages == 0
        store.updateSelectedProject {
            $0.boardThicknessMM = defaults.boardThicknessMM
            $0.hingeGapMM = defaults.hingeGapMM
            $0.spineWidthOverrideMM = nil
            $0.widthMM = minimumBoardWidthMM
            $0.heightMM = minimumBoardHeightMM
            $0.textPaperGSM = defaults.textPaperGSM
            if clearPageEstimate {
                $0.estimatedPageCount = 0
            }
        }
    }

    private func toggleLayerVisibility(_ id: UUID) {
        store.updateSelectedProject { project in
            guard let index = project.coverDesignLayers.firstIndex(where: { $0.id == id }) else { return }
            project.coverDesignLayers[index].isVisible.toggle()
        }
    }

    private func toggleLayerLock(_ id: UUID) {
        let willLock = !(project.coverDesignLayers.first { $0.id == id }?.isLocked ?? false)
        store.updateSelectedProject { project in
            guard let index = project.coverDesignLayers.firstIndex(where: { $0.id == id }) else { return }
            project.coverDesignLayers[index].isLocked.toggle()
        }
        if willLock, let element = selectedElement, element.designLayerID == id {
            selectedElementID = nil
        }
    }

    private func toggleElementVisibility(_ id: UUID) {
        updateElement(id, syncStamp: false) { $0.isVisible.toggle() }
    }

    private func deleteLayer(_ id: UUID) {
        store.updateSelectedProject { $0.removeCoverDesignLayer(id) }
    }

    private func moveElementInStack(_ id: UUID, direction: Int) {
        store.updateSelectedProject { $0.moveCoverElementWithinLayer(id, direction: direction) }
    }

    private func moveLayer(_ id: UUID, direction: Int) {
        store.updateSelectedProject { project in
            guard let index = project.coverDesignLayers.firstIndex(where: { $0.id == id }) else { return }
            let current = project.coverDesignLayers[index].zIndex
            let targetZ = current + direction
            guard let swapIndex = project.coverDesignLayers.firstIndex(where: { $0.zIndex == targetZ }) else { return }
            project.coverDesignLayers[index].zIndex = targetZ
            project.coverDesignLayers[swapIndex].zIndex = current
        }
    }

    private func updateElement(
        _ id: UUID,
        syncStamp: Bool = true,
        save: Bool = true,
        mutate: (inout CoverDesignElement) -> Void
    ) {
        store.updateSelectedProject(save: save) { project in
            guard let index = project.coverElements.firstIndex(where: { $0.id == id }) else { return }
            mutate(&project.coverElements[index])
            if syncStamp {
                project.syncFolioStampTextFromElements()
            }
        }
    }

    private func duplicateElement(_ id: UUID) {
        guard let element = project.coverElements.first(where: { $0.id == id }),
              !isLayerLocked(element.designLayerID) else { return }
        var copy = element
        copy.id = UUID()
        copy.usesWrapCoordinates = true
        copy.xMM = clampWrapX(element.wrapCenterX(geometry: geometry) + 4)
        copy.yMM = clampWrapY(element.yMM + 4)
        copy.panel = geometry.panel(containingWrapX: copy.xMM)
        store.updateSelectedProject { $0.coverElements.append(copy) }
        selectedElementID = copy.id
        canvasTool = .select
    }

    private func duplicateSelected() {
        guard let id = selectedElementID else { return }
        duplicateElement(id)
    }

    private func nudgeSelected(dxMM: Double, dyMM: Double) {
        guard let element = selectedElement, !isLayerLocked(element.designLayerID) else { return }
        updateElement(element.id, syncStamp: false) { el in
            el.usesWrapCoordinates = true
            el.xMM = clampWrapX(el.wrapCenterX(geometry: geometry) + dxMM)
            el.yMM = clampWrapY(el.yMM + dyMM)
            el.panel = geometry.panel(containingWrapX: el.xMM)
        }
    }

    private func deleteSelected() {
        guard let id = selectedElementID else { return }
        store.updateSelectedProject { project in
            project.coverElements.removeAll { $0.id == id }
            project.syncFolioStampTextFromElements()
        }
        selectedElementID = nil
    }

    private func elementPanelBinding(_ id: UUID) -> Binding<CoverPanel> {
        Binding(
            get: {
                let el = project.coverElements.first { $0.id == id }
                let wrapX = el.map { $0.wrapCenterX(geometry: geometry) } ?? 0
                return geometry.panel(containingWrapX: wrapX)
            },
            set: { value in
                updateElement(id) { el in
                    el.panel = value
                    el.usesWrapCoordinates = true
                    el.isPanelLocked = false
                    el.xMM = geometry.panelOriginX(value) + geometry.panelWidth(value) * 0.5
                    if el.kind == .text {
                        if value == .spine, abs(el.rotationDegrees) < 1 {
                            el.rotationDegrees = -90
                        } else if value != .spine, abs(el.rotationDegrees + 90) < 1 {
                            el.rotationDegrees = 0
                        }
                    }
                }
            }
        )
    }

    private func elementLayerBinding(_ id: UUID) -> Binding<CoverElementLayer> {
        Binding(
            get: { project.coverElements.first { $0.id == id }?.layer ?? .ink },
            set: { value in
                updateElement(id) { $0.layer = value }
                if value == .foil {
                    store.updateSelectedProject { $0.showFoilLayer = true }
                }
                if value == .deboss {
                    store.updateSelectedProject { $0.showDebossLayer = true }
                }
            }
        )
    }

    private func elementDesignLayerBinding(_ id: UUID) -> Binding<UUID> {
        Binding(
            get: {
                project.coverElements.first { $0.id == id }?.designLayerID
                    ?? project.activeCoverLayerID
                    ?? project.coverDesignLayers.first?.id
                    ?? UUID()
            },
            set: { value in updateElement(id, syncStamp: false) { $0.designLayerID = value } }
        )
    }

    private func elementStyleBinding(_ id: UUID) -> Binding<CoverFontStyle> {
        Binding(
            get: { project.coverElements.first { $0.id == id }?.fontStyle ?? .body },
            set: { value in
                updateElement(id) { el in
                    el.fontStyle = value
                    if el.fontSizeMM < 1 {
                        el.fontSizeMM = value.defaultSizeMM
                    }
                    if el.kind == .text {
                        let measured = CoverEditorMath.measuredTextSizeMM(
                            text: el.text.isEmpty ? " " : el.text,
                            fontSizeMM: el.fontSizeMM,
                            fontStyle: el.fontStyle
                        )
                        el.widthMM = measured.width
                        el.heightMM = measured.height
                    }
                }
            }
        )
    }

    private func elementOpacityBinding(_ id: UUID) -> Binding<Double> {
        Binding(
            get: { project.coverElements.first { $0.id == id }?.opacity ?? 1 },
            set: { value in
                updateElement(id, syncStamp: false, save: false) { $0.opacity = min(1, max(0.1, value)) }
            }
        )
    }

    private var materialBinding: Binding<CoverMaterial> {
        Binding(
            get: { project.coverMaterial },
            set: { value in store.updateSelectedProject { $0.coverMaterial = value } }
        )
    }

    private var foilBinding: Binding<Bool> {
        Binding(
            get: { project.showFoilLayer },
            set: { value in store.updateSelectedProject { $0.showFoilLayer = value } }
        )
    }

    private var debossBinding: Binding<Bool> {
        Binding(
            get: { project.showDebossLayer },
            set: { value in store.updateSelectedProject { $0.showDebossLayer = value } }
        )
    }
}

private struct CoverFocusRingDisabled: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 14.0, *) {
            content.focusEffectDisabled()
        } else {
            content
        }
    }
}

private struct CoverSelectionChrome: View {
    let width: CGFloat
    let height: CGFloat
    var onResizeChanged: (CoverResizeHandle, CGSize) -> Void
    var onResizeEnded: () -> Void
    var onRotateChanged: (CGPoint) -> Void
    var onRotateEnded: () -> Void
    var onDelete: () -> Void

    private let handleSize: CGFloat = 9
    private let rotateReach: CGFloat = 28
    /// Keep the delete badge clear of the top-trailing resize handle hit area.
    private var deleteBadgeOffset: CGFloat { handleSize + 14 }

    var body: some View {
        ZStack {
            Rectangle()
                .strokeBorder(Color.accentColor, lineWidth: 1.5)
                .allowsHitTesting(false)

            ForEach(CoverResizeHandle.allCases) { handle in
                handleView(handle)
                    .position(position(for: handle))
            }
        }
        .frame(width: width, height: height)
        .coordinateSpace(name: "selectionChrome")
        .overlay(alignment: .top) {
            rotateControl
                .offset(y: -(rotateReach + handleSize * 0.35))
        }
        .overlay(alignment: .topTrailing) {
            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, Color.red.opacity(0.92))
                    .font(.system(size: 14))
            }
            .buttonStyle(.plain)
            .focusable(false)
            .offset(x: deleteBadgeOffset, y: -deleteBadgeOffset)
            .help("Delete selected element")
        }
        .compositingGroup()
        .modifier(CoverFocusRingDisabled())
    }

    private var rotateControl: some View {
        VStack(spacing: 0) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Color.accentColor)
                .padding(5)
                .background(Circle().fill(Color(nsColor: .textBackgroundColor)))
                .overlay(Circle().strokeBorder(Color.accentColor, lineWidth: 1.25))
                .contentShape(Circle().inset(by: -10))
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .named("selectionChrome"))
                        .onChanged { value in
                            onRotateChanged(value.location)
                        }
                        .onEnded { _ in
                            onRotateEnded()
                        }
                )
                .help("Drag to rotate")

            Rectangle()
                .fill(Color.accentColor)
                .frame(width: 1.25, height: rotateReach - 4)
        }
        .allowsHitTesting(true)
    }

    private func handleView(_ handle: CoverResizeHandle) -> some View {
        RoundedRectangle(cornerRadius: 1, style: .continuous)
            .fill(Color(nsColor: .textBackgroundColor))
            .frame(width: handleSize, height: handleSize)
            .overlay {
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: 1)
            }
            .contentShape(Rectangle().inset(by: -6))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        onResizeChanged(handle, value.translation)
                    }
                    .onEnded { _ in
                        onResizeEnded()
                    }
            )
            .help("Drag to resize. Hold Shift to keep image proportions.")
    }

    private func position(for handle: CoverResizeHandle) -> CGPoint {
        switch handle {
        case .topLeft:
            return CGPoint(x: 0, y: 0)
        case .top:
            return CGPoint(x: width * 0.5, y: 0)
        case .topRight:
            return CGPoint(x: width, y: 0)
        case .right:
            return CGPoint(x: width, y: height * 0.5)
        case .bottomRight:
            return CGPoint(x: width, y: height)
        case .bottom:
            return CGPoint(x: width * 0.5, y: height)
        case .bottomLeft:
            return CGPoint(x: 0, y: height)
        case .left:
            return CGPoint(x: 0, y: height * 0.5)
        }
    }
}
