import SwiftUI

/// Project-type chooser: pick what you're making from illustrated cards, see how it's built
/// (or how the sheet folds and cuts), then name it.
struct NewMasterworkSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("newProjectKind") private var kindRaw = ProjectKind.caseBound.rawValue
    @AppStorage("newProjectStock") private var stockRaw = StockSheet.letter.rawValue

    @State private var title = ""
    @State private var author = ""
    @State private var widthMM = ProjectKind.caseBound.defaultTrim.width
    @State private var heightMM = ProjectKind.caseBound.defaultTrim.height
    @FocusState private var titleFocused: Bool

    let onCreate: (NewProjectRequest) -> Void

    private var kind: ProjectKind {
        ProjectKind(rawValue: kindRaw) ?? .caseBound
    }

    private var stock: StockSheet {
        StockSheet(rawValue: stockRaw) ?? .letter
    }

    private var canCreate: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                chooser
                    .frame(width: 330)
                Divider()
                detail
                    .frame(maxWidth: .infinity)
            }
            Divider()
            footer
        }
        .frame(width: 820, height: 600)
        .onAppear {
            applyDefaultTrim(for: kind)
            titleFocused = true
        }
    }

    // MARK: - Chooser

    private var chooser: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ForEach(ProjectKind.Group.allCases, id: \.self) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        WorkbenchInspectorChrome.SectionTitle(group.rawValue)
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                            ForEach(ProjectKind.kinds(in: group)) { item in
                                kindCard(item)
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
        .background(ArtisanTheme.contentBackground)
    }

    private func kindCard(_ item: ProjectKind) -> some View {
        let isSelected = item == kind
        return Button {
            select(item)
        } label: {
            VStack(spacing: 6) {
                ProjectKindIllustration(kind: item, detail: .thumbnail, stock: stock)
                    .frame(height: 58)
                    .background(ArtisanTheme.canvasBackground, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                Text(item.title)
                    .font(.caption.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? ArtisanTheme.textPrimary : ArtisanTheme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .padding(6)
            .background(
                isSelected ? ArtisanTheme.primary.opacity(0.14) : ArtisanTheme.cardBackground,
                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(isSelected ? ArtisanTheme.primary : ArtisanTheme.separator, lineWidth: isSelected ? 1.5 : 0.5)
            }
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .help(item.summary)
    }

    // MARK: - Detail

    private var detail: some View {
        VStack(alignment: .leading, spacing: 0) {
            ProjectKindIllustration(kind: kind, detail: .full, stock: stock)
                .frame(height: 230)
                .frame(maxWidth: .infinity)
                .background(ArtisanTheme.canvasBackground)
                .id(kind.rawValue + stock.rawValue)

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text(kind.title)
                    .font(ArtisanTheme.cardTitleFont)
                    .foregroundStyle(ArtisanTheme.primary)
                Text(kind.summary)
                    .font(.callout)
                    .foregroundStyle(ArtisanTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                factChips
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)

            Form {
                TextField("Title", text: $title, prompt: Text(kind.usesStockSheet ? "My Zine" : "Untitled Book"))
                    .focused($titleFocused)
                TextField("Author", text: $author, prompt: Text("Optional"))
                sizeFields
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
        }
    }

    private var factChips: some View {
        HStack(spacing: 6) {
            ForEach(kind.facts, id: \.self) { fact in
                Text(fact)
                    .font(.caption)
                    .foregroundStyle(ArtisanTheme.textPrimary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(ArtisanTheme.raisedFill, in: Capsule())
            }
        }
    }

    @ViewBuilder
    private var sizeFields: some View {
        if kind.usesStockSheet {
            Picker("Print on", selection: $stockRaw) {
                ForEach(StockSheet.allCases) { sheet in
                    Text(sheet.rawValue).tag(sheet.rawValue)
                }
            }
            let page = kind.pageSize(fromStock: stock)
            LabeledContent("Page size") {
                Text(String(format: "%.0f × %.0f mm", page.width, page.height))
                    .monospacedDigit()
                    .foregroundStyle(ArtisanTheme.textSecondary)
            }
        } else {
            LabeledContent("Trim") {
                HStack(spacing: 6) {
                    CoverInspectorNumberField(value: widthMM, fractionDigits: 1, width: 70, isLength: true) { widthMM = $0 }
                    Text("×").foregroundStyle(ArtisanTheme.textSecondary)
                    CoverInspectorNumberField(value: heightMM, fractionDigits: 1, width: 70, isLength: true) { heightMM = $0 }
                }
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Text(kind.usesStockSheet
                 ? "Opens in Imposition with the fold layout ready. Add Cover or other tools later."
                 : "Opens with Imposition, Cover, Endpapers, Preview, and Materials.")
                .font(.caption)
                .foregroundStyle(ArtisanTheme.textSecondary)
            Spacer()
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("Create") {
                onCreate(NewProjectRequest(
                    title: title,
                    author: author,
                    kind: kind,
                    widthMM: widthMM,
                    heightMM: heightMM,
                    stock: stock
                ))
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!canCreate)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private func select(_ item: ProjectKind) {
        guard item != kind else { return }
        withAnimation(.easeInOut(duration: 0.15)) {
            kindRaw = item.rawValue
        }
        applyDefaultTrim(for: item)
    }

    private func applyDefaultTrim(for item: ProjectKind) {
        guard !item.usesStockSheet else { return }
        widthMM = item.defaultTrim.width
        heightMM = item.defaultTrim.height
    }
}

#Preview {
    NewMasterworkSheet { _ in }
        .preferredColorScheme(.dark)
}
