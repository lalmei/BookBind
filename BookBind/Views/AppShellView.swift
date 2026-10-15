import AppKit
import SwiftUI

/// Root chrome: global tools in the sidebar; project workbenches in the detail pane.
struct AppShellView: View {
    @EnvironmentObject private var store: AppStore
    @State private var renamingProject: BinderyProject?
    @State private var projectPendingDeletion: BinderyProject?

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 300)
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(ArtisanTheme.contentBackground)
        }
        .preferredColorScheme(.dark)
        .tint(ArtisanTheme.primary)
        .sheet(isPresented: $store.showNewMasterwork) {
            NewMasterworkSheet { request in
                store.createProject(request)
            }
        }
        .sheet(item: $renamingProject) { project in
            RenameMasterworkSheet(project: project) { title, author in
                store.renameProject(project.id, title: title, author: author)
                renamingProject = nil
            }
        }
        .alert("Could not save InABind data", isPresented: Binding(
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
            Text("This removes the project from InABind. This cannot be undone.")
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
            Section {
                ForEach(GlobalDestination.allCases) { destination in
                    Label(destination.title, systemImage: destination.systemImage)
                        .tag(SidebarSelection.global(destination))
                }
            }

            Section {
                ForEach(store.projects) { project in
                    projectRow(project)
                }
            } header: {
                sectionHeader("Projects") {
                    Menu {
                        Button("New Masterwork…") { store.showNewMasterwork = true }
                        Divider()
                        Section("Quick Project") {
                            QuickStartMenuItems(store: store)
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("New Project")
                }
            }

            Section {
                ForEach(store.sidebarLibraries) { library in
                    libraryRow(library)
                }
            } header: {
                sectionHeader("Libraries") {
                    Button {
                        chooseAssetLibrary()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.borderless)
                    .help("Add Asset Library")
                }
            }
        }
        .listStyle(.sidebar)
        .onDeleteCommand {
            if case let .project(id) = store.selection {
                projectPendingDeletion = store.projects.first { $0.id == id }
            }
        }
    }

    private func sectionHeader<Accessory: View>(
        _ title: String,
        @ViewBuilder accessory: () -> Accessory
    ) -> some View {
        HStack {
            Text(title)
            Spacer()
            accessory()
        }
    }

    private func projectRow(_ project: BinderyProject) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 1) {
                Text(project.title)
                    .lineLimit(1)
                Text(project.displaySubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        } icon: {
            Image(systemName: "book.closed")
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
        panel.message = "Choose a folder of PDFs and artwork for InABind to link in the sidebar."
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
        case .global(let destination):
            Group {
                switch destination {
                case .home: HomeView()
                case .calculators: CalculatorsView()
                case .support: SupportView()
                }
            }
            .navigationTitle(destination.title)
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
                .navigationTitle(library.name)
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

#Preview {
    AppShellView()
        .environmentObject(AppStore())
        .frame(width: 1100, height: 760)
}
