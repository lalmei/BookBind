import Foundation
import SwiftUI

/// Owns global navigation and the list of masterworks.
@MainActor
final class AppStore: ObservableObject {
    @Published var projects: [BinderyProject] = []
    @Published var libraries: [AssetLibrary] = []
    @Published var selection: SidebarSelection = .global(.home)
    @Published var projectTool: ProjectTool = .imposition
    @Published var showNewMasterwork = false
    @Published var storeErrorMessage: String?

    /// One binding session per open project (imposition state).
    private var workspaces: [UUID: BindingWorkspace] = [:]
    private var restoredWorkspaceStates: [UUID: BindingWorkspaceState] = [:]
    private let projectStore: ProjectStore
    private let assetLibraryService: AssetLibraryService

    init(
        projectStore: ProjectStore = ProjectStore(),
        assetLibraryService: AssetLibraryService = AssetLibraryService()
    ) {
        self.projectStore = projectStore
        self.assetLibraryService = assetLibraryService
        let state = projectStore.load()
        self.projects = state.projects.map(\.project)
        self.restoredWorkspaceStates = Dictionary(
            uniqueKeysWithValues: state.projects.map { ($0.project.id, $0.workspace) }
        )
        do {
            self.libraries = try assetLibraryService.discoveredLibraries(persisted: state.libraries)
        } catch {
            self.libraries = state.libraries
            self.storeErrorMessage = error.localizedDescription
        }
    }

    var sidebarLibraries: [AssetLibrary] {
        libraries + assetLibraryService.cloudStubs()
    }

    var selectedProject: BinderyProject? {
        guard case let .project(id) = selection else { return nil }
        return projects.first { $0.id == id }
    }

    var selectedLibrary: AssetLibrary? {
        guard case let .library(id) = selection else { return nil }
        return sidebarLibraries.first { $0.id == id }
    }

    var selectedProjectIndex: Int? {
        guard case let .project(id) = selection else { return nil }
        return projects.firstIndex { $0.id == id }
    }

    func workspace(for projectID: UUID) -> BindingWorkspace {
        if let existing = workspaces[projectID] {
            return existing
        }
        let workspace = BindingWorkspace()
        if let restored = restoredWorkspaceStates[projectID] {
            workspace.restore(restored)
        }
        workspace.onChange = { [weak self] in
            self?.save()
        }
        workspaces[projectID] = workspace
        return workspace
    }

    func openHome() {
        selection = .global(.home)
    }

    func open(_ destination: GlobalDestination) {
        selection = .global(destination)
    }

    func openProject(_ id: UUID) {
        guard let project = projects.first(where: { $0.id == id }) else { return }
        selection = .project(id)
        projectTool = project.allows(projectTool) ? projectTool : project.primaryTool
    }

    func selectProjectTool(_ tool: ProjectTool) {
        guard let project = selectedProject, project.allows(tool) else { return }
        projectTool = tool
    }

    /// Unlocks a previously grayed-out workbench section on the open project and switches to it.
    /// When adding Imposition or Cover, seeds trim/paper from the other side so sizes stay aligned.
    func enableTool(_ tool: ProjectTool) {
        guard selectedProjectIndex != nil else { return }
        guard let projectID = selectedProject?.id else { return }
        let workspace = workspace(for: projectID)

        updateSelectedProject { project in
            project.enabledTools.insert(tool)
            switch tool {
            case .imposition:
                workspace.job.applyProjectTrim(widthMM: project.widthMM, heightMM: project.heightMM)
                workspace.job.applyArchitecture(project.architecture)
                workspace.refreshPlan()
            case .cover:
                project.applyImpositionTrim(from: workspace.job)
                // Fall back to assembled/source page size when paper is still "keep source".
                if workspace.job.resolvedTrimSize == nil,
                   let pageSize = workspace.sources.first?.pageSize {
                    project.applyImpositionTrim(
                        widthPoints: pageSize.width,
                        heightPoints: pageSize.height
                    )
                }
            case .materials:
                break
            }
        }
        projectTool = tool
    }

    func openLibrary(_ id: UUID) {
        guard sidebarLibraries.contains(where: { $0.id == id }) else { return }
        selection = .library(id)
    }

    func addLibrary(from url: URL) {
        let candidate = assetLibraryService.library(fromFolder: url)
        do {
            libraries = try assetLibraryService.discoveredLibraries(persisted: libraries + [candidate])
            save()
            openLibrary(candidate.id)
        } catch {
            storeErrorMessage = error.localizedDescription
        }
    }

    func removeLibrary(_ id: UUID) {
        guard let library = libraries.first(where: { $0.id == id }),
              !library.isAutoLinked else {
            return
        }
        libraries.removeAll { $0.id == id }
        if case let .library(selected) = selection, selected == id {
            selection = .global(.home)
        }
        save()
    }

    func isLibraryAvailable(_ library: AssetLibrary) -> Bool {
        assetLibraryService.isAvailable(library)
    }

    func items(in library: AssetLibrary) -> [AssetLibraryItem] {
        assetLibraryService.enumerateItems(in: library)
    }

    /// Starts a single-purpose project — only the chosen tool is unlocked; others stay grayed out.
    func startQuickWork(_ tool: ProjectTool) {
        createMasterwork(
            title: Self.scratchTitle(for: tool),
            author: "",
            heightMM: 229,
            widthMM: 152,
            architecture: .sectionSewn,
            enabledTools: [tool],
            initialTool: tool
        )
    }

    func createMasterwork(
        title: String,
        author: String,
        heightMM: Double,
        widthMM: Double,
        architecture: BindingArchitecture,
        enabledTools: Set<ProjectTool> = Set(ProjectTool.allCases),
        initialTool: ProjectTool? = nil
    ) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let defaults = UserDefaults.standard
        var project = BinderyProject(
            title: trimmed,
            author: author.trimmingCharacters(in: .whitespacesAndNewlines),
            heightMM: heightMM,
            widthMM: widthMM,
            architecture: architecture,
            enabledTools: enabledTools
        )
        let defaultGSM = defaults.double(forKey: "defaultPaperGSM")
        if defaultGSM > 0 {
            project.textPaperGSM = defaultGSM
        }
        projects.insert(project, at: 0)
        let workspace = workspace(for: project.id)
        workspace.job.showGuideMarks = defaults.bool(forKey: "preferGuideMarks")
        workspace.job.applyProjectTrim(widthMM: project.widthMM, heightMM: project.heightMM)
        workspace.job.applyArchitecture(project.architecture)
        workspace.onChange?()
        showNewMasterwork = false
        save()
        selection = .project(project.id)
        if let initialTool, project.allows(initialTool) {
            projectTool = initialTool
        } else {
            projectTool = project.primaryTool
        }
    }

    /// Keeps cover board trim aligned when the imposition paper size changes.
    func syncProjectTrimFromImposition(projectID: UUID) {
        guard let index = projects.firstIndex(where: { $0.id == projectID }) else { return }
        let job = workspace(for: projectID).job
        guard job.resolvedTrimSize != nil else { return }
        var project = projects[index]
        project.applyImpositionTrim(from: job)
        guard project.widthMM != projects[index].widthMM
            || project.heightMM != projects[index].heightMM else { return }
        projects[index] = project
        projects[index].updatedAt = Date()
        save()
    }

    /// Keeps imposition paper aligned when cover board trim changes.
    func syncImpositionFromProjectTrim(projectID: UUID) {
        guard let index = projects.firstIndex(where: { $0.id == projectID }) else { return }
        let project = projects[index]
        let workspace = workspace(for: projectID)
        workspace.job.applyProjectTrim(widthMM: project.widthMM, heightMM: project.heightMM)
        workspace.refreshPlan()
        workspace.onChange?()
    }

    private static func scratchTitle(for tool: ProjectTool) -> String {
        let token = String(UUID().uuidString.prefix(4)).uppercased()
        switch tool {
        case .imposition: return "Signature \(token)"
        case .cover: return "Cover \(token)"
        case .materials: return "Materials \(token)"
        }
    }

    /// Mutates the selected project. Pass `save: false` for high-frequency live
    /// updates (drag/resize/rotate ticks) and persist once when the gesture ends.
    func updateSelectedProject(save: Bool = true, _ mutate: (inout BinderyProject) -> Void) {
        guard let index = selectedProjectIndex else { return }
        mutate(&projects[index])
        projects[index].updatedAt = Date()
        if save {
            self.save()
        }
    }

    func renameProject(_ id: UUID, title: String, author: String) {
        guard let index = projects.firstIndex(where: { $0.id == id }) else { return }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }
        projects[index].title = trimmedTitle
        projects[index].author = author.trimmingCharacters(in: .whitespacesAndNewlines)
        projects[index].updatedAt = Date()
        save()
    }

    func duplicateProject(_ id: UUID) {
        guard let project = projects.first(where: { $0.id == id }) else { return }
        let sourceWorkspace = workspace(for: id)
        var copy = project
        copy.id = UUID()
        copy.title = "\(project.title) Copy"
        copy.createdAt = Date()
        copy.updatedAt = Date()
        projects.insert(copy, at: 0)
        restoredWorkspaceStates[copy.id] = sourceWorkspace.snapshot()
        save()
        openProject(copy.id)
    }

    func deleteProject(_ id: UUID) {
        projects.removeAll { $0.id == id }
        workspaces[id] = nil
        restoredWorkspaceStates[id] = nil
        if case let .project(selected) = selection, selected == id {
            selection = .global(.home)
        }
        save()
    }

    func save() {
        let records = projects.map { project in
            PersistedProjectRecord(
                project: project,
                workspace: workspaces[project.id]?.snapshot()
                    ?? restoredWorkspaceStates[project.id]
                    ?? BindingWorkspaceState()
            )
        }
        do {
            let persistedLibraries = libraries.filter { !$0.isAutoLinked && !$0.isCloudStub }
            try projectStore.save(PersistedAppState(projects: records, libraries: persistedLibraries))
            storeErrorMessage = nil
        } catch {
            storeErrorMessage = error.localizedDescription
        }
    }
}
