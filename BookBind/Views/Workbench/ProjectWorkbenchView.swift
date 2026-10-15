import AppKit
import SwiftUI

/// Project-scoped workbench: imposition, cover, endpapers, preview, and materials — not global nav items.
///
/// Owns the window toolbar for every tool so the layout never shifts between them:
/// project title on the left, tool switcher centered, tool actions + inspector toggle on the right.
struct ProjectWorkbenchView: View {
    @EnvironmentObject private var store: AppStore
    let project: BinderyProject
    @ObservedObject var workspace: BindingWorkspace
    @State private var toolPendingUnlock: ProjectTool?
    @StateObject private var coverChrome = CoverEditorChrome()
    @StateObject private var endsheetChrome = CoverEditorChrome()
    @StateObject private var previewChrome = BookPreviewChrome()
    @State private var endsheetEditingFront = true

    var body: some View {
        toolBody
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle(titleBinding)
            .navigationSubtitle(project.displaySubtitle)
            .toolbarRole(.editor)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    projectToolPicker
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    PreflightButton(project: project, workspace: workspace)
                    toolActions
                    if store.projectTool.hasInspector {
                        WorkbenchInspectorChrome.ToolbarToggle()
                    }
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
            .onChange(of: project.id) { _ in
                coverChrome.viewMode = .fit
                coverChrome.zoomFactor = 1.0
                endsheetChrome.viewMode = .fit
                endsheetChrome.zoomFactor = 1.0
                endsheetEditingFront = true
                previewChrome.openAmount = 0
            }
    }

    /// Editable window title (click the title to rename, as in document-based Mac apps).
    private var titleBinding: Binding<String> {
        Binding(
            get: { project.title },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty, trimmed != project.title else { return }
                store.renameProject(project.id, title: trimmed, author: project.author)
            }
        )
    }

    // MARK: - Tool switcher

    /// Native segmented control. Locked tools stay visible with a "+" so they read as
    /// "add this section" rather than disabled; choosing one asks before unlocking.
    private var projectToolPicker: some View {
        Picker("Tool", selection: Binding(
            get: { store.projectTool },
            set: { tool in
                if project.allows(tool) {
                    store.selectProjectTool(tool)
                } else {
                    toolPendingUnlock = tool
                }
            }
        )) {
            ForEach(ProjectTool.allCases) { tool in
                toolLabel(tool).tag(tool)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .help(store.projectTool.help)
    }

    private func toolLabel(_ tool: ProjectTool) -> Text {
        if project.allows(tool) {
            return Text(tool.title)
        }
        return Text(Image(systemName: "plus")) + Text(" ") + Text(tool.title)
    }

    // MARK: - Tool actions

    @ViewBuilder
    private var toolActions: some View {
        switch store.projectTool {
        case .imposition:
            Button {
                workspace.showSignatureMap = true
            } label: {
                Label("Sheet Map", systemImage: "square.grid.3x2")
            }
            .disabled(workspace.signatureMap == nil)
            .help("Show signature / sheet page layout")

            Button {
                workspace.showFoldGuide = true
            } label: {
                Label("Fold Guide", systemImage: "scissors")
            }
            .help("Show fold and cut instructions for this layout")

            if workspace.isWorking || workspace.isPreviewStale {
                ProgressView()
                    .controlSize(.small)
                    .help("Binding with the latest settings…")
            }

            Button {
                workspace.exportBoundPDF()
            } label: {
                Label("Export PDF", systemImage: "square.and.arrow.up")
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])
            .disabled(!workspace.canExport)
            .help("Export the imposed PDF (⇧⌘S) — binds automatically as you edit")

        case .cover:
            CanvasZoomControls(chrome: coverChrome)
            exportMenu(
                production: {
                    CoverExportService.exportSVG(project: project, workspace: workspace, store: store, mode: .production)
                },
                clean: {
                    CoverExportService.exportSVG(project: project, workspace: workspace, store: store, mode: .clean)
                },
                blueprint: {
                    CoverExportService.exportBlueprintPDF(project: project, workspace: workspace, store: store)
                }
            )

        case .endpapers:
            CanvasZoomControls(chrome: endsheetChrome)
            exportMenu(
                production: {
                    EndsheetExportService.exportSVG(
                        project: project, workspace: workspace, store: store,
                        isFront: endsheetEditingFront, mode: .production
                    )
                },
                clean: {
                    EndsheetExportService.exportSVG(
                        project: project, workspace: workspace, store: store,
                        isFront: endsheetEditingFront, mode: .clean
                    )
                },
                blueprint: {
                    EndsheetExportService.exportBlueprintPDF(
                        project: project, workspace: workspace, store: store,
                        isFront: endsheetEditingFront
                    )
                }
            )

        case .preview:
            Button {
                previewChrome.toggleOpen()
            } label: {
                Label(
                    previewChrome.isOpen ? "Close Book" : "Open Book",
                    systemImage: previewChrome.isOpen ? "book.closed" : "book"
                )
            }
            .help(previewChrome.isOpen ? "Close the book" : "Open the book")

            Button {
                previewChrome.resetCamera()
            } label: {
                Label("Reset Camera", systemImage: "camera.metering.center.weighted")
            }
            .help("Reset the camera to the default view")

        case .materials:
            EmptyView()
        }
    }

    /// One Export control per canvas tool: the primary click exports the blueprint PDF,
    /// the menu offers the SVG variants.
    private func exportMenu(
        production: @escaping () -> Void,
        clean: @escaping () -> Void,
        blueprint: @escaping () -> Void
    ) -> some View {
        Menu {
            Button("Blueprint PDF…", action: blueprint)
            Divider()
            Button("Production SVG…", action: production)
            Button("Clean Artwork SVG…", action: clean)
        } label: {
            Label("Export", systemImage: "square.and.arrow.up")
        } primaryAction: {
            blueprint()
        }
        .help("Export blueprint PDF; hold for SVG options")
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
            CoverDesignerView(
                project: project,
                workspace: workspace,
                chrome: coverChrome
            )
        case .endpapers:
            EndsheetDesignerView(
                project: project,
                workspace: workspace,
                chrome: endsheetChrome,
                editingFront: $endsheetEditingFront
            )
        case .preview:
            BookPreviewWorkbenchView(project: project, workspace: workspace, chrome: previewChrome)
        case .materials:
            MaterialsLogView(project: project)
        }
    }
}

/// Fit / 1:1 scale and live zoom readout for the cover and endpaper canvases.
private struct CanvasZoomControls: View {
    @ObservedObject var chrome: CoverEditorChrome

    var body: some View {
        Picker("Scale", selection: $chrome.viewMode) {
            ForEach(CoverEditorChrome.ViewMode.allCases) { mode in
                Text(mode.shortLabel).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .help("Fit to window or show at 1:1 scale")

        Button {
            chrome.zoomFactor = 1.0
        } label: {
            Text(String(format: "%.0f%%", chrome.zoomFactor * 100))
                .monospacedDigit()
                .frame(minWidth: 40)
        }
        .help("Reset zoom")
    }
}
