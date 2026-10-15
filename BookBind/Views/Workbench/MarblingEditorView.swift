import AppKit
import SwiftUI

/// Marblizer-class interactive marbling editor: tools, undo/redo, recipes, PNG export.
struct MarblingEditorView: View {
    @Binding var spec: MarbledPaperSpec
    var pageSize: CGSize
    var onDone: (() -> Void)?

    @StateObject private var controller: MarblingCompositionController
    @State private var previewImage: NSImage?
    @State private var previewTask: Task<Void, Never>?
    @State private var isRendering = false
    @State private var showForceField = false
    @State private var showRecipes = false
    @State private var showHelp = false
    @State private var showAPIDocs = false
    @State private var replaceConfirmRecipe: MarblingRecipe?
    @State private var dragOrigin: CGPoint?
    @State private var dragCurrent: CGPoint?
    @State private var pendingSpatter: [MarblingInkDeposit] = []
    @State private var spatterRNG = SeededGenerator(seed: UInt64.random(in: 1...UInt64.max))
    @State private var shiftDown = false

    init(
        spec: Binding<MarbledPaperSpec>,
        pageSize: CGSize = CGSize(width: 612, height: 792),
        onDone: (() -> Void)? = nil
    ) {
        self._spec = spec
        self.pageSize = pageSize
        self.onDone = onDone
        let aspect = pageSize.height / max(1, pageSize.width)
        let logicalH = MarbledPaperGenerator.logicalWidth * aspect
        _controller = StateObject(
            wrappedValue: MarblingCompositionController(spec: spec.wrappedValue, logicalHeight: logicalH)
        )
    }

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                toolbar
                Divider()
                canvas
            }
            .frame(minWidth: 480)

            inspector
                .frame(minWidth: 300, idealWidth: 340, maxWidth: 400)
        }
        .frame(minWidth: 900, minHeight: 580)
        .onAppear {
            syncLogicalHeight()
            if !controller.spec.hasEditableHistory {
                // Keep parametric preview until user edits; still render from params.
            }
            schedulePreview()
        }
        .onChange(of: controller.spec) { newSpec in
            spec = newSpec
            schedulePreview()
        }
        .onChange(of: pageSize) { _ in
            syncLogicalHeight()
            schedulePreview()
        }
        .onDisappear {
            previewTask?.cancel()
            spec = controller.spec
        }
        .sheet(isPresented: $showRecipes) {
            recipesSheet
        }
        .sheet(isPresented: $showHelp) {
            helpSheet
        }
        .sheet(isPresented: $showAPIDocs) {
            apiDocsSheet
        }
        .confirmationDialog(
            "Replace current composition?",
            isPresented: Binding(
                get: { replaceConfirmRecipe != nil },
                set: { if !$0 { replaceConfirmRecipe = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Replace", role: .destructive) {
                if let recipe = replaceConfirmRecipe {
                    runRecipe(recipe, replace: true)
                }
                replaceConfirmRecipe = nil
            }
            Button("Append") {
                if let recipe = replaceConfirmRecipe {
                    runRecipe(recipe, replace: false)
                }
                replaceConfirmRecipe = nil
            }
            Button("Cancel", role: .cancel) {
                replaceConfirmRecipe = nil
            }
        } message: {
            Text("This recipe can replace the current operation history, or append to it.")
        }
        .background(KeyEventMonitor(shiftDown: $shiftDown, onKey: handleKey))
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 10) {
            Text("Marble editor")
                .font(.headline)

            Spacer(minLength: 0)

            Button {
                controller.undo()
            } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .disabled(!controller.canUndo)
            .help("Undo (⌘Z)")

            Button {
                controller.redo()
            } label: {
                Image(systemName: "arrow.uturn.forward")
            }
            .disabled(!controller.canRedo)
            .help("Redo (⇧⌘Z)")

            Button {
                showForceField.toggle()
            } label: {
                Image(systemName: showForceField ? "arrow.triangle.branch" : "arrow.triangle.branch")
                    .foregroundStyle(showForceField ? ArtisanTheme.secondary : Color.primary)
            }
            .help("Show tool force field (F)")

            Button {
                controller.reset()
            } label: {
                Image(systemName: "trash")
            }
            .help("Reset composition (R)")

            Button {
                exportPNG()
            } label: {
                Image(systemName: "square.and.arrow.down")
            }
            .help("Save PNG")

            Button {
                showRecipes = true
            } label: {
                Label("Recipes", systemImage: "text.badge.plus")
            }
            .help("Swift recipes (Marblizer script ports)")

            Button {
                showHelp = true
            } label: {
                Image(systemName: "questionmark.circle")
            }
            .help("Help")

            if isRendering {
                ProgressView()
                    .controlSize(.small)
            }

            if let onDone {
                Button("Done") {
                    spec = controller.spec
                    onDone()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.bar)
    }

    // MARK: - Canvas

    private var canvas: some View {
        GeometryReader { proxy in
            let aspect = pageSize.width / max(1, pageSize.height)
            let fitW = min(proxy.size.width - 40, (proxy.size.height - 40) * aspect)
            let fitH = fitW / aspect
            let logical = controller.logicalSize

            ZStack {
                ArtisanTheme.canvasBackground
                ZStack {
                    Group {
                        if let previewImage {
                            Image(nsImage: previewImage)
                                .resizable()
                                .interpolation(.high)
                                .frame(width: fitW, height: fitH)
                        } else {
                            Rectangle()
                                .fill(controller.backgroundColor.color)
                                .frame(width: fitW, height: fitH)
                                .overlay { ProgressView("Rendering…") }
                        }
                    }
                    .shadow(color: .black.opacity(0.16), radius: 12, y: 5)

                    if showForceField {
                        ForceFieldOverlay(
                            spec: controller.spec,
                            logicalSize: logical,
                            displaySize: CGSize(width: fitW, height: fitH)
                        )
                        .frame(width: fitW, height: fitH)
                        .allowsHitTesting(false)
                    }

                    if let origin = dragOrigin, let current = dragCurrent {
                        DragGuideOverlay(
                            tool: controller.tool,
                            origin: origin,
                            current: current,
                            logicalSize: logical,
                            displaySize: CGSize(width: fitW, height: fitH)
                        )
                        .frame(width: fitW, height: fitH)
                        .allowsHitTesting(false)
                    }
                }
                .gesture(canvasDrag(logicalSize: logical, displaySize: CGSize(width: fitW, height: fitH)))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func canvasDrag(logicalSize: CGSize, displaySize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let logical = viewToLogical(value.location, display: displaySize, logical: logicalSize)
                if dragOrigin == nil {
                    dragOrigin = logical
                    if controller.tool == .spatter {
                        pendingSpatter = controller.makeSpatterDrops(around: logical, rng: &spatterRNG)
                    }
                }
                dragCurrent = logical
                if controller.tool == .spatter, let origin = dragOrigin {
                    // Accumulate along drag path.
                    let extra = controller.makeSpatterDrops(around: logical, rng: &spatterRNG)
                    pendingSpatter.append(contentsOf: extra.prefix(8))
                    _ = origin
                }
            }
            .onEnded { value in
                let logical = viewToLogical(value.location, display: displaySize, logical: logicalSize)
                let origin = dragOrigin ?? logical
                commitGesture(from: origin, to: logical)
                dragOrigin = nil
                dragCurrent = nil
                pendingSpatter = []
            }
    }

    private func commitGesture(from origin: CGPoint, to end: CGPoint) {
        let distance = hypot(end.x - origin.x, end.y - origin.y)
        switch controller.tool {
        case .drop:
            controller.apply(controller.inkDrop(at: origin, displacing: !shiftDown))
        case .spatter:
            let drops = pendingSpatter.isEmpty
                ? controller.makeSpatterDrops(around: origin, rng: &spatterRNG)
                : pendingSpatter
            controller.apply(.scatter(drops: drops))
        case .lineTine:
            guard distance > 2 else { return }
            controller.apply(controller.lineTine(from: origin, to: end))
        case .wavyTine:
            guard distance > 2 else { return }
            controller.apply(controller.wavyTine(from: origin, to: end))
        case .circularTine:
            guard distance > 2 else { return }
            controller.apply(controller.circularTine(from: origin, to: end))
        case .vortex:
            guard distance > 2 else { return }
            controller.apply(controller.vortex(from: origin, to: end))
        }
    }

    private func viewToLogical(_ point: CGPoint, display: CGSize, logical: CGSize) -> CGPoint {
        // Gesture locations are relative to the ZStack content; assume centered image.
        // The gesture is on the image ZStack sized to fitW×fitH, so origin is top-left of image.
        CGPoint(
            x: Double(point.x) / Double(display.width) * logical.width,
            y: Double(point.y) / Double(display.height) * logical.height
        )
    }

    // MARK: - Inspector

    private var inspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Tools")
                    .font(.headline)
                toolPalette

                parameterSteppers

                Text("Color")
                    .font(.headline)
                colorSection

                Text("Composition")
                    .font(.headline)
                HStack {
                    Text("\(controller.operations.count) operations")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("New variation") {
                        controller.regenerateVariation()
                    }
                    .help("New seed from parametric recipe; clears interactive history")
                    .controlSize(.small)
                }

                Button {
                    showAPIDocs = true
                } label: {
                    Label("Recipe API docs", systemImage: "doc.text")
                }
                .buttonStyle(.borderless)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var toolPalette: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            ForEach(MarblingTool.allCases) { tool in
                Button {
                    controller.tool = tool
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tool.systemImage)
                        Text(tool.title)
                            .font(.caption2)
                            .lineLimit(1)
                        Text(tool.shortcut)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .padding(6)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(controller.tool == tool
                                  ? ArtisanTheme.secondary.opacity(0.22)
                                  : Color(nsColor: .controlBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(
                                controller.tool == tool ? ArtisanTheme.secondary : Color(nsColor: .separatorColor),
                                lineWidth: controller.tool == tool ? 1.5 : 1
                            )
                    )
                }
                .buttonStyle(.plain)
                .help(tool.help)
            }
        }
    }

    @ViewBuilder
    private var parameterSteppers: some View {
        let tool = controller.tool
        VStack(alignment: .leading, spacing: 8) {
            Text("Tool parameters")
                .font(.caption.weight(.semibold))
            switch tool {
            case .drop:
                stepperRow("Radius", value: controller.toolParameters.dropRadius) { delta in
                    controller.toolParameters.adjustPrimary(for: .drop, delta: delta)
                }
            case .spatter:
                stepperRow("Scatter", value: controller.toolParameters.scatterRadius) { delta in
                    controller.toolParameters.adjustPrimary(for: .spatter, delta: delta)
                }
                stepperRow("Drop size", value: controller.toolParameters.spatterDropRadius) { delta in
                    controller.toolParameters.adjustSecondary(for: .spatter, delta: delta)
                }
            case .lineTine:
                stepperRow("Spacing", value: controller.toolParameters.tineSpacing) { delta in
                    controller.toolParameters.adjustPrimary(for: .lineTine, delta: delta)
                }
                stepperRow("Tines", value: controller.toolParameters.numTines) { delta in
                    controller.toolParameters.adjustSecondary(for: .lineTine, delta: delta)
                }
            case .wavyTine:
                stepperRow("Spacing", value: controller.toolParameters.wavySpacing) { delta in
                    controller.toolParameters.adjustPrimary(for: .wavyTine, delta: delta)
                }
                stepperRow("Tines", value: controller.toolParameters.wavyNumTines) { delta in
                    controller.toolParameters.adjustSecondary(for: .wavyTine, delta: delta)
                }
            case .circularTine:
                stepperRow("Spacing", value: controller.toolParameters.circularSpacing) { delta in
                    controller.toolParameters.adjustPrimary(for: .circularTine, delta: delta)
                }
                stepperRow("Tines", value: controller.toolParameters.circularNumTines) { delta in
                    controller.toolParameters.adjustSecondary(for: .circularTine, delta: delta)
                }
            case .vortex:
                Text("No adjustable parameters")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func stepperRow(_ title: String, value: Double, adjust: @escaping (Double) -> Void) -> some View {
        HStack {
            Text(title)
                .font(.caption)
            Spacer()
            Text(String(format: "%.0f", value))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .trailing)
            Button("−") { adjust(-5) }
                .controlSize(.small)
            Button("+") { adjust(5) }
                .controlSize(.small)
        }
    }

    private var colorSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Foreground")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    ColorPicker(
                        "",
                        selection: Binding(
                            get: { controller.foregroundColor.color },
                            set: { controller.setForegroundColor(CodableColor(color: $0)) }
                        ),
                        supportsOpacity: false
                    )
                    .labelsHidden()
                    .frame(width: 44, height: 28)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Background")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    ColorPicker(
                        "",
                        selection: Binding(
                            get: { controller.backgroundColor.color },
                            set: { controller.setBackgroundColor(CodableColor(color: $0), asOperation: true) }
                        ),
                        supportsOpacity: false
                    )
                    .labelsHidden()
                    .frame(width: 44, height: 28)
                }
                Spacer()
            }

            if !controller.recentColors.isEmpty {
                Text("Recent")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    ForEach(Array(controller.recentColors.enumerated()), id: \.offset) { _, color in
                        Button {
                            controller.setForegroundColor(color)
                        } label: {
                            Circle()
                                .fill(color.color)
                                .frame(width: 18, height: 18)
                                .overlay(Circle().strokeBorder(Color.primary.opacity(0.2), lineWidth: 0.5))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            ForEach(MarbledPaperPalette.all) { palette in
                Button {
                    controller.updatePalette(palette)
                    if controller.spec.hasEditableHistory {
                        controller.setBackgroundColor(palette.background, asOperation: true)
                    }
                } label: {
                    HStack(spacing: 6) {
                        ForEach(Array(palette.colors.prefix(4).enumerated()), id: \.offset) { _, c in
                            Circle().fill(c.color).frame(width: 10, height: 10)
                        }
                        Text(palette.name).font(.caption)
                        Spacer(minLength: 0)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Sheets

    private var recipesSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recipes")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button("Close") { showRecipes = false }
            }
            Text("Swift ports of Marblizer’s example scripts and style generators.")
                .font(.callout)
                .foregroundStyle(.secondary)
            List(MarblingRecipe.all) { recipe in
                VStack(alignment: .leading, spacing: 4) {
                    Text(recipe.title).font(.headline)
                    Text(recipe.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Apply") {
                        if controller.spec.hasEditableHistory && recipe.replacesHistory {
                            replaceConfirmRecipe = recipe
                            showRecipes = false
                        } else {
                            runRecipe(recipe, replace: true)
                            showRecipes = false
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                .padding(.vertical, 4)
            }
        }
        .padding(16)
        .frame(width: 420, height: 480)
    }

    private var helpSheet: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Marble editor help")
                    .font(.title2.weight(.semibold))
                Text("Marbling floats ink on a liquid surface, rakes it into patterns, and lifts the result onto paper. This editor simulates that surface.")
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(MarblingTool.allCases) { tool in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(tool.title) (\(tool.shortcut))")
                            .font(.headline)
                        Text(tool.help)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                Text("Shortcuts")
                    .font(.headline)
                Text("⌘Z Undo · ⇧⌘Z Redo · R Reset · F Force field · S Recipes · ↑↓ Primary param · ←→ Secondary")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(20)
            .frame(maxWidth: 480, alignment: .leading)
        }
        .frame(width: 500, height: 520)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { showHelp = false }
            }
        }
    }

    private var apiDocsSheet: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Recipe API")
                    .font(.title2.weight(.semibold))
                Text("A recipe is a Swift function `(MarblingRecipeContext) -> [MarblingOperation]`. Built-ins live in MarblingRecipe.all.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                ForEach(MarblingRecipeAPIDocs.sections) { section in
                    Text(section.title)
                        .font(.headline)
                    ForEach(section.entries) { entry in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.signature)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                            Text(entry.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: 560, alignment: .leading)
        }
        .frame(width: 580, height: 520)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { showAPIDocs = false }
            }
        }
    }

    // MARK: - Actions

    private func runRecipe(_ recipe: MarblingRecipe, replace: Bool) {
        let ops = recipe.run(controller.recipeContext())
        controller.applyRecipe(ops, replace: replace)
    }

    private func syncLogicalHeight() {
        let aspect = pageSize.height / max(1, pageSize.width)
        controller.logicalHeight = MarbledPaperGenerator.logicalWidth * aspect
    }

    private func schedulePreview() {
        previewTask?.cancel()
        isRendering = true
        let snapshot = controller.spec
        let size = pageSize
        previewTask = Task {
            let rendered: NSImage? = await Task.detached(priority: .userInitiated) {
                MarbledPaperGenerator.nsImage(spec: snapshot, sizePoints: size, dpi: 110)
            }.value
            guard !Task.isCancelled else { return }
            await MainActor.run {
                previewImage = rendered
                isRendering = false
            }
        }
    }

    private func exportPNG() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "marbling.png"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let snapshot = controller.spec
        let size = pageSize
        Task.detached(priority: .userInitiated) {
            guard let image = MarbledPaperGenerator.nsImage(spec: snapshot, sizePoints: size, dpi: 300),
                  let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:])
            else { return }
            try? png.write(to: url)
        }
    }

    private func handleKey(_ key: String, modifiers: NSEvent.ModifierFlags) {
        switch key.lowercased() {
        case "d": controller.tool = .drop
        case "x": controller.tool = .spatter
        case "l": controller.tool = .lineTine
        case "w": controller.tool = .wavyTine
        case "c": controller.tool = .circularTine
        case "v": controller.tool = .vortex
        case "f": showForceField.toggle()
        case "s" where !modifiers.contains(.command):
            showRecipes = true
        case "r" where !modifiers.contains(.command):
            controller.reset()
        case "z" where modifiers.contains(.command) && modifiers.contains(.shift):
            controller.redo()
        case "z" where modifiers.contains(.command):
            controller.undo()
        case "uparrow", "up":
            controller.toolParameters.adjustPrimary(for: controller.tool, delta: 5)
        case "downarrow", "down":
            controller.toolParameters.adjustPrimary(for: controller.tool, delta: -5)
        case "leftarrow", "left":
            controller.toolParameters.adjustSecondary(for: controller.tool, delta: -1)
        case "rightarrow", "right":
            controller.toolParameters.adjustSecondary(for: controller.tool, delta: 1)
        default:
            break
        }
    }
}

// MARK: - Overlays

private struct DragGuideOverlay: View {
    let tool: MarblingTool
    let origin: CGPoint
    let current: CGPoint
    let logicalSize: CGSize
    let displaySize: CGSize

    var body: some View {
        Canvas { context, size in
            let o = map(origin)
            let c = map(current)
            var path = Path()
            switch tool {
            case .drop:
                let r = 8.0
                path.addEllipse(in: CGRect(x: o.x - r, y: o.y - r, width: r * 2, height: r * 2))
            case .spatter:
                path.addEllipse(in: CGRect(x: c.x - 12, y: c.y - 12, width: 24, height: 24))
            case .lineTine, .wavyTine:
                path.move(to: o)
                path.addLine(to: c)
            case .circularTine, .vortex:
                let radius = hypot(c.x - o.x, c.y - o.y)
                path.addEllipse(in: CGRect(x: o.x - radius, y: o.y - radius, width: radius * 2, height: radius * 2))
                path.move(to: o)
                path.addLine(to: c)
            }
            context.stroke(path, with: .color(.white.opacity(0.9)), lineWidth: 1.5)
            context.stroke(path, with: .color(.black.opacity(0.5)), lineWidth: 0.75)
        }
    }

    private func map(_ p: CGPoint) -> CGPoint {
        CGPoint(
            x: p.x / logicalSize.width * displaySize.width,
            y: p.y / logicalSize.height * displaySize.height
        )
    }
}

private struct ForceFieldOverlay: View {
    let spec: MarbledPaperSpec
    let logicalSize: CGSize
    let displaySize: CGSize

    var body: some View {
        Canvas { context, _ in
            let cols = 12
            let rows = 12
            for iy in 0..<rows {
                for ix in 0..<cols {
                    let lx = (Double(ix) + 0.5) / Double(cols) * logicalSize.width
                    let ly = (Double(iy) + 0.5) / Double(rows) * logicalSize.height
                    let disp = MarbledPaperGenerator.displacementAt(
                        point: CGPoint(x: lx, y: ly),
                        spec: spec,
                        logicalHeight: logicalSize.height
                    )
                    let ox = lx / logicalSize.width * displaySize.width
                    let oy = ly / logicalSize.height * displaySize.height
                    let scale = 0.35
                    var path = Path()
                    path.move(to: CGPoint(x: ox, y: oy))
                    path.addLine(to: CGPoint(x: ox + disp.dx * scale, y: oy + disp.dy * scale))
                    context.stroke(path, with: .color(.white.opacity(0.55)), lineWidth: 1)
                }
            }
        }
        .opacity(0.85)
    }
}

/// Lightweight key monitor for tool shortcuts while the editor is open.
private struct KeyEventMonitor: NSViewRepresentable {
    @Binding var shiftDown: Bool
    var onKey: (String, NSEvent.ModifierFlags) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = KeyCatcherView()
        view.shiftDown = $shiftDown
        view.onKey = onKey
        DispatchQueue.main.async { view.window?.makeFirstResponder(view) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? KeyCatcherView else { return }
        view.shiftDown = $shiftDown
        view.onKey = onKey
    }

    final class KeyCatcherView: NSView {
        var shiftDown: Binding<Bool>?
        var onKey: ((String, NSEvent.ModifierFlags) -> Void)?

        override var acceptsFirstResponder: Bool { true }

        override func keyDown(with event: NSEvent) {
            shiftDown?.wrappedValue = event.modifierFlags.contains(.shift)
            if let chars = event.charactersIgnoringModifiers, let ch = chars.first {
                onKey?(String(ch), event.modifierFlags)
            } else {
                switch event.keyCode {
                case 126: onKey?("up", event.modifierFlags)
                case 125: onKey?("down", event.modifierFlags)
                case 123: onKey?("left", event.modifierFlags)
                case 124: onKey?("right", event.modifierFlags)
                default: super.keyDown(with: event)
                }
            }
        }

        override func flagsChanged(with event: NSEvent) {
            shiftDown?.wrappedValue = event.modifierFlags.contains(.shift)
        }
    }
}
