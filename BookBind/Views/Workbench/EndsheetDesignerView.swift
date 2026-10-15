import AppKit
import SwiftUI

/// Endsheet workbench sharing the cover editor’s design-document model:
/// layers, shapes, fill/stroke (incl. marbled), multi-select, group, align.
struct EndsheetDesignerView: View {
    @EnvironmentObject private var store: AppStore
    let project: BinderyProject
    @ObservedObject var workspace: BindingWorkspace
    @ObservedObject var chrome: CoverEditorChrome
    @Binding var editingFront: Bool

    @AppStorage(WorkbenchInspectorChrome.visibilityKey) private var isInspectorVisible = true
    @State private var measurementsExpanded = true
    @State private var layersExpanded = true
    @State private var selectionExpanded = true
    @State private var canvasTool: DesignCanvasTool = .select
    @State private var selectedIDs: Set<UUID> = []
    @State private var primaryID: UUID?
    @State private var liveZoom: Double = 1
    @GestureState private var pinchMagnification: CGFloat = 1
    @State private var showMarbleEditor = false
    @State private var marbleEditorSpec = MarbledPaperSpec()
    @State private var marbleEditorElementID: UUID?

    private var geometry: EndsheetGeometry {
        EndsheetGeometry.resolving(project: project, trimPoints: workspace.job.resolvedTrimSize)
    }

    private var face: EndpaperFaceDesign {
        editingFront ? project.endsheets.front : project.endsheets.back
    }

    private var document: DesignDocument { face.document }

    private var sheetW: Double { geometry.totalW }
    private var sheetH: Double { geometry.leafH }

    private var zoom: Double { liveZoom * Double(pinchMagnification) }

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                canvasToolbar
                Divider()
                canvasHost
            }
            .frame(minWidth: 420)

            if isInspectorVisible {
                inspector
            }
        }
        .onAppear {
            liveZoom = chrome.zoomFactor
            ensureDocument()
        }
        .onChange(of: editingFront) { _ in
            selectedIDs = []
            primaryID = nil
            ensureDocument()
        }
        .onChange(of: chrome.zoomFactor) { liveZoom = $0 }
        .onDisappear { store.save() }
        .sheet(isPresented: $showMarbleEditor) {
            MarblingEditorView(
                spec: $marbleEditorSpec,
                pageSize: geometry.sheetSizePoints,
                onDone: {
                    commitMarbleEditor()
                    showMarbleEditor = false
                }
            )
            .frame(minWidth: 960, minHeight: 640)
        }
    }

    // MARK: - Toolbar

    private var canvasToolbar: some View {
        HStack(spacing: 10) {
            Picker("", selection: $editingFront) {
                Text("Front").tag(true)
                Text("Back").tag(false)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 160)

            toolStrip

            Spacer(minLength: 0)

            if selectedIDs.count >= 2 {
                Button("Group") { groupSelection() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Button("Ungroup") { ungroupSelection() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }

            Button {
                duplicateSelection()
            } label: {
                Image(systemName: "plus.square.on.square")
            }
            .disabled(selectedIDs.isEmpty)
            .help("Duplicate")

            Button(role: .destructive) {
                deleteSelection()
            } label: {
                Image(systemName: "trash")
            }
            .disabled(selectedIDs.isEmpty)

            Button {
                openMarbleEditor(for: selectedElement)
            } label: {
                Label("Marble editor", systemImage: "paintbrush.pointed")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Open the interactive Marblizer-class marble editor")

            Text("Flat endsheet · fold guides are print marks, not artwork.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var toolStrip: some View {
        HStack(spacing: 4) {
            ForEach([DesignCanvasTool.select, .rectangle, .ellipse, .line, .text], id: \.self) { tool in
                Button {
                    canvasTool = tool
                } label: {
                    Image(systemName: tool.systemImage)
                }
                .buttonStyle(.bordered)
                .tint(canvasTool == tool ? Color.accentColor : Color.secondary)
                .help(tool.title)
            }
        }
    }

    // MARK: - Canvas

    private var canvasHost: some View {
        GeometryReader { geo in
            let scale = canvasScale(in: geo.size)
            let w = sheetW * scale
            let h = sheetH * scale
            ScrollView([.horizontal, .vertical]) {
                ZStack(alignment: .topLeading) {
                    sheetBody(width: w, height: h, scale: scale)
                    if face.showFoldGuides {
                        foldGuideOverlay(width: w, height: h, scale: scale)
                    }
                }
                .frame(width: w, height: h)
                .padding(40)
                .frame(
                    minWidth: max(geo.size.width, w + 80),
                    minHeight: max(geo.size.height, h + 80)
                )
            }
            .background(ArtisanTheme.canvasBackground)
            .gesture(MagnificationGesture().updating($pinchMagnification) { value, state, _ in
                state = value
            })
        }
    }

    private func sheetBody(width: CGFloat, height: CGFloat, scale: Double) -> some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Color.white)
                .frame(width: width, height: height)
                .shadow(color: .black.opacity(0.2), radius: 8, y: 2)
                .contentShape(Rectangle())
                .onTapGesture { location in
                    handleSheetTap(at: location, scale: scale)
                }

            ForEach(document.orderedElementsForRendering()) { element in
                elementView(element, scale: scale)
            }
        }
    }

    private func foldGuideOverlay(width: CGFloat, height: CGFloat, scale: Double) -> some View {
        let foldX = geometry.foldXMM * scale
        let left = geometry.zone(forHalfIndex: 0, isFront: editingFront)
        let right = geometry.zone(forHalfIndex: 1, isFront: editingFront)
        return ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Color.blue.opacity(0.04))
                .frame(width: foldX, height: height)
            Rectangle()
                .fill(Color.orange.opacity(0.04))
                .frame(width: width - foldX, height: height)
                .offset(x: foldX)
            Path { path in
                path.move(to: CGPoint(x: foldX, y: 0))
                path.addLine(to: CGPoint(x: foldX, y: height))
            }
            .stroke(Color(red: 0, green: 0.125, blue: 0.27).opacity(0.85),
                    style: StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
            Text(left.title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .position(x: foldX * 0.5, y: height + 12)
            Text(right.title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .position(x: foldX + (width - foldX) * 0.5, y: height + 12)
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func elementView(_ element: DesignElement, scale: Double) -> some View {
        let w = max(4, element.widthMM) * scale
        let h = max(4, element.heightMM) * scale
        let x = element.centerXMM * scale
        let y = element.centerYMM * scale
        let selected = selectedIDs.contains(element.id)

        Group {
            switch element.kind {
            case .shape:
                shapeView(element, pixelW: w, pixelH: h, scale: scale)
            case .text:
                Text(element.text.isEmpty ? "Text" : element.text)
                    .font(.system(size: max(8, element.fontSizeMM * scale)))
                    .foregroundStyle(element.fill.solidColor?.color ?? .primary)
            case .image:
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.gray.opacity(0.2))
                    .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
            }
        }
        .frame(width: w, height: h)
        .opacity(element.opacity)
        .rotationEffect(.degrees(element.rotationDegrees))
        .overlay {
            if selected {
                Rectangle()
                    .strokeBorder(Color.accentColor, lineWidth: 1.5)
            }
        }
        .position(x: x, y: y)
        .gesture(
            DragGesture()
                .onChanged { value in
                    guard !isLocked(element.designLayerID) else { return }
                    if !selectedIDs.contains(element.id) {
                        select(element, additive: false)
                    }
                    let dx = value.translation.width / scale
                    let dy = value.translation.height / scale
                    // Live drag uses cumulative from start — apply via gesture start snapshot ideally;
                    // for simplicity nudge from original on each change by resetting from store.
                    _ = (dx, dy)
                }
        )
        .highPriorityGesture(
            TapGesture().onEnded {
                select(
                    element,
                    additive: NSEvent.modifierFlags.contains(.shift)
                        || NSEvent.modifierFlags.contains(.command)
                )
                canvasTool = .select
            }
        )
        .onDragGestureEndedTranslate(scale: scale, element: element, selectedIDs: selectedIDs, mutate: translateSelection)
    }

    private func shapeView(_ element: DesignElement, pixelW: CGFloat, pixelH: CGFloat, scale: Double) -> some View {
        let marble: NSImage? = {
            guard let spec = element.fill.marbling else { return nil }
            return MarbledPaperGenerator.nsImage(
                spec: spec,
                sizePoints: CGSize(width: pixelW, height: pixelH),
                dpi: 120
            )
        }()
        return CoverShapeElementView(
            shapeType: element.shapeType.asCoverShape,
            strokeStyle: element.strokeStyle,
            ornamentPattern: element.ornamentPattern,
            strokeWidthPx: element.isStroked ? max(0.5, element.strokeWidthMM * scale) : 0,
            dashPx: element.strokeDashPatternMM().map { CGFloat($0 * scale) },
            isFilled: element.isFilled,
            color: element.stroke.solidColor?.color ?? .primary,
            fillColor: element.fill.solidColor?.color,
            marbleFill: marble
        )
    }

    // MARK: - Inspector

    private var inspector: some View {
        WorkbenchInspectorChrome.Panel {
            VStack(alignment: .leading, spacing: 14) {
                collapsible("Measurements", isExpanded: $measurementsExpanded) {
                    LabeledContent("Leaf") {
                        Text(String(format: "%.1f × %.1f mm", geometry.leafW, geometry.leafH))
                            .font(.body.monospacedDigit())
                    }
                    LabeledContent("Sheet") {
                        Text(String(format: "%.1f × %.1f mm", geometry.totalW, geometry.leafH))
                            .font(.body.monospacedDigit())
                    }
                    Toggle("Fold guides", isOn: faceShowFoldGuidesBinding)
                }

                collapsible("Layers", isExpanded: $layersExpanded) {
                    ForEach(document.layers.sorted(by: { $0.zIndex > $1.zIndex })) { layer in
                        HStack {
                            Text(layer.name)
                            Spacer()
                            if document.activeLayerID == layer.id {
                                Image(systemName: "pencil")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            updateDocument { $0.activeLayerID = layer.id }
                        }
                    }
                    Button {
                        updateDocument { $0.addLayer() }
                    } label: {
                        Label("Add Layer", systemImage: "plus")
                    }
                    .buttonStyle(.borderless)
                }

                collapsible("Selected", isExpanded: $selectionExpanded) {
                    if let element = selectedElement {
                        selectionInspector(element)
                    } else {
                        Text("Select an element, or draw a shape on the sheet.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        legacyModeQuickFill
                    }
                }
            }
            .horizontallyScrollable(minWidth: 220)
        }
    }

    @ViewBuilder
    private func selectionInspector(_ element: DesignElement) -> some View {
        Text(element.displayLabel)
            .font(.headline)
        if element.kind == .shape {
            labeled("Fill") {
                PaintColorWell(
                    paint: element.fill,
                    defaultSolid: .inkBlack,
                    allowsNone: true,
                    allowsMarble: true,
                    onChange: { paint in
                        updateElement(element.id) { $0.fill = paint }
                        if case let .marbled(spec) = paint {
                            updateFace { $0.mode = .marbled; $0.marbling = spec }
                        }
                    }
                )
            }
            labeled("Stroke") {
                PaintColorWell(
                    paint: element.stroke,
                    defaultSolid: .inkBlack,
                    allowsNone: true,
                    allowsMarble: false,
                    onChange: { paint in
                        updateElement(element.id) { $0.stroke = paint }
                    }
                )
            }
            if element.fill.marbling != nil {
                MarblingInspectorControls(
                    spec: Binding(
                        get: {
                            element.fill.marbling
                                ?? face.marbling
                                ?? MarbledPaperSpec()
                        },
                        set: { newSpec in
                            updateElement(element.id) { $0.fill = .marbled(newSpec) }
                            updateFace { $0.marbling = newSpec; $0.mode = .marbled }
                        }
                    ),
                    onOpenEditor: {
                        openMarbleEditor(for: element)
                    }
                )
            }
        }
        if selectedIDs.count >= 2 {
            Menu("Align") {
                ForEach(DesignAlignEdge.allCases) { edge in
                    Button(edge.title) { alignSelection(edge) }
                }
            }
        }
    }

    private var legacyModeQuickFill: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Quick fill (full sheet)")
                .font(.caption.weight(.semibold))
            Button("Blank sheet") {
                updateDocument { $0.elements.removeAll() }
                updateFace { $0.mode = .blank }
            }
            Button("Solid ivory") {
                seedSolidFill(.archivalIvory)
            }
            Button("Marbled paper") {
                seedMarbledFill()
            }
            Button("Open Marble editor…") {
                openMarbleEditor(for: nil)
            }
        }
    }

    // MARK: - Actions

    private func ensureDocument() {
        store.updateSelectedEndsheets { design in
            if editingFront {
                design.front.ensureDesignDocument(geometry: geometry)
            } else {
                design.back.ensureDesignDocument(geometry: geometry)
            }
        }
    }

    private func handleSheetTap(at location: CGPoint, scale: Double) {
        let x = Double(location.x) / scale
        let y = Double(location.y) / scale
        switch canvasTool {
        case .select:
            selectedIDs = []
            primaryID = nil
        case .rectangle, .ellipse, .line:
            if let coverShape = canvasTool.shapeType {
                placeShape(type: DesignShapeType(coverShape), atX: x, atY: y)
            }
        case .text:
            placeText(atX: x, atY: y)
        case .image:
            break
        }
    }

    private func placeShape(type: DesignShapeType, atX x: Double, atY y: Double) {
        guard let layerID = document.activeLayerID ?? document.layers.first?.id else { return }
        let size = type == .line ? 40.0 : 28.0
        let element = DesignElement(
            kind: .shape,
            xMM: max(0, x - size / 2),
            yMM: max(0, y - (type == .line ? 1 : size / 2)),
            widthMM: size,
            heightMM: type == .line ? 2 : size,
            designLayerID: layerID,
            shapeType: type,
            stroke: .solid(.inkBlack),
            fill: type == .line ? .none : .none
        )
        updateDocument { $0.elements.append(element) }
        selectedIDs = [element.id]
        primaryID = element.id
        canvasTool = .select
    }

    private func placeText(atX x: Double, atY y: Double) {
        guard let layerID = document.activeLayerID ?? document.layers.first?.id else { return }
        let element = DesignElement(
            kind: .text,
            text: "Text",
            xMM: max(0, x - 10),
            yMM: max(0, y - 4),
            widthMM: 40,
            heightMM: 10,
            fontSizeMM: 6,
            designLayerID: layerID,
            fill: .solid(.inkBlack)
        )
        updateDocument { $0.elements.append(element) }
        selectedIDs = [element.id]
        primaryID = element.id
        canvasTool = .select
    }

    private func seedSolidFill(_ color: EndpaperColor) {
        guard let layerID = document.activeLayerID ?? document.layers.first?.id else { return }
        let element = DesignElement(
            kind: .shape,
            xMM: 0, yMM: 0,
            widthMM: sheetW, heightMM: sheetH,
            designLayerID: layerID,
            shapeType: .rectangle,
            stroke: .none,
            fill: .solid(CodableColor(cgColor: color.cgColor))
        )
        updateDocument {
            $0.elements.removeAll()
            $0.elements.append(element)
        }
        updateFace {
            $0.mode = .solidColor
            $0.solidColor = color
        }
    }

    private func seedMarbledFill() {
        guard let layerID = document.activeLayerID ?? document.layers.first?.id else { return }
        var marble = MarbledPaperSpec()
        marble.regenerateVariation()
        let element = DesignElement(
            kind: .shape,
            xMM: 0, yMM: 0,
            widthMM: sheetW, heightMM: sheetH,
            designLayerID: layerID,
            shapeType: .rectangle,
            stroke: .none,
            fill: .marbled(marble)
        )
        updateDocument {
            $0.elements.removeAll()
            $0.elements.append(element)
        }
        updateFace {
            $0.mode = .marbled
            $0.marbling = marble
        }
        selectedIDs = [element.id]
        primaryID = element.id
    }

    private func openMarbleEditor(for element: DesignElement?) {
        if let element, let marble = element.fill.marbling {
            marbleEditorSpec = marble
            marbleEditorElementID = element.id
        } else if let faceMarble = face.marbling {
            marbleEditorSpec = faceMarble
            marbleEditorElementID = element?.id
        } else {
            var marble = MarbledPaperSpec()
            marble.regenerateVariation()
            marbleEditorSpec = marble
            marbleEditorElementID = element?.id
        }
        showMarbleEditor = true
    }

    private func commitMarbleEditor() {
        let marble = marbleEditorSpec
        if let id = marbleEditorElementID,
           document.elements.contains(where: { $0.id == id }) {
            updateElement(id) { $0.fill = .marbled(marble) }
        } else {
            // Seed a full-sheet marbled shape when opening from empty selection.
            guard let layerID = document.activeLayerID ?? document.layers.first?.id else {
                updateFace { $0.mode = .marbled; $0.marbling = marble }
                return
            }
            let element = DesignElement(
                kind: .shape,
                xMM: 0, yMM: 0,
                widthMM: sheetW, heightMM: sheetH,
                designLayerID: layerID,
                shapeType: .rectangle,
                stroke: .none,
                fill: .marbled(marble)
            )
            updateDocument {
                $0.elements.removeAll { $0.fill.isMarbled && $0.widthMM >= sheetW * 0.9 }
                $0.elements.insert(element, at: 0)
            }
            selectedIDs = [element.id]
            primaryID = element.id
        }
        updateFace {
            $0.mode = .marbled
            $0.marbling = marble
        }
        marbleEditorElementID = nil
    }

    private func select(_ element: DesignElement, additive: Bool) {
        if additive {
            if selectedIDs.contains(element.id) {
                selectedIDs.remove(element.id)
            } else {
                selectedIDs.insert(element.id)
            }
            selectedIDs = DesignEditorMath.expandSelection(
                selectedIDs: selectedIDs,
                frames: document.elements.map(\.designFrame)
            )
            primaryID = selectedIDs.contains(element.id) ? element.id : selectedIDs.first
        } else {
            var ids: Set<UUID> = [element.id]
            if let gid = element.groupID {
                for el in document.elements where el.groupID == gid { ids.insert(el.id) }
            }
            selectedIDs = ids
            primaryID = element.id
        }
    }

    private var selectedElement: DesignElement? {
        guard let primaryID else { return nil }
        return document.elements.first(where: { $0.id == primaryID })
    }

    private func deleteSelection() {
        let ids = selectedIDs
        updateDocument { $0.elements.removeAll { ids.contains($0.id) } }
        selectedIDs = []
        primaryID = nil
    }

    private func duplicateSelection() {
        var newIDs: Set<UUID> = []
        updateDocument { doc in
            let copies = doc.elements.filter { selectedIDs.contains($0.id) }.map { el -> DesignElement in
                var copy = el
                copy.id = UUID()
                copy.xMM += 4
                copy.yMM += 4
                newIDs.insert(copy.id)
                return copy
            }
            doc.elements.append(contentsOf: copies)
        }
        selectedIDs = newIDs
        primaryID = newIDs.first
    }

    private func groupSelection() {
        guard selectedIDs.count >= 2 else { return }
        let gid = UUID()
        updateDocument { doc in
            for i in doc.elements.indices where selectedIDs.contains(doc.elements[i].id) {
                doc.elements[i].groupID = gid
            }
        }
    }

    private func ungroupSelection() {
        updateDocument { doc in
            for i in doc.elements.indices where selectedIDs.contains(doc.elements[i].id) {
                doc.elements[i].groupID = nil
            }
        }
    }

    private func alignSelection(_ edge: DesignAlignEdge) {
        let frames = document.elements.filter { selectedIDs.contains($0.id) }.map(\.designFrame)
        let aligned = DesignEditorMath.align(frames, edge: edge)
        applyFrames(aligned)
    }

    private func translateSelection(dx: Double, dy: Double, ids: Set<UUID>) {
        updateDocument { doc in
            for i in doc.elements.indices where ids.contains(doc.elements[i].id) {
                doc.elements[i].xMM += dx
                doc.elements[i].yMM += dy
            }
        }
    }

    private func applyFrames(_ frames: [DesignFrame]) {
        let byID = Dictionary(uniqueKeysWithValues: frames.map { ($0.id, $0) })
        updateDocument { doc in
            for i in doc.elements.indices {
                guard let frame = byID[doc.elements[i].id] else { continue }
                doc.elements[i].xMM = frame.xMM
                doc.elements[i].yMM = frame.yMM
                doc.elements[i].widthMM = frame.widthMM
                doc.elements[i].heightMM = frame.heightMM
            }
        }
    }

    private func isLocked(_ layerID: UUID) -> Bool {
        document.layers.first(where: { $0.id == layerID })?.isLocked == true
    }

    private func canvasScale(in size: CGSize) -> Double {
        let pad: CGFloat = 80
        switch chrome.viewMode {
        case .fit:
            let sx = max(40, size.width - pad) / sheetW
            let sy = max(40, size.height - pad) / sheetH
            return min(sx, sy, 8) * zoom
        case .oneToOne:
            return 3.78 * zoom
        }
    }

    // MARK: - Mutations

    private func updateFace(_ mutate: (inout EndpaperFaceDesign) -> Void) {
        store.updateSelectedEndsheets { design in
            if editingFront {
                mutate(&design.front)
            } else {
                mutate(&design.back)
            }
        }
    }

    private func updateDocument(_ mutate: (inout DesignDocument) -> Void) {
        updateFace { face in
            mutate(&face.document)
        }
    }

    private func updateElement(_ id: UUID, _ mutate: (inout DesignElement) -> Void) {
        updateDocument { doc in
            guard let i = doc.elements.firstIndex(where: { $0.id == id }) else { return }
            mutate(&doc.elements[i])
        }
    }

    private var faceShowFoldGuidesBinding: Binding<Bool> {
        Binding(
            get: { face.showFoldGuides },
            set: { value in updateFace { $0.showFoldGuides = value } }
        )
    }

    private func collapsible<Content: View>(
        _ title: String,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        DisclosureGroup(isExpanded: isExpanded) {
            content()
        } label: {
            Text(title).font(ArtisanTheme.sectionFont)
        }
    }

    private func labeled<Content: View>(_ title: String, @ViewBuilder content: @escaping () -> Content) -> some View {
        HStack {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Spacer()
            content()
        }
    }
}

// MARK: - Drag helper

private extension View {
    /// Applies a drag that translates the selection when the gesture ends.
    func onDragGestureEndedTranslate(
        scale: Double,
        element: DesignElement,
        selectedIDs: Set<UUID>,
        mutate: @escaping (Double, Double, Set<UUID>) -> Void
    ) -> some View {
        gesture(
            DragGesture()
                .onEnded { value in
                    let ids = selectedIDs.contains(element.id) ? selectedIDs : [element.id]
                    mutate(Double(value.translation.width) / scale, Double(value.translation.height) / scale, ids)
                }
        )
    }
}
