import SwiftUI

/// Global quick-reference tools — no project required.
struct CalculatorsView: View {
    @EnvironmentObject private var store: AppStore

    @State private var pageCount = 256
    @State private var gsm = 80.0
    @State private var boardThickness = 2.0
    @State private var hingeGap = 8.0
    @State private var sheetsPerSignature = 4
    @State private var bondLb = 60.0

    private var textBlock: Double {
        BindingMath.textBlockThicknessMM(pageCount: pageCount, gsm: gsm)
    }

    private var spine: Double {
        BindingMath.caseSpineWidthMM(
            pageCount: pageCount,
            gsm: gsm,
            boardThicknessMM: boardThickness,
            hingeGapMM: hingeGap
        )
    }

    private var creep: Double {
        BindingMath.suggestedCreepPoints(gsm: gsm, sheetsPerSignature: sheetsPerSignature)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                header
                spineSection
                Divider().background(ArtisanTheme.rule)
                gsmSection
                Divider().background(ArtisanTheme.rule)
                creepSection
            }
            .padding(36)
            .frame(maxWidth: 560, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(.black)
        .background(Color.white)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Calculators")
                .font(ArtisanTheme.displayFont)
                .foregroundStyle(.black)
            Text("Quick measurements without opening a project.")
                .font(.callout)
                .foregroundStyle(.black.opacity(0.7))
            if let project = store.selectedProject {
                Text("Active project: \(project.title)")
                    .font(ArtisanTheme.technicalCaption)
                    .foregroundStyle(.black.opacity(0.55))
            }
        }
    }

    private var spineSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Spine width")
                .font(ArtisanTheme.sectionFont)
                .foregroundStyle(.black)

            gridRow("Pages", IntField(value: $pageCount))
            gridRow("Paper GSM", DoubleField(value: $gsm))
            gridRow("Board (mm)", DoubleField(value: $boardThickness))
            gridRow("Hinge gap (mm)", DoubleField(value: $hingeGap))

            resultRow("Text block", String(format: "%.2f mm", textBlock))
            resultRow("Case spine", String(format: "%.2f mm", spine))

            if store.selectedProject != nil {
                HStack {
                    Button("Use Project Page Count") {
                        useSelectedProjectPageCount()
                    }
                    Button("Apply to Project Cover") {
                        applyCoverInputsToProject()
                    }
                }
                .buttonStyle(.link)
                .foregroundStyle(.black)
            }
        }
    }

    private var gsmSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("GSM ↔ bond")
                .font(ArtisanTheme.sectionFont)
                .foregroundStyle(.black)

            gridRow("GSM", DoubleField(value: $gsm, onEdit: {
                bondLb = BindingMath.gsmToBondLb(gsm)
            }))
            gridRow("Bond (lb)", DoubleField(value: $bondLb, onEdit: {
                gsm = BindingMath.bondLbToGSM(bondLb)
            }))

            Text(String(format: "Sheet caliper ≈ %.3f mm", BindingMath.sheetThicknessMM(gsm: gsm)))
                .font(ArtisanTheme.technicalCaption)
                .foregroundStyle(.black.opacity(0.7))
        }
    }

    private var creepSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Creep hint")
                .font(ArtisanTheme.sectionFont)
                .foregroundStyle(.black)

            gridRow("Sheets / signature", IntField(value: $sheetsPerSignature))
            resultRow("Suggested creep", String(format: "%.1f pt", creep))

            Text("Copy into a project’s Imposition settings after a proof pull.")
                .font(.caption)
                .foregroundStyle(.black.opacity(0.55))

            if store.selectedProject != nil {
                Button("Apply Creep to Project") {
                    applyCreepToProject()
                }
                .buttonStyle(.link)
                .foregroundStyle(.black)
            }
        }
    }

    private func gridRow<Content: View>(_ label: String, _ content: Content) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.black.opacity(0.7))
            Spacer()
            content
                .frame(width: 100, alignment: .trailing)
        }
        .font(ArtisanTheme.technicalFont)
    }

    private func resultRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.black)
            Spacer()
            Text(value)
                .font(ArtisanTheme.technicalFont)
                .foregroundStyle(.black)
        }
        .padding(.top, 6)
    }

    private func useSelectedProjectPageCount() {
        guard let project = store.selectedProject else { return }
        let workspace = store.workspace(for: project.id)
        let count = workspace.assembledPageCount > 0 ? workspace.assembledPageCount : project.estimatedPageCount
        if count > 0 {
            pageCount = count
        }
    }

    private func applyCoverInputsToProject() {
        store.updateSelectedProject { project in
            project.estimatedPageCount = pageCount
            project.textPaperGSM = gsm
            project.boardThicknessMM = boardThickness
            project.hingeGapMM = hingeGap
        }
    }

    private func applyCreepToProject() {
        guard let project = store.selectedProject else { return }
        let workspace = store.workspace(for: project.id)
        workspace.job.creepPoints = CGFloat(max(0, creep))
        workspace.markChanged()
    }
}

private struct IntField: View {
    @Binding var value: Int

    var body: some View {
        TextField("", value: $value, format: .number)
            .multilineTextAlignment(.trailing)
            .monochromeInput()
    }
}

private struct DoubleField: View {
    @Binding var value: Double
    var onEdit: (() -> Void)?

    var body: some View {
        TextField(
            "",
            value: Binding(
                get: { value },
                set: {
                    value = $0
                    onEdit?()
                }
            ),
            format: .number.precision(.fractionLength(0...2))
        )
        .multilineTextAlignment(.trailing)
        .monochromeInput()
    }
}

private extension View {
    func monochromeInput() -> some View {
        self
            .textFieldStyle(.plain)
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.black, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color.white.opacity(0.8), lineWidth: 1)
            }
    }
}

#Preview {
    CalculatorsView()
        .frame(width: 700, height: 640)
}
