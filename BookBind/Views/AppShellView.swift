import AppKit
import SwiftUI

/// Root chrome: global tools in the sidebar; project workbenches in the detail pane.
struct AppShellView: View {
    @StateObject private var store = AppStore()
    @State private var renamingProject: BinderyProject?
    @State private var projectPendingDeletion: BinderyProject?

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 300)
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(ArtisanTheme.surfaceBright)
        }
        .tint(ArtisanTheme.primary)
        .sheet(isPresented: $store.showNewMasterwork) {
            NewMasterworkSheet { title, author, height, width, architecture in
                store.createMasterwork(
                    title: title,
                    author: author,
                    heightMM: height,
                    widthMM: width,
                    architecture: architecture
                )
            }
        }
        .sheet(item: $renamingProject) { project in
            RenameMasterworkSheet(project: project) { title, author in
                store.renameProject(project.id, title: title, author: author)
                renamingProject = nil
            }
        }
        .environmentObject(store)
        .onReceive(NotificationCenter.default.publisher(for: .bookBindNewMasterwork)) { _ in
            store.showNewMasterwork = true
        }
        .alert("Could not save BookBind data", isPresented: Binding(
            get: { store.storeErrorMessage != nil },
            set: { if !$0 { store.storeErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { store.storeErrorMessage = nil }
        } message: {
            Text(store.storeErrorMessage ?? "")
        }
        .alert(
            "Delete “\(projectPendingDeletion?.title ?? "Project")”?",
            isPresented: Binding(
                get: { projectPendingDeletion != nil },
                set: { if !$0 { projectPendingDeletion = nil } }
            )
        ) {
            Button("Cancel", role: .cancel) { projectPendingDeletion = nil }
            Button("Delete", role: .destructive) {
                if let id = projectPendingDeletion?.id {
                    store.deleteProject(id)
                }
                projectPendingDeletion = nil
            }
        } message: {
            Text("This removes the project from BookBind. This cannot be undone.")
        }
    }

    private var sidebar: some View {
        List(selection: Binding(
            get: { store.selection },
            set: { newValue in
                guard let newValue else { return }
                if case let .project(id) = newValue {
                    store.openProject(id)
                } else {
                    store.selection = newValue
                }
            }
        )) {
            Section("Workbench") {
                ForEach(GlobalDestination.allCases) { destination in
                    Label(destination.title, systemImage: destination.systemImage)
                        .tag(SidebarSelection.global(destination))
                }
            }

            Section {
                ForEach(store.sidebarLibraries) { library in
                    libraryRow(library)
                }
            } header: {
                HStack {
                    Text("Libraries")
                    Spacer()
                    Button {
                        chooseAssetLibrary()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.borderless)
                    .help("Add Asset Library")
                }
            }

            Section {
                ForEach(store.projects) { project in
                    HStack(spacing: 6) {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(project.title)
                                    .lineLimit(1)
                                Text(project.displaySubtitle)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        } icon: {
                            Image(systemName: "book")
                        }

                        Spacer(minLength: 4)

                        Button {
                            projectPendingDeletion = project
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                        .help("Delete Project")
                    }
                    .tag(SidebarSelection.project(project.id))
                    .contextMenu {
                        Button("Rename…") {
                            renamingProject = project
                        }
                        Button("Duplicate") {
                            store.duplicateProject(project.id)
                        }
                        Divider()
                        Button("Delete…", role: .destructive) {
                            projectPendingDeletion = project
                        }
                    }
                }
            } header: {
                HStack {
                    Text("Projects")
                    Spacer()
                    Button {
                        store.showNewMasterwork = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.borderless)
                    .help("New Masterwork")
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: 10) {
                SidebarQuickActionsView(
                    onNewMasterwork: { store.showNewMasterwork = true },
                    onSignatureLayout: { store.startQuickWork(.imposition) },
                    onCoverAndSpine: { store.startQuickWork(.cover) },
                    onMaterialsLog: { store.startQuickWork(.materials) }
                )
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .windowBackgroundColor))
        }
    }

    @ViewBuilder
    private func libraryRow(_ library: AssetLibrary) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(library.name)
                    .lineLimit(1)
                Text(library.pathHint ?? "Connect library")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        } icon: {
            Image(systemName: sidebarImage(for: library))
        }
        .tag(SidebarSelection.library(library.id))
        .contextMenu {
            if !library.isAutoLinked && !library.isCloudStub {
                Button("Remove") {
                    store.removeLibrary(library.id)
                }
            }
        }
    }

    private func chooseAssetLibrary() {
        let panel = NSOpenPanel()
        panel.title = "Add Asset Library"
        panel.message = "Choose a folder of PDFs and artwork for BookBind to link in the sidebar."
        panel.prompt = "Add Library"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true

        if panel.runModal() == .OK, let url = panel.url {
            store.addLibrary(from: url)
        }
    }

    private func sidebarImage(for library: AssetLibrary) -> String {
        switch library.kind {
        case .localFolder:
            return store.isLibraryAvailable(library) ? "folder" : "folder.badge.questionmark"
        case .cloudStub(let provider):
            return provider.systemImage
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch store.selection {
        case .global(.home):
            HomeView()
        case .global(.calculators):
            CalculatorsView()
        case .global(.settings):
            SettingsView()
        case .global(.support):
            SupportView()
        case .project(let id):
            if let project = store.projects.first(where: { $0.id == id }) {
                ProjectWorkbenchView(
                    project: project,
                    workspace: store.workspace(for: id)
                )
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "book.closed")
                        .font(.system(size: 36, weight: .ultraLight))
                        .foregroundStyle(.secondary)
                    Text("Project unavailable")
                        .font(ArtisanTheme.sectionFont)
                    Text("Select a project from the sidebar.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        case .library(let id):
            if let library = store.sidebarLibraries.first(where: { $0.id == id }) {
                AssetLibraryView(
                    library: library,
                    isAvailable: store.isLibraryAvailable(library),
                    items: store.items(in: library)
                )
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "folder.badge.questionmark")
                        .font(.system(size: 36, weight: .ultraLight))
                        .foregroundStyle(.secondary)
                    Text("Library unavailable")
                        .font(ArtisanTheme.sectionFont)
                    Text("Select an asset library from the sidebar.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

private struct SidebarQuickActionsView: View {
    let onNewMasterwork: () -> Void
    let onSignatureLayout: () -> Void
    let onCoverAndSpine: () -> Void
    let onMaterialsLog: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Quick Actions")
                .font(ArtisanTheme.labelFont)
                .tracking(0.8)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            quickAction("New Masterwork", systemImage: "plus", help: "Name a masterwork before working", action: onNewMasterwork)
            quickAction("Signature Layout", systemImage: "book.pages", help: "Start imposition in a new saved project", action: onSignatureLayout)
            quickAction("Cover & Spine", systemImage: "book.closed", help: "Start cover design in a new saved project", action: onCoverAndSpine)
            quickAction("Materials Log", systemImage: "cart", help: "Start a materials list in a new saved project", action: onMaterialsLog)
        }
        .padding(10)
        .background(
            Color.primary.opacity(0.06),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.55), lineWidth: 1)
        }
    }

    private func quickAction(
        _ title: String,
        systemImage: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.callout.weight(.medium))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .background(
                    Color.primary.opacity(0.05),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

#Preview {
    AppShellView()
        .frame(width: 1100, height: 760)
}
