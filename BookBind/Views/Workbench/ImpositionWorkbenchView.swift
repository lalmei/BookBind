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
    @State private var showBlankPageCountSheet = false
    @State private var blankPageCount = 4

    @State private var sourcesExpanded = true
    @State private var bookBlockExpanded = true
    @State private var summaryExpanded = true
    @State private var bindingExpanded = true
    @State private var paperExpanded = true
    @State private var endpapersExpanded = true
    @State private var pageMarksExpanded = false
    @AppStorage(WorkbenchInspectorChrome.visibilityKey) private var isInspectorVisible = true

    private var minimumWorkbenchWidth: CGFloat {
        isInspectorVisible ? 420 + WorkbenchInspectorChrome.minWidth : 420
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
        .sheet(isPresented: $workspace.showFoldGuide) {
            FoldGuideView(guide: FoldCutGuide.making(for: workspace.job))
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { workspace.showFoldGuide = false }
                    }
                }
        }
        .sheet(isPresented: $showBlankPageCountSheet) {
            BlankPagesCountSheet(count: $blankPageCount) {
                workspace.addBlankPages(count: blankPageCount)
                showBlankPageCountSheet = false
            } onCancel: {
                showBlankPageCountSheet = false
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
        WorkbenchInspectorChrome.Panel {
            VStack(alignment: .leading, spacing: 12) {
                collapsibleSection("Sources", isExpanded: $sourcesExpanded, badge: sourcesBadge) {
                    sourcesContent
                } trailing: {
                    Menu {
                        Button("Add PDFs…") {
                            showPDFImporter = true
                        }
                        Divider()
                        Button("Blank Page") {
                            workspace.addBlankPage()
                        }
                        Button("Blank Pages…") {
                            blankPageCount = 4
                            showBlankPageCountSheet = true
                        }
                        Divider()
                        Button("Front Cover Slot") {
                            workspace.addCoverSlot(.frontCover)
                        }
                        Button("Back Cover Slot") {
                            workspace.addCoverSlot(.backCover)
                        }
                    } label: {
                        Image(systemName: "plus")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                    }
                    .menuStyle(.borderlessButton)
                    .help("Add PDFs, blank pages, or cover slots")
                    .accessibilityLabel("Add to sources and book block")
                }

                if !workspace.bookBlockItems.isEmpty {
                    collapsibleSection("Book Block", isExpanded: $bookBlockExpanded) {
                        bookBlockContent
                    } trailing: {
                        Menu {
                            Button("Blank Page") { workspace.addBlankPage() }
                            Button("Blank Pages…") {
                                blankPageCount = 4
                                showBlankPageCountSheet = true
                            }
                            Divider()
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

                        Button(workspace.job.impositionScheme.usesFolioImpose ? "Signature map…" : "Sheet map…") {
                            workspace.showSignatureMap = true
                        }
                        .buttonStyle(.link)
                        .disabled(workspace.signatureMap == nil)

                        Button("Fold & cut guide…") {
                            workspace.showFoldGuide = true
                        }
                        .buttonStyle(.link)
                    }
                }

                collapsibleSection("Layout", isExpanded: $bindingExpanded) {
                    labeledControl("Scheme") {
                        Picker("", selection: $workspace.job.impositionScheme) {
                            ForEach(ImpositionScheme.allCases) { scheme in
                                Text(scheme.rawValue).tag(scheme)
                            }
                        }
                        .labelsHidden()
                        .onChange(of: workspace.job.impositionScheme) { scheme in
                            workspace.job.applyImpositionScheme(scheme)
                            workspace.refreshPlan()
                            syncProjectArchitecture()
                            syncProjectTrimFromPaper()
                        }
                    }

                    Text(workspace.job.impositionScheme.help)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)

                    if workspace.job.impositionScheme.usesFolioImpose {
                        labeledControl("Style") {
                            Picker("", selection: $workspace.job.bindingStyle) {
                                ForEach(BindingStyle.allCases) { style in
                                    Text(style.rawValue).tag(style)
                                }
                            }
                            .labelsHidden()
                            .onChange(of: workspace.job.bindingStyle) { _ in
                                workspace.refreshPlan()
                                syncProjectArchitecture()
                            }
                        }

                        if workspace.job.impositionScheme.showsSignatureSize,
                           workspace.job.bindingStyle.usesSignatures {
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

                    if workspace.job.impositionScheme.showsAccordionPanelCount {
                        labeledControl("Panels") {
                            Stepper(
                                value: Binding(
                                    get: { workspace.job.resolvedAccordionPanelCount },
                                    set: {
                                        workspace.job.accordionPanelCount = $0
                                        workspace.refreshPlan()
                                        syncProjectTrimFromPaper()
                                    }
                                ),
                                in: BindingJob.minAccordionPanels...BindingJob.maxAccordionPanels
                            ) {
                                Text("\(workspace.job.resolvedAccordionPanelCount)")
                                    .font(.callout.monospacedDigit())
                            }
                        }
                    }

                    if workspace.job.impositionScheme.showsMiniZine8Template {
                        labeledControl("Page map") {
                            Picker("", selection: $workspace.job.miniZine8Template) {
                                ForEach(MiniZine8Template.allCases) { template in
                                    Text(template.rawValue).tag(template)
                                }
                            }
                            .labelsHidden()
                            .onChange(of: workspace.job.miniZine8Template) { _ in
                                workspace.refreshPlan()
                            }
                        }
                        Text("\(workspace.job.miniZine8Template.shortLabel) — \(workspace.job.miniZine8Template.help)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Cut is always the center slit across the middle two columns (not to the edges). Guide marks use light gray (folds dashed, cut solid) so residue after cutting is less obvious — turn guides off for a clean final print.")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("How to fold & cut…") {
                            workspace.showFoldGuide = true
                        }
                        .buttonStyle(.link)
                        .font(.caption)
                    }

                    if workspace.job.impositionScheme.showsMiniZine16Template {
                        labeledControl("Cut pattern") {
                            Picker("", selection: $workspace.job.miniZine16Template) {
                                ForEach(MiniZine16Template.allCases) { template in
                                    Text(template.rawValue).tag(template)
                                }
                            }
                            .labelsHidden()
                            .onChange(of: workspace.job.miniZine16Template) { _ in
                                workspace.refreshPlan()
                            }
                        }
                        Text(workspace.job.miniZine16Template.help)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                collapsibleSection("Paper & sheet", isExpanded: $paperExpanded) {
                    labeledControl(workspace.job.impositionScheme.paperSizeIsStockSheet ? "Stock" : "Paper") {
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

                    if workspace.job.impositionScheme.paperSizeIsStockSheet {
                        Text("Stock is the sheet you load in the printer. Page trim is derived from the layout grid.")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                        if let trim = workspace.job.resolvedTrimSize {
                            Text(
                                String(
                                    format: "Page trim ≈ %.2f × %.2f in",
                                    trim.width / 72,
                                    trim.height / 72
                                )
                            )
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                        }
                    }

                    if workspace.job.paperSize == .custom {
                        labeledControl("Trim") {
                            HStack(spacing: 4) {
                                CoverInspectorNumberField(
                                    value: BindingMath.millimeters(fromPoints: workspace.job.customPageWidth),
                                    fractionDigits: 1,
                                    width: 58,
                                    isLength: true
                                ) {
                                    workspace.job.customPageWidth = max(1, BindingMath.points(fromMillimeters: $0))
                                    syncProjectTrimFromPaper()
                                }
                                Text("×")
                                    .foregroundStyle(.secondary)
                                CoverInspectorNumberField(
                                    value: BindingMath.millimeters(fromPoints: workspace.job.customPageHeight),
                                    fractionDigits: 1,
                                    width: 58,
                                    isLength: true
                                ) {
                                    workspace.job.customPageHeight = max(1, BindingMath.points(fromMillimeters: $0))
                                    syncProjectTrimFromPaper()
                                }
                            }
                        }
                    }

                    labeledControl("Bleed") {
                        CoverInspectorNumberField(
                            value: BindingMath.millimeters(fromPoints: workspace.job.bleedPoints),
                            fractionDigits: 1,
                            width: 58,
                            isLength: true
                        ) {
                            workspace.job.bleedPoints = max(0, BindingMath.points(fromMillimeters: $0))
                        }
                        .help("Extra margin outside trim. Try 3mm or ⅛in.")
                    }

                    labeledControl("Creep") {
                        CoverInspectorNumberField(
                            value: BindingMath.millimeters(fromPoints: workspace.job.creepPoints),
                            fractionDigits: 2,
                            width: 58,
                            isLength: true
                        ) {
                            workspace.job.creepPoints = max(0, BindingMath.points(fromMillimeters: $0))
                        }
                        .help("Total shift for the innermost sheet toward the spine. 0 = off. Calculators ▸ Signatures estimates it.")
                    }

                    Toggle("Normalize orientation", isOn: $workspace.job.normalizeOrientation)
                        .help("Rotate mixed landscape/portrait pages to a common orientation before imposing")
                    Toggle("Crop marks", isOn: $workspace.job.addCropMarks)
                    Toggle("Guide marks", isOn: $workspace.job.showGuideMarks)
                        .help(
                            workspace.job.impositionScheme.usesFolioImpose
                                ? "Fold line and signature labels on printer spreads"
                                : "Light gray fold (dashed) and cut (solid) marks — turn off for a clean final print"
                        )
                    if workspace.job.bindingStyle.usesStitchHoleMarks,
                       workspace.job.impositionScheme.usesFolioImpose {
                        Toggle("Stitch hole marks", isOn: $workspace.job.showStitchHoleMarks)
                            .help("Punch positions on the fold for saddle-stitch stapling")
                        if workspace.job.showStitchHoleMarks {
                            labeledControl("Stitch holes") {
                                Picker("", selection: $workspace.job.stitchHoleCount) {
                                    ForEach(StitchHoleCount.allCases) { count in
                                        Text(count.label).tag(count)
                                    }
                                }
                                .labelsHidden()
                            }
                            if let hint = stitchHoleCountHint {
                                Text(hint)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }

                collapsibleSection("Endpapers", isExpanded: $endpapersExpanded) {
                    Text("One folded endsheet = 2 leaves (pastedown + flyleaf). Counts are whole sheets only.")
                        .font(.caption)
                        .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                        .fixedSize(horizontal: false, vertical: true)

                    HStack {
                        Text("Front endsheets")
                            .font(.callout)
                            .foregroundStyle(Color(nsColor: .labelColor))
                        Spacer()
                        Stepper(
                            value: Binding(
                                get: { workspace.job.frontEndsheets },
                                set: {
                                    workspace.job.frontEndsheets = $0
                                    workspace.refreshPlan()
                                }
                            ),
                            in: 0...BindingJob.maxEndsheetsPerSide
                        ) {
                            Text("\(workspace.job.frontEndsheets) (\(workspace.job.frontEndpapers) leaves)")
                                .font(.callout.monospacedDigit())
                        }
                    }

                    HStack {
                        Text("Back endsheets")
                            .font(.callout)
                            .foregroundStyle(Color(nsColor: .labelColor))
                        Spacer()
                        Stepper(
                            value: Binding(
                                get: { workspace.job.backEndsheets },
                                set: {
                                    workspace.job.backEndsheets = $0
                                    workspace.refreshPlan()
                                }
                            ),
                            in: 0...BindingJob.maxEndsheetsPerSide
                        ) {
                            Text("\(workspace.job.backEndsheets) (\(workspace.job.backEndpapers) leaves)")
                                .font(.callout.monospacedDigit())
                        }
                    }

                    endpaperModeSummaryRow(title: "Front", face: workspace.job.endpapers.front)
                    endpaperModeSummaryRow(title: "Back", face: workspace.job.endpapers.back)

                    Button {
                        store.selectProjectTool(.endpapers)
                    } label: {
                        Label("Open Endpapers", systemImage: "doc.on.doc")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ArtisanTheme.secondary)
                    .foregroundStyle(Color.black)
                    .help("Open the folded endsheet artboard")
                    .disabled(projectID == nil || !(store.selectedProject?.allows(.endpapers) ?? false))

                    if projectID != nil, store.selectedProject?.allows(.endpapers) != true {
                        Button("Add Endpapers section…") {
                            store.enableTool(.endpapers)
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)
                    }
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
        }
    }

    private var sourcesBadge: String? {
        guard !workspace.sources.isEmpty else { return nil }
        return "\(workspace.sources.count)"
    }

    private var stitchHoleCountHint: String? {
        guard workspace.job.bindingStyle.usesStitchHoleMarks else { return nil }
        let sheetCount = workspace.plan?.sheetCount ?? 0
        let pageHeight = workspace.job.resolvedTrimSize?.height
            ?? workspace.sources.first?.pageSize.height
            ?? 792
        let resolved = ImpositionService.resolvedStitchHoleCount(
            setting: workspace.job.stitchHoleCount,
            sheetCount: sheetCount,
            pageHeight: pageHeight
        )
        switch workspace.job.stitchHoleCount {
        case .auto:
            if sheetCount == 0 {
                return "Auto uses 2 staples for up to 4 nested sheets, 3 for thicker booklets."
            }
            return String(
                format: "Auto → %d hole%@ for %d nested sheet%@.",
                resolved,
                resolved == 1 ? "" : "s",
                sheetCount,
                sheetCount == 1 ? "" : "s"
            )
        case .one, .two, .three:
            let requested = workspace.job.stitchHoleCount == .one ? 1
                : workspace.job.stitchHoleCount == .two ? 2 : 3
            if requested != resolved {
                return String(
                    format: "Trim height limits this to %d hole%@.",
                    resolved,
                    resolved == 1 ? "" : "s"
                )
            }
            return nil
        }
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
                    Text("Add PDFs in Sources on the right. The imposed preview updates as you change settings.")
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
        .background(ArtisanTheme.canvasBackground)
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
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .help(status)
            } else if workspace.totalSourcePages > 0 {
                Text("\(workspace.sources.count) file(s) · \(workspace.totalSourcePages) pages")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .frame(height: 28)
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

    private func endpaperModeSummaryRow(title: String, face: EndpaperFaceDesign) -> some View {
        HStack {
            Text(title)
                .font(.callout)
                .foregroundStyle(Color(nsColor: .labelColor))
            Spacer()
            Label(face.mode.title, systemImage: face.mode.systemImage)
                .font(.caption)
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))
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

    private func syncProjectArchitecture() {
        guard let projectID else { return }
        store.syncProjectArchitectureFromImposition(projectID: projectID)
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

private struct BlankPagesCountSheet: View {
    @Binding var count: Int
    var onAdd: () -> Void
    var onCancel: () -> Void

    private let presets = [1, 2, 4, 8, 16]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Add Blank Pages")
                .font(ArtisanTheme.sectionFont)
                .padding(20)

            Divider()

            VStack(alignment: .leading, spacing: 14) {
                Text("How many blank pages should go into the book block?")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Stepper(value: $count, in: 1...200) {
                    Text("\(count) page\(count == 1 ? "" : "s")")
                        .font(.body.monospacedDigit())
                }

                HStack(spacing: 8) {
                    ForEach(presets, id: \.self) { preset in
                        Button("\(preset)") {
                            count = preset
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .padding(20)

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Add") {
                    onAdd()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(ArtisanTheme.primary)
            }
            .padding(20)
        }
        .frame(width: 360)
    }
}

#Preview {
    ImpositionWorkbenchView(workspace: BindingWorkspace(), projectTitle: "Sample")
        .frame(width: 1100, height: 720)
}
