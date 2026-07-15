import AppKit
import SwiftUI

/// Project-scoped workbench: imposition, cover, and materials — not global nav items.
struct ProjectWorkbenchView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.colorScheme) private var colorScheme
    let project: BinderyProject
    @ObservedObject var workspace: BindingWorkspace
    @State private var toolPendingUnlock: ProjectTool?
    @State private var isEditingTitle = false
    @State private var titleDraft = ""
    @FocusState private var isTitleFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            workbenchHeader
            Divider()
            toolBody
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                projectToolPicker
            }
        }
        .alert(
            toolPendingUnlock?.unlockPromptTitle ?? "Add section?",
            isPresented: Binding(
                get: { toolPendingUnlock != nil },
                set: { if !$0 { toolPendingUnlock = nil } }
            )
        ) {
            Button("Cancel", role: .cancel) {
                toolPendingUnlock = nil
            }
            Button("Create Section") {
                if let tool = toolPendingUnlock {
                    store.enableTool(tool)
                }
                toolPendingUnlock = nil
            }
        } message: {
            Text(toolPendingUnlock?.unlockPromptMessage ?? "")
        }
    }

    /// Project identity in the content chrome; tool switcher lives in the window toolbar.
    private var workbenchHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                projectTitleView
                Text(project.displaySubtitle)
                    .font(.caption)
                    .foregroundStyle(headerSubtitleColor)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
    }

    @ViewBuilder
    private var projectTitleView: some View {
        if isEditingTitle {
            TextField("Project name", text: $titleDraft)
                .textFieldStyle(.plain)
                .font(ArtisanTheme.sectionFont)
                .foregroundStyle(headerTitleColor)
                .lineLimit(1)
                .focused($isTitleFieldFocused)
                .onSubmit { commitTitleEdit() }
                .onChange(of: isTitleFieldFocused) { focused in
                    guard !focused, isEditingTitle else { return }
                    commitTitleEdit()
                }
                .onExitCommand { cancelTitleEdit() }
        } else {
            Text(project.title)
                .font(ArtisanTheme.sectionFont)
                .foregroundStyle(headerTitleColor)
                .help("Double-click to rename")
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { beginTitleEdit() }
        }
    }

    private func beginTitleEdit() {
        titleDraft = project.title
        isEditingTitle = true
        DispatchQueue.main.async {
            isTitleFieldFocused = true
        }
    }

    private func commitTitleEdit() {
        isEditingTitle = false
        isTitleFieldFocused = false

        let trimmed = titleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            titleDraft = project.title
            return
        }
        guard trimmed != project.title else { return }
        store.renameProject(project.id, title: trimmed, author: project.author)
    }

    private func cancelTitleEdit() {
        isEditingTitle = false
        titleDraft = project.title
        isTitleFieldFocused = false
    }

    /// Brand navy is for light paper surfaces only — never on a dark window bar.
    private var headerTitleColor: Color {
        colorScheme == .dark ? .white : ArtisanTheme.primary
    }

    private var headerSubtitleColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.65) : Color(nsColor: .secondaryLabelColor)
    }

    private var projectToolPicker: some View {
        HStack(spacing: 2) {
            ForEach(ProjectTool.allCases) { tool in
                toolButton(tool)
            }
        }
        .padding(3)
        .background(
            Capsule(style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
        }
        .help(store.projectTool.help)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Tool")
    }

    private func toolButton(_ tool: ProjectTool) -> some View {
        let isSelected = store.projectTool == tool
        let isEnabled = project.allows(tool)
        return Button {
            if isEnabled {
                store.selectProjectTool(tool)
            } else {
                toolPendingUnlock = tool
            }
        } label: {
            Text(tool.title)
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(toolForeground(isSelected: isSelected, isEnabled: isEnabled))
                .padding(.horizontal, 14)
                .padding(.vertical, 5)
                .background {
                    if isSelected && isEnabled {
                        Capsule(style: .continuous)
                            .fill(headerTitleColor.opacity(colorScheme == .dark ? 0.18 : 0.1))
                    }
                }
        }
        .buttonStyle(.plain)
        .help(isEnabled ? tool.help : "Click to add a \(tool.sectionName) section to this project.")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint(isEnabled ? "" : "Not included yet — activates a prompt to create this section")
    }

    private func toolForeground(isSelected: Bool, isEnabled: Bool) -> Color {
        if !isEnabled {
            return headerTitleColor.opacity(colorScheme == .dark ? 0.28 : 0.32)
        }
        return isSelected
            ? headerTitleColor
            : headerTitleColor.opacity(colorScheme == .dark ? 0.75 : 0.7)
    }

    @ViewBuilder
    private var toolBody: some View {
        switch store.projectTool {
        case .imposition:
            ImpositionWorkbenchView(
                workspace: workspace,
                projectID: project.id,
                projectTitle: project.title
            )
        case .cover:
            CoverDesignerView(project: project)
        case .materials:
            MaterialsLogView(project: project)
        }
    }
}
