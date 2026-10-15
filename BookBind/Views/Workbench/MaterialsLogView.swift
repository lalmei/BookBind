import SwiftUI

struct MaterialsLogView: View {
    @EnvironmentObject private var store: AppStore
    let project: BinderyProject

    @State private var draftName = ""
    @State private var draftQuantity = ""
    @State private var draftNotes = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if project.materials.isEmpty {
                emptyState
            } else {
                list
            }
            Divider()
            addRow
        }
        .background(ArtisanTheme.contentBackground)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("Stock and notes for this book.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Prefill from Project Specs") {
                prefillMaterials()
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "list.bullet.clipboard")
                .font(.system(size: 36, weight: .ultraLight))
                .foregroundStyle(.secondary)
            Text("No materials logged")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("Add leather, board, thread, or foil for this project.")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var list: some View {
        List {
            ForEach(project.materials) { entry in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(entry.name)
                            .font(.headline)
                        Spacer()
                        if !entry.quantity.isEmpty {
                            Text(entry.quantity)
                                .font(ArtisanTheme.technicalCaption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if !entry.notes.isEmpty {
                        Text(entry.notes)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
            .onDelete(perform: delete)
        }
        .listStyle(.inset)
    }

    private var addRow: some View {
        HStack(spacing: 10) {
            TextField("Material", text: $draftName)
                .textFieldStyle(.roundedBorder)
            TextField("Qty", text: $draftQuantity)
                .textFieldStyle(.roundedBorder)
                .frame(width: 80)
            TextField("Notes", text: $draftNotes)
                .textFieldStyle(.roundedBorder)
            Button("Add") {
                addEntry()
            }
            .disabled(draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .buttonStyle(.borderedProminent)
            .tint(ArtisanTheme.primary)
        }
        .padding(16)
        .background(.bar)
    }

    private func addEntry() {
        let name = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let entry = MaterialEntry(
            name: name,
            quantity: draftQuantity.trimmingCharacters(in: .whitespacesAndNewlines),
            notes: draftNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        store.updateSelectedProject { $0.materials.append(entry) }
        draftName = ""
        draftQuantity = ""
        draftNotes = ""
    }

    private func delete(at offsets: IndexSet) {
        store.updateSelectedProject { $0.materials.remove(atOffsets: offsets) }
    }

    private func prefillMaterials() {
        let suggestions = suggestedMaterials()
        store.updateSelectedProject { project in
            let existing = Set(project.materials.map { $0.name.lowercased() })
            for entry in suggestions where !existing.contains(entry.name.lowercased()) {
                project.materials.append(entry)
            }
        }
    }

    private func suggestedMaterials() -> [MaterialEntry] {
        var entries = [
            MaterialEntry(
                name: project.coverMaterial.rawValue,
                quantity: "cover wrap",
                notes: "Sized for \(project.trimLabel) boards and spine"
            ),
            MaterialEntry(
                name: "Binder's board",
                quantity: "2 boards",
                notes: String(format: "%.1f mm thickness", project.boardThicknessMM)
            ),
            MaterialEntry(
                name: "Linen thread",
                quantity: "as needed",
                notes: project.architecture.rawValue
            )
        ]
        if project.showFoilLayer {
            entries.append(MaterialEntry(name: "Foil", quantity: "1 roll", notes: project.folioStampText))
        }
        if project.showDebossLayer {
            entries.append(MaterialEntry(name: "Deboss die", quantity: "1", notes: project.folioStampText))
        }
        return entries
    }
}
