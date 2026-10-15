import SceneKit
import SwiftUI

/// Project Preview tool: interactive 3D book assembled from cover, trim, and endpapers.
struct BookPreviewWorkbenchView: View {
    @EnvironmentObject private var store: AppStore
    let project: BinderyProject
    @ObservedObject var workspace: BindingWorkspace

    @ObservedObject var chrome: BookPreviewChrome
    @State private var showDimensions = true
    @AppStorage(WorkbenchInspectorChrome.visibilityKey) private var isInspectorVisible = true
    @State private var sceneBundle: BookPreview3DBuilder.SceneBundle?
    @State private var rebuildTask: Task<Void, Never>?

    private var dimensions: PhysicalBookDimensions {
        PhysicalBookDimensions.resolving(
            project: project,
            assembledPageCount: workspace.assembledPageCount
        )
    }

    /// Bumps when any dimension/cover input that should rebuild the 3D scene changes.
    private var previewRebuildToken: String {
        [
            project.id.uuidString,
            String(project.widthMM),
            String(project.heightMM),
            String(project.boardThicknessMM),
            String(project.hingeGapMM),
            String(project.spineWidthOverrideMM ?? -1),
            project.architecture.rawValue,
            project.coverMaterial.rawValue,
            String(project.coverElements.count),
            String(project.estimatedPageCount),
            String(project.textPaperGSM),
            String(workspace.assembledPageCount),
            endsheetToken(project.endsheets.front),
            endsheetToken(project.endsheets.back)
        ].joined(separator: "|")
    }

    private func endsheetToken(_ face: EndpaperFaceDesign) -> String {
        var parts = [face.mode.rawValue, face.solidColor.rawValue]
        if let marble = face.marbling {
            // Key off the full spec so every marble edit (turbulence, palette,
            // comb, flow, …) rebuilds the preview — not just style/seed/scale.
            parts.append(String(marble.hashValue))
        }
        if let art = face.artwork {
            parts.append(art.id.uuidString)
        }
        return parts.joined(separator: ",")
    }

    var body: some View {
        content
            .background(ArtisanTheme.canvasBackground)
            .onAppear { rebuildScene(immediate: true) }
            .onChange(of: chrome.openAmount, perform: applyOpenAmount)
            .onChange(of: previewRebuildToken) { _ in rebuildScene() }
            .onDisappear { rebuildTask?.cancel() }
    }

    private var content: some View {
        HSplitView {
            mainCanvas
                .frame(minWidth: 420)
                .layoutPriority(1)
            inspectorColumn
        }
    }

    @ViewBuilder
    private var inspectorColumn: some View {
        if isInspectorVisible {
            WorkbenchInspectorChrome.Panel {
                inspectorBody
            }
        }
    }

    private var mainCanvas: some View {
        previewHost
    }

    private var previewHost: some View {
        ZStack {
            if let bundle = sceneBundle {
                BookPreview3DView(scene: bundle.scene, resetToken: chrome.resetToken)
            } else {
                ProgressView("Building preview…")
                    .controlSize(.regular)
            }

            if showDimensions {
                VStack {
                    Spacer()
                    dimensionOverlay
                        .padding(16)
                }
                .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var dimensionOverlay: some View {
        let dims = dimensions
        return HStack(spacing: 16) {
            metric("Trim", String(format: "%.0f × %.0f mm", dims.boardWidthMM, dims.boardHeightMM))
            metric("Spine", String(format: "%.1f mm", dims.spineWidthMM))
            metric("Pages", "\(dims.pageCount)")
            metric("Architecture", dims.architecture.rawValue)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.primary)
        }
    }

    private var inspectorBody: some View {
        let dims = dimensions
        return VStack(alignment: .leading, spacing: 18) {
            openAmountSection
            Toggle("Show dimensions", isOn: $showDimensions)
            Divider()
            assemblySection(dims)
            Text("Drag to orbit. Pinch or scroll to zoom. Cover art and endpapers update from the Cover and Endpapers tools.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var openAmountSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            WorkbenchInspectorChrome.SectionTitle("Open amount")
            Slider(value: $chrome.openAmount, in: 0...1)
            HStack {
                Text("Closed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int((chrome.openAmount * 100).rounded()))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Open")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func assemblySection(_ dims: PhysicalBookDimensions) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            WorkbenchInspectorChrome.SectionTitle("Assembly")
            LabeledContent("Trim") {
                Text(String(format: "%.1f × %.1f mm", dims.boardWidthMM, dims.boardHeightMM))
                    .font(.body.monospacedDigit())
            }
            LabeledContent("Spine") {
                Text(String(format: "%.2f mm", dims.spineWidthMM))
                    .font(.body.monospacedDigit())
            }
            LabeledContent("Text block") {
                Text(String(format: "%.2f mm", dims.textBlockThicknessMM))
                    .font(.body.monospacedDigit())
            }
            LabeledContent("Pages") {
                Text("\(dims.pageCount)")
                    .font(.body.monospacedDigit())
            }
            LabeledContent("GSM") {
                Text("\(Int(dims.gsm))")
                    .font(.body.monospacedDigit())
            }
            LabeledContent("Binding") {
                Text(dims.architecture.rawValue)
            }
        }
    }

    private func applyOpenAmount(_ value: Double) {
        guard let bundle = sceneBundle else { return }
        BookPreview3DBuilder.applyOpenAmount(
            Float(value),
            frontHinge: bundle.frontHinge,
            backHinge: bundle.backHinge
        )
    }

    private func rebuildScene(immediate: Bool = false) {
        rebuildTask?.cancel()
        let projectSnapshot = project
        let assembledPages = workspace.assembledPageCount
        let open = Float(chrome.openAmount)

        let work = {
            let dims = PhysicalBookDimensions.resolving(
                project: projectSnapshot,
                assembledPageCount: assembledPages
            )
            let textures = CoverWrapTextureService.makeTextures(
                project: projectSnapshot,
                dimensions: dims
            )
            return BookPreview3DBuilder.makeScene(
                dimensions: dims,
                textures: textures,
                openAmount: open
            )
        }

        if immediate {
            sceneBundle = work()
            return
        }

        rebuildTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }
            sceneBundle = work()
        }
    }
}

/// Toolbar-owned state for the 3D preview, so window toolbar buttons can drive the scene.
@MainActor
final class BookPreviewChrome: ObservableObject {
    @Published var openAmount: Double = 0
    @Published var resetToken = 0

    var isOpen: Bool { openAmount >= 0.5 }

    func toggleOpen() {
        withAnimation(.easeInOut(duration: 0.25)) {
            openAmount = isOpen ? 0 : 1
        }
    }

    func resetCamera() {
        resetToken += 1
    }
}
