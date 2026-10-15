import SwiftUI

/// Preferences window (⌘,). Kept small and form-based, like other Mac apps.
struct SettingsView: View {
    @AppStorage("defaultPaperGSM") private var defaultPaperGSM = 80.0
    @AppStorage("preferGuideMarks") private var preferGuideMarks = false
    @AppStorage(MeasurementUnit.storageKey) private var unitRaw = MeasurementUnit.millimeters.rawValue

    var body: some View {
        TabView {
            Form {
                Section {
                    Picker("Measurement units", selection: $unitRaw) {
                        ForEach(MeasurementUnit.allCases) { unit in
                            Text(unit.label).tag(unit.rawValue)
                        }
                    }
                } footer: {
                    Text("Length fields show this unit. Any field also accepts other units and arithmetic — 6in, 152mm, 1p6, 210-6.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section {
                    TextField("Default text paper (GSM)", value: $defaultPaperGSM, format: .number)
                    Toggle("Prefer guide marks on new imposes", isOn: $preferGuideMarks)
                } footer: {
                    Text("These defaults apply when you create a new masterwork.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("General", systemImage: "gearshape") }
        }
        .frame(width: 480, height: 320)
    }
}

struct SupportView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
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
        .background(ArtisanTheme.contentBackground)
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
