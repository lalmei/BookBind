import SwiftUI

struct SettingsView: View {
    @AppStorage("defaultPaperGSM") private var defaultPaperGSM = 80.0
    @AppStorage("preferGuideMarks") private var preferGuideMarks = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Settings")
                    .font(ArtisanTheme.displayFont)
                    .foregroundStyle(ArtisanTheme.primary)

                Text("Preferences for new work. Equipment calibration can grow here later.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Form {
                    TextField("Default text paper (GSM)", value: $defaultPaperGSM, format: .number)
                    Toggle("Prefer guide marks on new imposes", isOn: $preferGuideMarks)
                    Text("These defaults apply when you create a new masterwork.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .formStyle(.grouped)
                .frame(maxWidth: 480)
            }
            .padding(36)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(ArtisanTheme.surfaceBright)
    }
}

struct SupportView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Support")
                    .font(ArtisanTheme.displayFont)
                    .foregroundStyle(ArtisanTheme.primary)

                Text("Short binding guides and current product boundaries.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                guideRow(
                    "Home",
                    "Your masterworks. Open one to reach project tools."
                )
                guideRow(
                    "Calculators",
                    "Spine, GSM, and creep estimates without a project."
                )
                guideRow(
                    "Imposition",
                    "Inside a project: assemble PDFs, set signatures, bind and export."
                )
                guideRow(
                    "Cover",
                    "Inside a project: board and spine blueprint with foil/deboss layers."
                )
                guideRow(
                    "Materials",
                    "Inside a project: note the stock you need for that book."
                )
                guideRow(
                    "Section-sewn",
                    "Use multiple signatures of 4–32 pages. Print duplex, flip on short edge, fold each sheet, nest by signature, then sew."
                )
                guideRow(
                    "Saddle-stitch",
                    "Use one nested signature for pamphlets and thin booklets. Pads to a multiple of four before export."
                )
                guideRow(
                    "Endpapers",
                    "Choose blank, solid-color swatches, or artwork/PDF cycling from the project Imposition controls."
                )
                guideRow(
                    "Later",
                    "Direct print/booklet dialog and EPUB conversion remain planned; current output is print-ready PDF export."
                )
            }
            .padding(36)
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(ArtisanTheme.surfaceBright)
    }

    private func guideRow(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
                .foregroundStyle(ArtisanTheme.primary)
            Text(body)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
    }
}

#Preview("Settings") {
    SettingsView()
}

#Preview("Support") {
    SupportView()
}
