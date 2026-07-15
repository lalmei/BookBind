import Foundation
import SwiftUI

private enum ProjectsLayoutMode: String, CaseIterable, Identifiable {
    case cards
    case list

    var id: String { rawValue }

    var label: String {
        switch self {
        case .cards: return "Cards"
        case .list: return "List"
        }
    }

    var systemImage: String {
        switch self {
        case .cards: return "square.grid.2x2"
        case .list: return "list.bullet"
        }
    }
}

struct HomeView: View {
    @EnvironmentObject private var store: AppStore
    @AppStorage("homeProjectsLayout") private var layoutModeRaw = ProjectsLayoutMode.cards.rawValue

    private var layoutModeBinding: Binding<ProjectsLayoutMode> {
        Binding(
            get: { ProjectsLayoutMode(rawValue: layoutModeRaw) ?? .cards },
            set: { layoutModeRaw = $0.rawValue }
        )
    }

    private var layoutMode: ProjectsLayoutMode {
        layoutModeBinding.wrappedValue
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 40) {
                header

                if store.projects.isEmpty {
                    emptyState
                } else {
                    dashboard
                }
            }
            .padding(.horizontal, ArtisanTheme.marginDesktop)
            .padding(.vertical, 44)
            .frame(maxWidth: 1500, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .background(ArtisanTheme.surfaceBright)
    }

    private var header: some View {
        Text("BookBind")
            .font(ArtisanTheme.displayFont)
            .foregroundStyle(ArtisanTheme.primary)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 22) {
            sectionTitle("Active Projects")

            Button {
                store.showNewMasterwork = true
            } label: {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Start your first masterwork")
                        .font(ArtisanTheme.cardTitleFont)
                        .foregroundStyle(ArtisanTheme.primary)
                    Text("Create a book project to keep imposition, boards, spine estimates, foil layers, and material notes together.")
                        .font(ArtisanTheme.bodyFont)
                        .foregroundStyle(ArtisanTheme.onSurfaceVariant.opacity(0.82))
                        .fixedSize(horizontal: false, vertical: true)

                    Text("New Masterwork")
                        .font(ArtisanTheme.buttonFont)
                        .foregroundStyle(ArtisanTheme.surfaceBright)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(ArtisanTheme.secondary, in: RoundedRectangle(cornerRadius: ArtisanTheme.controlRadius, style: .continuous))
                }
                .padding(20)
                .frame(maxWidth: 480, alignment: .leading)
                .background(ArtisanTheme.surfaceContainerLowest, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(ArtisanTheme.outlineVariant.opacity(0.55), lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var dashboard: some View {
        projectsColumn
    }

    private var projectsColumn: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 16) {
                sectionTitle("Active Projects")
                Spacer(minLength: 12)
                layoutPicker
            }

            switch layoutMode {
            case .cards:
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 220), spacing: 14, alignment: .top)],
                    alignment: .leading,
                    spacing: 14
                ) {
                    ForEach(sortedProjects) { project in
                        ProjectCard(project: project) {
                            store.openProject(project.id)
                        }
                    }
                }
            case .list:
                VStack(spacing: 0) {
                    ForEach(Array(sortedProjects.enumerated()), id: \.element.id) { index, project in
                        ProjectListRow(project: project) {
                            store.openProject(project.id)
                        }
                        if index < sortedProjects.count - 1 {
                            Divider()
                                .background(ArtisanTheme.outlineVariant.opacity(0.35))
                        }
                    }
                }
                .background(ArtisanTheme.surfaceContainerLowest, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(ArtisanTheme.outlineVariant.opacity(0.45), lineWidth: 1)
                }
            }
        }
    }

    private var layoutPicker: some View {
        HStack(spacing: 2) {
            ForEach(ProjectsLayoutMode.allCases) { mode in
                let isSelected = layoutMode == mode
                Button {
                    layoutModeBinding.wrappedValue = mode
                } label: {
                    Image(systemName: mode.systemImage)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isSelected ? ArtisanTheme.primary : ArtisanTheme.onSurfaceVariant.opacity(0.72))
                        .frame(width: 34, height: 26)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(isSelected ? ArtisanTheme.surfaceContainerLowest : Color.clear)
                        )
                }
                .buttonStyle(.plain)
                .help(mode.label)
                .accessibilityLabel(mode.label)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(ArtisanTheme.surfaceContainer)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(ArtisanTheme.outlineVariant.opacity(0.45), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Project layout")
    }

    private var sortedProjects: [BinderyProject] {
        store.projects.sorted { $0.updatedAt > $1.updatedAt }
    }

    private func sectionTitle(_ title: String) -> some View {
        HStack(spacing: 14) {
            Rectangle()
                .fill(ArtisanTheme.outlineVariant.opacity(0.35))
                .frame(width: 32, height: 1)
            Text(title.uppercased())
                .font(ArtisanTheme.labelFont)
                .tracking(2.2)
                .foregroundStyle(ArtisanTheme.onSurfaceVariant.opacity(0.46))
        }
    }
}

private struct ProjectCard: View {
    let project: BinderyProject
    let action: () -> Void

    private var status: ProjectDashboardStatus {
        project.dashboardStatus
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(project.title)
                        .font(ArtisanTheme.cardTitleFont)
                        .foregroundStyle(ArtisanTheme.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Spacer(minLength: 8)

                    Text(project.updatedAt.formatted(.dateTime.month(.abbreviated).day()))
                        .font(ArtisanTheme.labelFont)
                        .foregroundStyle(ArtisanTheme.onSurfaceVariant.opacity(0.55))
                }

                HStack(spacing: 6) {
                    ForEach(project.dashboardTags, id: \.self) { tag in
                        Text(tag)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(ArtisanTheme.onSurfaceVariant.opacity(0.68))
                            .lineLimit(1)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .overlay {
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .stroke(ArtisanTheme.outlineVariant.opacity(0.45), lineWidth: 1)
                            }
                    }
                }

                Text("\(project.displaySubtitle) · \(project.trimLabel)")
                    .font(.system(size: 13))
                    .foregroundStyle(ArtisanTheme.onSurfaceVariant.opacity(0.78))
                    .lineLimit(1)

                ProjectProgressBar(status: status, barHeight: 3)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ArtisanTheme.surfaceContainerLowest, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(ArtisanTheme.outlineVariant.opacity(0.45), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct ProjectListRow: View {
    let project: BinderyProject
    let action: () -> Void

    private var status: ProjectDashboardStatus {
        project.dashboardStatus
    }

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(project.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(ArtisanTheme.primary)
                        .lineLimit(1)

                    Text("\(project.displaySubtitle) · \(project.trimLabel)")
                        .font(.system(size: 12))
                        .foregroundStyle(ArtisanTheme.onSurfaceVariant.opacity(0.72))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(status.phase)
                    .font(ArtisanTheme.labelFont)
                    .foregroundStyle(ArtisanTheme.onSurfaceVariant.opacity(0.55))
                    .lineLimit(1)

                Text(project.updatedAt.formatted(.dateTime.month(.abbreviated).day()))
                    .font(ArtisanTheme.labelFont)
                    .foregroundStyle(ArtisanTheme.onSurfaceVariant.opacity(0.5))
                    .frame(width: 48, alignment: .trailing)

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(ArtisanTheme.onSurfaceVariant.opacity(0.35))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct ProjectProgressBar: View {
    let status: ProjectDashboardStatus
    var barHeight: CGFloat = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(status.phase.uppercased())
                    .font(ArtisanTheme.labelFont)
                    .tracking(0.8)
                    .foregroundStyle(ArtisanTheme.onSurfaceVariant.opacity(0.55))
                Spacer()
                Text("\(status.progress)%")
                    .font(ArtisanTheme.labelFont)
                    .foregroundStyle(ArtisanTheme.onSurfaceVariant.opacity(0.55))
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(ArtisanTheme.surfaceContainerHigh)
                    Capsule()
                        .fill(status.progress > 55 ? ArtisanTheme.primary : ArtisanTheme.primary.opacity(0.35))
                        .frame(width: proxy.size.width * CGFloat(status.progress) / 100)
                }
            }
            .frame(height: barHeight)
        }
    }
}

private struct ProjectDashboardStatus {
    let progress: Int
    let phase: String
}

private extension BinderyProject {
    var dashboardStatus: ProjectDashboardStatus {
        var score = 20
        if !author.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { score += 8 }
        score += estimatedPageCount > 0 ? 20 : 8
        score += min(materials.count * 12, 28)
        if showFoilLayer || showDebossLayer || !folioStampText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            score += 12
        }

        let progress = min(max(score, 12), 96)
        let phase: String
        if materials.isEmpty {
            phase = "Material Sourcing"
        } else if estimatedPageCount == 0 {
            phase = "Planning Signatures"
        } else if progress < 70 {
            phase = "Cover Blueprint"
        } else {
            phase = "Consolidation Phase"
        }

        return ProjectDashboardStatus(progress: progress, phase: phase)
    }

    var dashboardTags: [String] {
        [architecture.rawValue, coverMaterial.shortLabel]
    }
}

private extension CoverMaterial {
    var shortLabel: String {
        switch self {
        case .moroccanGoat:
            return "Goat Leather"
        case .bookram:
            return "Bookram"
        case .buckram:
            return "Buckram"
        case .bookCloth:
            return "Book Cloth"
        case .paper:
            return "Decorative Paper"
        }
    }
}

struct RenameMasterworkSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var author: String

    let project: BinderyProject
    let onSave: (String, String) -> Void

    init(project: BinderyProject, onSave: @escaping (String, String) -> Void) {
        self.project = project
        self.onSave = onSave
        _title = State(initialValue: project.title)
        _author = State(initialValue: project.author)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Rename Masterwork")
                .font(ArtisanTheme.sectionFont)
                .padding(20)

            Divider()

            Form {
                TextField("Title", text: $title)
                TextField("Author", text: $author)
                Text(project.trimLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .formStyle(.grouped)
            .padding(.horizontal, 8)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    onSave(title, author)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .buttonStyle(.borderedProminent)
                .tint(ArtisanTheme.primary)
            }
            .padding(20)
        }
        .frame(width: 420, height: 280)
    }
}

struct NewMasterworkSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var author = ""
    @State private var heightMM = 229.0
    @State private var widthMM = 152.0
    @State private var architecture: BindingArchitecture = .caseBound

    let onCreate: (String, String, Double, Double, BindingArchitecture) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("New Masterwork")
                .font(ArtisanTheme.sectionFont)
                .padding(20)

            Divider()

            Form {
                TextField("Title", text: $title)
                TextField("Author", text: $author)

                Picker("Architecture", selection: $architecture) {
                    ForEach(BindingArchitecture.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }

                HStack {
                    TextField("Width (mm)", value: $widthMM, format: .number)
                    TextField("Height (mm)", value: $heightMM, format: .number)
                }

                Text(architecture.help)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .formStyle(.grouped)
            .padding(.horizontal, 8)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Create") {
                    onCreate(title, author, heightMM, widthMM, architecture)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .buttonStyle(.borderedProminent)
                .tint(ArtisanTheme.primary)
            }
            .padding(20)
        }
        .frame(width: 420, height: 420)
    }
}

#Preview {
    HomeView()
        .environmentObject(AppStore())
        .frame(width: 800, height: 600)
}
