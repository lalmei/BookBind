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
    @State private var endpapersExpanded = true
    @State private var pageMarksExpanded = false
    @State private var isInspectorVisible = true
    @State private var showEndpaperDesigner = false
    /// When opening the designer, focus front (true) or back (false).
    @State private var endpaperDesignerFocusFront = true

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
        .sheet(isPresented: $showEndpaperDesigner) {
            EndpaperDesignerView(
                workspace: workspace,
                isPresented: $showEndpaperDesigner,
                initiallyEditingFront: endpaperDesignerFocusFront
            )
        }
    }

    private var frontEndpaperBinding: Binding<EndpaperFaceDesign> {
        Binding(
            get: { workspace.job.endpapers.front },
            set: {
                workspace.job.endpapers.front = $0
                workspace.markChanged()
            }
        )
    }

    private var backEndpaperBinding: Binding<EndpaperFaceDesign> {
        Binding(
            get: { workspace.job.endpapers.back },
            set: {
                workspace.job.endpapers.back = $0
                workspace.markChanged()
            }
        )
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
                        .onChange(of: workspace.job.bindingStyle) { _ in
                            workspace.refreshPlan()
                            syncProjectArchitecture()
                        }
                    }

                    if workspace.job.bindingStyle.usesSignatures {
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
                    if workspace.job.bindingStyle.usesStitchHoleMarks {
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
                    endpaperFaceCard(
                        title: "Front",
                        count: $workspace.job.frontEndpapers,
                        face: frontEndpaperBinding,
                        isFront: true
                    )

                    endpaperFaceCard(
                        title: "Back",
                        count: $workspace.job.backEndpapers,
                        face: backEndpaperBinding,
                        isFront: false
                    )

                    Button {
                        // Jump straight into marbling for the front face.
                        var front = workspace.job.endpapers.front
                        front.ensureMarbling()
                        workspace.job.endpapers.front = front
                        workspace.markChanged()
                        endpaperDesignerFocusFront = true
                        showEndpaperDesigner = true
                    } label: {
                        Label("Marble paper generator", systemImage: "paintbrush.pointed.fill")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ArtisanTheme.secondary)
                    .foregroundStyle(Color.black)
                    .help("Open the procedural marbled-paper generator")
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

    private func endpaperFaceCard(
        title: String,
        count: Binding<Int>,
        face: Binding<EndpaperFaceDesign>,
        isFront: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color(nsColor: .labelColor))
                Spacer()
                Stepper(
                    value: Binding(
                        get: { count.wrappedValue },
                        set: {
                            count.wrappedValue = $0
                            workspace.refreshPlan()
                        }
                    ),
                    in: 0...16
                ) {
                    Text("\(count.wrappedValue) pages")
                        .font(.callout)
                        .foregroundStyle(Color(nsColor: .labelColor))
                        .monospacedDigit()
                }
            }

            // Vertical mode list — readable in a narrow inspector (segmented 4-up was clipped).
            VStack(spacing: 4) {
                ForEach(EndpaperMode.allCases) { mode in
                    endpaperModeRow(
                        mode: mode,
                        isSelected: face.wrappedValue.mode == mode,
                        action: { endpaperModeBinding(face).wrappedValue = mode }
                    )
                }
            }

            endpaperModeDetails(face: face, isFront: isFront)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.7), lineWidth: 1)
        )
    }

    private func endpaperModeRow(mode: EndpaperMode, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: mode.systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isSelected ? ArtisanTheme.secondary : Color(nsColor: .secondaryLabelColor))
                    .frame(width: 18)
                Text(mode.title)
                    .font(.callout.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(Color(nsColor: .labelColor))
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(ArtisanTheme.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isSelected
                          ? ArtisanTheme.secondary.opacity(0.18)
                          : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(mode.help)
    }

    @ViewBuilder
    private func endpaperModeDetails(face: Binding<EndpaperFaceDesign>, isFront: Bool) -> some View {
        switch face.wrappedValue.mode {
        case .blank:
            Text("Plain undecorated leaves")
                .font(.caption)
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))
        case .solidColor:
            HStack {
                Text("Color")
                    .font(.caption)
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                Spacer()
                Picker("", selection: endpaperColorBinding(face)) {
                    ForEach(EndpaperColor.allCases.filter { $0 != .none }) { swatch in
                        Text(swatch.rawValue).tag(swatch)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 160)
            }
        case .artwork:
            endpaperArtworkControl(
                artwork: face.wrappedValue.artwork,
                choose: {
                    if isFront { workspace.chooseFrontEndpaperArtwork() }
                    else { workspace.chooseBackEndpaperArtwork() }
                },
                clear: {
                    if isFront { workspace.clearFrontEndpaperArtwork() }
                    else { workspace.clearBackEndpaperArtwork() }
                }
            )
        case .marbled:
            endpaperMarbleSummary(face: face.wrappedValue, isFront: isFront)
        }
    }

    private func endpaperModeBinding(_ face: Binding<EndpaperFaceDesign>) -> Binding<EndpaperMode> {
        Binding(
            get: { face.wrappedValue.mode },
            set: { mode in
                var next = face.wrappedValue
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
                face.wrappedValue = next
            }
        )
    }

    private func endpaperColorBinding(_ face: Binding<EndpaperFaceDesign>) -> Binding<EndpaperColor> {
        Binding(
            get: {
                face.wrappedValue.solidColor == .none
                    ? .archivalIvory
                    : face.wrappedValue.solidColor
            },
            set: { color in
                var next = face.wrappedValue
                next.solidColor = color
                next.mode = .solidColor
                face.wrappedValue = next
            }
        )
    }

    private func endpaperMarbleSummary(face: EndpaperFaceDesign, isFront: Bool) -> some View {
        let spec = face.marbling ?? MarbledPaperSpec()
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                EndpaperMarbleThumbnail(spec: spec)
                    .frame(width: 48, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(spec.style.title)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(Color(nsColor: .labelColor))
                    Text("\(spec.palette.count) inks")
                        .font(.caption)
                        .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                }

                Spacer(minLength: 0)
            }

            Button {
                endpaperDesignerFocusFront = isFront
                showEndpaperDesigner = true
            } label: {
                Text("Edit marble pattern…")
                    .font(.callout.weight(.medium))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(ArtisanTheme.secondary)
            .help("Adjust style, colors, flow, and regenerate variations")
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(ArtisanTheme.secondary.opacity(0.08))
        )
    }

    private func endpaperArtworkControl(
        artwork: EndpaperArtwork?,
        choose: @escaping () -> Void,
        clear: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 6) {
            if let artwork {
                Text(artwork.name)
                    .font(.caption2)
                    .lineLimit(1)
                    .help(artwork.name)
                Spacer(minLength: 0)
                Button("Clear", action: clear)
                    .buttonStyle(.borderless)
                    .help("Remove artwork")
            } else {
                Button("Choose artwork…", action: choose)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
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

#Preview {
    ImpositionWorkbenchView(workspace: BindingWorkspace(), projectTitle: "Sample")
        .frame(width: 1100, height: 720)
}
