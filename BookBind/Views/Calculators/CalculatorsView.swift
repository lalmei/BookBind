import SwiftUI

/// Global bench calculators — no project required.
///
/// Same layout as a project tool: a blueprint drawing in the main area, inputs and results
/// in the trailing inspector, calculator switcher centered in the toolbar.
struct CalculatorsView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        CalculatorsContent(session: store.calculators)
    }
}

private struct CalculatorsContent: View {
    @EnvironmentObject private var store: AppStore
    @ObservedObject var session: CalculatorSession
    @AppStorage("calculatorKind") private var kindRaw = CalculatorKind.caseBinding.rawValue
    @AppStorage(WorkbenchInspectorChrome.visibilityKey) private var isInspectorVisible = true

    private var kind: CalculatorKind {
        CalculatorKind(rawValue: kindRaw) ?? .caseBinding
    }

    var body: some View {
        HSplitView {
            drawing
                .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(1)
            if isInspectorVisible {
                WorkbenchInspectorChrome.Panel {
                    VStack(alignment: .leading, spacing: 18) {
                        Text(kind.help)
                            .font(.callout)
                            .foregroundStyle(ArtisanTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        inputs
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Calculator", selection: $kindRaw) {
                    ForEach(CalculatorKind.allCases) { kind in
                        Text(kind.title).tag(kind.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .help(kind.help)
            }
            ToolbarItemGroup(placement: .primaryAction) {
                actions
                WorkbenchInspectorChrome.ToolbarToggle()
            }
        }
    }

    // MARK: - Drawing

    @ViewBuilder
    private var drawing: some View {
        switch kind {
        case .caseBinding:
            CaseBlueprint(plan: session.casePlan)
        case .signatures:
            SignatureBlueprint(plan: session.signaturePlan, sheetsPerSignature: session.sheetsPerSignature)
        case .sewing:
            SewingBlueprint(plan: session.sewingPlan, spineHeight: session.pageHeight)
        case .sheetYield:
            YieldBlueprint(
                plan: session.yieldPlan,
                parentWidth: session.parentWidth,
                parentHeight: session.parentHeight,
                grainAlongHeight: (session.parentGrain == .long) == (session.parentHeight >= session.parentWidth)
            )
        case .paper:
            PaperReferenceTable(currentGSM: session.gsm)
        }
    }

    // MARK: - Toolbar actions

    @ViewBuilder
    private var actions: some View {
        Menu {
            if store.projects.isEmpty {
                Text("No projects yet")
            }
            ForEach(store.projects) { project in
                Button(project.title) {
                    session.fill(from: project, assembledPageCount: 0)
                }
            }
        } label: {
            Label("Use Project", systemImage: "book.closed")
        }
        .help("Fill trim, pages, paper, and boards from a project")

        switch kind {
        case .sewing:
            Button {
                SewingTemplateExporter.export(plan: session.sewingPlan, spineHeight: session.pageHeight)
            } label: {
                Label("Export Template", systemImage: "square.and.arrow.up")
            }
            .help("Export a 1:1 PDF punching template for the signature folds")
        case .signatures:
            Menu {
                ForEach(store.projects.filter { $0.allows(.imposition) }) { project in
                    Button(project.title) {
                        let workspace = store.workspace(for: project.id)
                        workspace.job.creepPoints = CGFloat(session.signaturePlan.creepPoints)
                        workspace.markChanged()
                    }
                }
            } label: {
                Label("Apply Creep", systemImage: "arrow.right.to.line")
            }
            .help("Set this creep on a project's imposition")
        default:
            EmptyView()
        }
    }

    // MARK: - Inputs & results

    @ViewBuilder
    private var inputs: some View {
        switch kind {
        case .caseBinding: caseInputs
        case .signatures: signatureInputs
        case .sewing: sewingInputs
        case .sheetYield: yieldInputs
        case .paper: paperInputs
        }
    }

    private var bookSection: some View {
        section("Text block") {
            field("Width", $session.pageWidth, "mm")
            field("Height", $session.pageHeight, "mm")
            intField("Pages", $session.pageCount)
            field("Paper", $session.gsm, "gsm")
        }
    }

    private var caseInputs: some View {
        let plan = session.casePlan
        return VStack(alignment: .leading, spacing: 18) {
            bookSection
            section("Case") {
                field("Board", $session.boardThickness, "mm")
                field("Square", $session.square, "mm")
                field("Joint gap", $session.jointGap, "mm")
                field("Board setback", $session.boardSetback, "mm")
                field("Turn-in", $session.turnIn, "mm")
            }
            section("Cut list") {
                result("Boards ×2", size(plan.boardWidth, plan.boardHeight))
                result("Spine stiffener", size(plan.spineWidth, plan.boardHeight))
                result("Covering material", size(plan.coverWidth, plan.coverHeight), emphasized: true)
                result("Text block", String(format: "%.1f mm thick", plan.blockThickness))
                result("Corner cut", String(format: "%.1f mm off corner", plan.cornerCutOffset))
            }
            footnote("Square is the board overhang at head, tail, and fore-edge. Set boards back from the spine so they clear the shoulder.")
        }
    }

    private var signatureInputs: some View {
        let plan = session.signaturePlan
        return VStack(alignment: .leading, spacing: 18) {
            section("Book") {
                intField("Pages", $session.pageCount)
                field("Paper", $session.gsm, "gsm")
                intField("Sheets / signature", $session.sheetsPerSignature)
            }
            section("Plan") {
                result("Signatures", "\(plan.signatureCount) × \(plan.pagesPerSignature) pp", emphasized: true)
                result("Blank pages to add", "\(plan.blankPages)")
                result("Sheets to fold", "\(plan.totalSheets)")
                result("Block thickness", String(format: "%.1f mm", plan.blockThickness))
                result("Creep", String(format: "%.2f mm · %.1f pt", plan.creepMM, plan.creepPoints))
            }
            footnote("Creep is the innermost sheet's fore-edge push-out. Apply it to a project's imposition, then confirm with a folded proof.")
        }
    }

    private var sewingInputs: some View {
        let plan = session.sewingPlan
        return VStack(alignment: .leading, spacing: 18) {
            section("Spine") {
                field("Spine height", $session.pageHeight, "mm")
                intField("Stations", $session.stationCount)
                field("Kettle inset", $session.kettleInset, "mm")
            }
            section("Stations from head") {
                ForEach(Array(plan.stations.enumerated()), id: \.offset) { index, position in
                    let isKettle = index == 0 || index == plan.stations.count - 1
                    result(isKettle ? "K · kettle" : "\(index)", String(format: "%.1f mm", position))
                }
            }
            section("Thread") {
                result("Signatures", "\(session.signaturePlan.signatureCount)")
                result("Thread length", String(format: "%.0f mm · %.1f m", plan.threadLength, plan.threadLength / 1000), emphasized: true)
            }
            footnote("Thread uses one spine height per signature plus two for tails and tie-offs. Signature count comes from the Signatures calculator.")
        }
    }

    private var yieldInputs: some View {
        let plan = session.yieldPlan
        return VStack(alignment: .leading, spacing: 18) {
            section("Parent sheet") {
                Menu("Preset") {
                    ForEach(CalculatorMath.ParentSheet.presets) { preset in
                        Button(String(format: "%@ — %.0f × %.0f mm", preset.name, preset.width, preset.height)) {
                            session.applyParentPreset(preset)
                        }
                    }
                }
                .fixedSize()
                field("Width", $session.parentWidth, "mm")
                field("Height", $session.parentHeight, "mm")
                Picker("Grain", selection: $session.parentGrain) {
                    ForEach(CalculatorMath.GrainDirection.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            section("Page") {
                field("Trim width", $session.pageWidth, "mm")
                field("Trim height", $session.pageHeight, "mm")
                field("Trim allowance", $session.trimAllowance, "mm")
                intField("Pages", $session.pageCount)
            }
            section("Yield") {
                result("Folio, flat", size(plan.folioWidth, plan.folioHeight))
                result("Folios / sheet", "\(plan.perSheet)  (\(plan.columns) × \(plan.rows))", emphasized: true)
                result("Ignoring grain", "\(plan.crossGrainCount)")
                result("Parent sheets", "\(plan.parentSheetsNeeded)")
                result("Waste", String(format: "%.0f%%", plan.wastePercent))
            }
            footnote("Folios are placed so the fold runs with the grain, which lets pages turn and lie flat. Each folio carries 4 pages.")
        }
    }

    private var paperInputs: some View {
        VStack(alignment: .leading, spacing: 18) {
            section("Convert") {
                field("GSM", $session.gsm, "gsm")
                field("Bond", Binding(
                    get: { BindingMath.gsmToBondLb(session.gsm) },
                    set: { session.gsm = BindingMath.bondLbToGSM($0) }
                ), "lb")
            }
            section("Estimate") {
                result("Caliper", String(format: "%.3f mm", CalculatorMath.sheetCaliper(gsm: session.gsm)))
                result("Pages per inch", String(format: "%.0f", CalculatorMath.pagesPerInch(gsm: session.gsm)), emphasized: true)
                result("\(session.pageCount) pages", String(format: "%.1f mm block", CalculatorMath.textBlockThickness(pageCount: session.pageCount, gsm: session.gsm)))
            }
        }
    }

    // MARK: - Rows

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            WorkbenchInspectorChrome.SectionTitle(title)
            content()
        }
    }

    /// Label left, control right-aligned — keeps every field in one column.
    private func row<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .foregroundStyle(ArtisanTheme.textSecondary)
                .lineLimit(1)
            Spacer(minLength: 8)
            content()
        }
    }

    /// `unit == "mm"` makes a length field (shown in the preferred unit, accepts 6in, 1p6, 210-6…);
    /// other units are plain numbers that still accept arithmetic.
    private func field(_ label: String, _ value: Binding<Double>, _ unit: String) -> some View {
        row(label) {
            if unit == "mm" {
                CoverInspectorNumberField(value: value.wrappedValue, fractionDigits: 1, width: 72, isLength: true) {
                    value.wrappedValue = $0
                }
            } else {
                HStack(spacing: 4) {
                    CoverInspectorNumberField(value: value.wrappedValue, fractionDigits: 2, width: 72) {
                        value.wrappedValue = $0
                    }
                    Text(unit)
                        .font(.caption)
                        .foregroundStyle(ArtisanTheme.textTertiary)
                }
            }
        }
    }

    private func intField(_ label: String, _ value: Binding<Int>) -> some View {
        row(label) {
            HStack(spacing: 4) {
                TextField(label, value: value, format: .number)
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .frame(width: 72)
                Stepper(label, value: value, in: 0...10_000)
                    .labelsHidden()
                    .controlSize(.small)
                    .frame(width: 28, alignment: .leading)
            }
        }
    }

    private func result(_ label: String, _ value: String, emphasized: Bool = false) -> some View {
        row(label) {
            Text(value)
                .font(ArtisanTheme.technicalCaption)
                .monospacedDigit()
                .foregroundStyle(emphasized ? ArtisanTheme.secondary : ArtisanTheme.textPrimary)
                .textSelection(.enabled)
        }
    }

    private func footnote(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(ArtisanTheme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func size(_ w: Double, _ h: Double) -> String {
        String(format: "%.1f × %.1f mm", w, h)
    }
}

#Preview {
    CalculatorsView()
        .environmentObject(AppStore())
        .preferredColorScheme(.dark)
        .frame(width: 1000, height: 640)
}
