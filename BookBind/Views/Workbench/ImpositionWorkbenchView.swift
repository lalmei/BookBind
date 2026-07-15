import AppKit
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

/// Project workbench tool: PDF sources, signature config, bind, and export.
/// Lives under a masterwork — not in the global app sidebar.
struct ImpositionWorkbenchView: View {
    @EnvironmentObject private var store: AppStore
    @ObservedObject var workspace: BindingWorkspace
    var projectID: UUID?
    var projectTitle: String = "Project"
    @State private var isDropTargeted = false
    @State private var showPDFImporter = false

    @State private var sourcesExpanded = true
    @State private var bookBlockExpanded = true
    @State private var summaryExpanded = true
    @State private var bindingExpanded = true
    @State private var paperExpanded = true
    @State private var endpapersExpanded = false
    @State private var pageMarksExpanded = false
    @State private var isInspectorVisible = true

    /// Preview + inspector, or preview + collapsed reopen rail.
    private var minimumWorkbenchWidth: CGFloat {
        isInspectorVisible ? 720 : 420 + WorkbenchInspectorChrome.collapsedRailWidth
    }

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                previewArea
                Divider()
                footerBar
            }
            .frame(minWidth: 420)

            if isInspectorVisible {
                jobInspector
                    .frame(minWidth: 280, idealWidth: 320, maxWidth: 400)
            } else {
                WorkbenchInspectorChrome.CollapsedRail(isVisible: $isInspectorVisible, title: "Job")
            }
        }
        .horizontallyScrollable(minWidth: minimumWorkbenchWidth)
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
        }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color(nsColor: .labelColor).opacity(0.55), style: StrokeStyle(lineWidth: 2, dash: [8, 4]))
                    .padding(12)
                    .allowsHitTesting(false)
            }
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { workspace.errorMessage != nil },
            set: { if !$0 { workspace.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { workspace.errorMessage = nil }
        } message: {
            Text(workspace.errorMessage ?? "")
        }
        .sheet(isPresented: $workspace.showSignatureMap) {
            if let map = workspace.signatureMap {
                SignatureMapView(map: map)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { workspace.showSignatureMap = false }
                        }
                    }
            }
        }
        .onChange(of: workspace.job) { _ in
            workspace.markChanged()
        }
        .fileImporter(
            isPresented: $showPDFImporter,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                workspace.addPDFs(urls: urls)
            case .failure(let error):
                workspace.errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Job inspector

    private var jobInspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Job")
                        .font(ArtisanTheme.sectionFont)
                        .foregroundStyle(Color(nsColor: .labelColor))
                    Spacer(minLength: 0)
                    WorkbenchInspectorChrome.ToggleButton(isVisible: $isInspectorVisible)
                }

                collapsibleSection("Sources", isExpanded: $sourcesExpanded, badge: sourcesBadge) {
                    sourcesContent
                } trailing: {
                    Button {
                        showPDFImporter = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .help("Add PDFs")
                    .accessibilityLabel("Add PDFs")
                }

                if !workspace.bookBlockItems.isEmpty {
                    collapsibleSection("Book Block", isExpanded: $bookBlockExpanded) {
                        bookBlockContent
                    } trailing: {
                        Menu {
                            Button("Blank Page") { workspace.addBlankPage() }
                            Button("Front Cover Slot") { workspace.addCoverSlot(.frontCover) }
                            Button("Back Cover Slot") { workspace.addCoverSlot(.backCover) }
                        } label: {
                            Image(systemName: "plus")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                                .frame(width: 22, height: 22)
                                .contentShape(Rectangle())
                        }
                        .menuStyle(.borderlessButton)
                        .help("Insert pages into the assembled book block")
                        .accessibilityLabel("Insert into book block")
                    }
                }

                if let summary = workspace.impositionSummary {
                    collapsibleSection("Imposition summary", isExpanded: $summaryExpanded) {
                        ImpositionSummaryView(summary: summary, showsChrome: false)

                        if let plan = workspace.plan {
                            Text(plan.summary)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Button("Signature map…") {
                            workspace.showSignatureMap = true
                        }
                        .buttonStyle(.link)
                        .disabled(workspace.signatureMap == nil)
                    }
                }

                collapsibleSection("Binding", isExpanded: $bindingExpanded) {
                    labeledControl("Style") {
                        Picker("", selection: $workspace.job.bindingStyle) {
                            ForEach(BindingStyle.allCases) { style in
                                Text(style.rawValue).tag(style)
                            }
                        }
                        .labelsHidden()
                        .onChange(of: workspace.job.bindingStyle) { _ in workspace.refreshPlan() }
                    }

                    if workspace.job.bindingStyle == .sectionSewn {
                        labeledControl("Signature") {
                            Picker("", selection: $workspace.job.signatureSize) {
                                ForEach(SignatureSize.allCases) { size in
                                    Text(size.label).tag(size)
                                }
                            }
                            .labelsHidden()
                            .onChange(of: workspace.job.signatureSize) { _ in workspace.refreshPlan() }
                        }
                    }

                    Text(workspace.job.bindingStyle.help)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                collapsibleSection("Paper & sheet", isExpanded: $paperExpanded) {
                    labeledControl("Paper") {
                        Picker("", selection: $workspace.job.paperSize) {
                            ForEach(PaperSize.allCases) { size in
                                Text(size.rawValue).tag(size)
                            }
                        }
                        .labelsHidden()
                        .onChange(of: workspace.job.paperSize) { _ in
                            workspace.refreshPlan()
                            syncProjectTrimFromPaper()
                        }
                    }

                    if workspace.job.paperSize == .custom {
                        labeledControl("Trim (in)") {
                            HStack(spacing: 4) {
                                TextField(
                                    "W",
                                    value: Binding(
                                        get: { Double(workspace.job.customPageWidth / 72) },
                                        set: {
                                            workspace.job.customPageWidth = CGFloat(max(1, $0)) * 72
                                            syncProjectTrimFromPaper()
                                        }
                                    ),
                                    format: .number
                                )
                                .frame(width: 52)
                                Text("×")
                                    .foregroundStyle(.secondary)
                                TextField(
                                    "H",
                                    value: Binding(
                                        get: { Double(workspace.job.customPageHeight / 72) },
                                        set: {
                                            workspace.job.customPageHeight = CGFloat(max(1, $0)) * 72
                                            syncProjectTrimFromPaper()
                                        }
                                    ),
                                    format: .number
                                )
                                .frame(width: 52)
                            }
                        }
                    }

                    labeledControl("Bleed (pt)") {
                        TextField(
                            "pt",
                            value: Binding(
                                get: { Double(workspace.job.bleedPoints) },
                                set: { workspace.job.bleedPoints = CGFloat(max(0, $0)) }
                            ),
                            format: .number
                        )
                        .frame(width: 56)
                        .help("Extra margin outside trim. Try 9 (~⅛\") or 18 (~¼\").")
                    }

                    labeledControl("Creep (pt)") {
                        TextField(
                            "pt",
                            value: Binding(
                                get: { Double(workspace.job.creepPoints) },
                                set: { workspace.job.creepPoints = CGFloat(max(0, $0)) }
                            ),
                            format: .number
                        )
                        .frame(width: 56)
                        .help("Total shift for the innermost sheet toward the spine. 0 = off.")
                    }

                    Toggle("Normalize orientation", isOn: $workspace.job.normalizeOrientation)
                        .help("Rotate mixed landscape/portrait pages to a common orientation before imposing")
                    Toggle("Crop marks", isOn: $workspace.job.addCropMarks)
                    Toggle("Guide marks", isOn: $workspace.job.showGuideMarks)
                        .help("Fold line and signature labels on printer spreads")
                }

                collapsibleSection("Endpapers", isExpanded: $endpapersExpanded) {
                    endpaperRow(
                        title: "Front",
                        count: $workspace.job.frontEndpapers,
                        color: $workspace.job.frontEndpaperColor,
                        artwork: workspace.job.frontEndpaperArtwork,
                        choose: workspace.chooseFrontEndpaperArtwork,
                        clear: workspace.clearFrontEndpaperArtwork
                    )
                    endpaperRow(
                        title: "Back",
                        count: $workspace.job.backEndpapers,
                        color: $workspace.job.backEndpaperColor,
                        artwork: workspace.job.backEndpaperArtwork,
                        choose: workspace.chooseBackEndpaperArtwork,
                        clear: workspace.clearBackEndpaperArtwork
                    )
                }

                collapsibleSection("Page marks", isExpanded: $pageMarksExpanded) {
                    Toggle("Page numbers", isOn: $workspace.job.pageNumbers.enabled)

                    if workspace.job.pageNumbers.enabled {
                        labeledControl("Position") {
                            Picker("", selection: $workspace.job.pageNumbers.position) {
                                ForEach(PageNumberPosition.allCases) { position in
                                    Text(position.rawValue).tag(position)
                                }
                            }
                            .labelsHidden()
                        }

                        labeledControl("Start #") {
                            TextField("", value: $workspace.job.pageNumbers.startAt, format: .number)
                                .frame(width: 56)
                        }
                    }

                    Toggle("Watermark", isOn: $workspace.job.watermark.enabled)
                    if workspace.job.watermark.enabled {
                        labeledControl("Text") {
                            TextField("Watermark", text: $workspace.job.watermark.text)
                        }
                    }
                }
            }
            .padding(16)
        }
        .background(.background)
    }

    private var sourcesBadge: String? {
        guard !workspace.sources.isEmpty else { return nil }
        return "\(workspace.sources.count)"
    }

    private var sourcesContent: some View {
        Group {
            if workspace.sources.isEmpty {
                emptySources
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    List {
                        ForEach(workspace.sources) { source in
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "doc.richtext")
                                    .foregroundStyle(.secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(source.name)
                                        .lineLimit(2)
                                    Text("\(source.pageCount) pages")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                                Button {
                                    workspace.removeSource(source)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.tertiary)
                                }
                                .buttonStyle(.borderless)
                            }
                            .padding(.vertical, 2)
                        }
                        .onMove(perform: workspace.moveSource)
                    }
                    .listStyle(.plain)
                    .frame(minHeight: min(CGFloat(workspace.sources.count) * 52, 220))
                    .scrollContentBackground(.hidden)

                    Button {
                        showPDFImporter = true
                    } label: {
                        Label("Add PDF…", systemImage: "plus")
                            .font(.caption.weight(.medium))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                    .help("Add PDFs")
                }
            }
        }
    }

    private var emptySources: some View {
        Button {
            showPDFImporter = true
        } label: {
            VStack(spacing: 8) {
                Image(systemName: "doc.badge.plus")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(.secondary)
                Text("Drop PDFs here")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text("or click to browse")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Add PDFs")
    }

    private var bookBlockContent: some View {
        List {
            ForEach(workspace.bookBlockItems) { item in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: iconName(for: item))
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.label)
                            .lineLimit(1)
                        Text(description(for: item))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        workspace.rotateBookBlockItem(item)
                    } label: {
                        Image(systemName: "rotate.right")
                    }
                    .buttonStyle(.borderless)
                    .disabled(item.kind != .sourceRange)
                    .help("Rotate this range 90°")
                }
                .contextMenu {
                    if item.kind == .sourceRange, item.pageCount > 1 {
                        Button("Split…") {
                            promptSplit(item)
                        }
                    }
                    Button("Rotate 90°") {
                        workspace.rotateBookBlockItem(item)
                    }
                    .disabled(item.kind != .sourceRange)
                }
                .padding(.vertical, 2)
            }
            .onMove(perform: workspace.moveBookBlockItem)
            .onDelete(perform: workspace.deleteBookBlockItem)
        }
        .listStyle(.plain)
        .frame(minHeight: min(CGFloat(workspace.bookBlockItems.count) * 52, 220))
        .scrollContentBackground(.hidden)
    }

    // MARK: - Preview

    private var previewArea: some View {
        Group {
            if let document = workspace.previewDocument {
                PDFKitView(document: document)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "book.closed")
                        .font(.system(size: 44, weight: .ultraLight))
                        .foregroundStyle(.secondary)
                    Text(projectTitle)
                        .font(ArtisanTheme.cardTitleFont)
                    Text("Add PDFs in Sources on the right, set binding, then Bind.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 360)
                    Text(workspace.job.duplexHint)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 360)
                        .padding(.top, 4)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    // MARK: - Footer

    private var footerBar: some View {
        HStack(spacing: 12) {
            if workspace.isWorking {
                ProgressView()
                    .controlSize(.small)
            }

            if let status = workspace.statusMessage {
                Text(status)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            } else if workspace.totalSourcePages > 0 {
                Text("\(workspace.sources.count) file(s) · \(workspace.totalSourcePages) pages")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Map") {
                workspace.showSignatureMap = true
            }
            .disabled(workspace.signatureMap == nil)
            .help("Show signature sheet layout")

            Button("Bind") {
                workspace.runBinding()
            }
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(!workspace.canBind)

            Button("Export PDF…") {
                workspace.exportBoundPDF()
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])
            .disabled(workspace.previewDocument == nil)
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .tint(Color(nsColor: .labelColor))
        .background(.bar)
    }

    // MARK: - Inspector helpers

    private func collapsibleSection<Content: View>(
        _ title: String,
        isExpanded: Binding<Bool>,
        badge: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        collapsibleSection(title, isExpanded: isExpanded, badge: badge, content: content) {
            EmptyView()
        }
    }

    private func collapsibleSection<Content: View, Trailing: View>(
        _ title: String,
        isExpanded: Binding<Bool>,
        badge: String? = nil,
        @ViewBuilder content: () -> Content,
        @ViewBuilder trailing: () -> Trailing
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

                        if let badge {
                            Text(badge)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(
                                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                                        .fill(Color(nsColor: .separatorColor).opacity(0.35))
                                )
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Spacer(minLength: 0)

                trailing()
                    .fixedSize()
                    .layoutPriority(1)
            }
            .padding(.horizontal, 4)
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
                .overlay(
                    RoundedRectangle(cornerRadius: ArtisanTheme.controlRadius, style: .continuous)
                        .strokeBorder(Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 1)
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func labeledControl<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 78, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
    }

    private func endpaperRow(
        title: String,
        count: Binding<Int>,
        color: Binding<EndpaperColor>,
        artwork: EndpaperArtwork?,
        choose: @escaping () -> Void,
        clear: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            Stepper(
                "\(count.wrappedValue) pages",
                value: Binding(
                    get: { count.wrappedValue },
                    set: {
                        count.wrappedValue = $0
                        workspace.refreshPlan()
                    }
                ),
                in: 0...16
            )

            HStack(spacing: 6) {
                Picker("", selection: color) {
                    ForEach(EndpaperColor.allCases) { swatch in
                        Text(swatch.rawValue).tag(swatch)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity)
                .help("Solid-color endpaper when no artwork is selected")

                endpaperArtworkControl(artwork: artwork, choose: choose, clear: clear)
            }
        }
    }

    private func endpaperArtworkControl(
        artwork: EndpaperArtwork?,
        choose: @escaping () -> Void,
        clear: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 4) {
            if let artwork {
                Text(artwork.name)
                    .font(.caption2)
                    .lineLimit(1)
                    .frame(maxWidth: 72)
                    .help(artwork.name)
                Button(action: clear) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.borderless)
                .help("Use blank endpapers")
            } else {
                Button("Art…", action: choose)
                    .buttonStyle(.borderless)
                    .help("Use an image or PDF for these endpaper pages")
            }
        }
    }

    // MARK: - Book block helpers

    private func iconName(for item: BookBlockItem) -> String {
        switch item.kind {
        case .sourceRange: return "doc.richtext"
        case .blank: return "doc"
        case .frontCover, .backCover: return "book.closed"
        }
    }

    private func description(for item: BookBlockItem) -> String {
        var parts = ["\(item.pageCount) page\(item.pageCount == 1 ? "" : "s")"]
        if let pageRange = item.pageRange {
            parts.append("p\(pageRange.lowerBound + 1)-\(pageRange.upperBound + 1)")
        }
        if item.rotationDegrees != 0 {
            parts.append("\(item.rotationDegrees)°")
        }
        return parts.joined(separator: " · ")
    }

    private func promptSplit(_ item: BookBlockItem) {
        let alert = NSAlert()
        alert.messageText = "Split Source Range"
        alert.informativeText = "Keep how many pages in the first range? The remaining pages stay directly after it."
        alert.addButton(withTitle: "Split")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(string: "\(max(1, item.pageCount / 2))")
        field.frame = NSRect(x: 0, y: 0, width: 180, height: 24)
        alert.accessoryView = field

        if alert.runModal() == .alertFirstButtonReturn,
           let count = Int(field.stringValue) {
            workspace.splitBookBlockItem(item, afterPageCount: count)
        }
    }

    private func syncProjectTrimFromPaper() {
        guard let projectID else { return }
        store.syncProjectTrimFromImposition(projectID: projectID)
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var handled = false
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                handled = true
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    let url: URL?
                    if let data = item as? Data {
                        url = URL(dataRepresentation: data, relativeTo: nil)
                    } else if let maybeURL = item as? URL {
                        url = maybeURL
                    } else {
                        url = nil
                    }
                    guard let url else { return }
                    Task { @MainActor in
                        workspace.addPDFs(urls: [url])
                    }
                }
            }
        }
        return handled
    }
}

#Preview {
    ImpositionWorkbenchView(workspace: BindingWorkspace(), projectTitle: "Sample")
        .frame(width: 1100, height: 720)
}
