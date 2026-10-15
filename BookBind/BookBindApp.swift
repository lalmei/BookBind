import SwiftUI

@main
struct BookBindApp: App {
    @StateObject private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            AppShellView()
                .environmentObject(store)
                .focusedSceneObject(store)
        }
        .defaultSize(width: 1180, height: 780)
        .commands {
            SidebarCommands()
            InspectorCommands()
            ProjectCommands()
        }

        Settings {
            SettingsView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
                .tint(ArtisanTheme.primary)
        }
    }
}

/// File-menu entry points for new work; mirrors the sidebar "+" menu.
private struct ProjectCommands: Commands {
    @FocusedObject private var store: AppStore?

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Masterwork…") {
                store?.showNewMasterwork = true
            }
            .keyboardShortcut("n", modifiers: .command)
            .disabled(store == nil)

            Menu("New Quick Project") {
                QuickStartMenuItems(store: store)
            }
            .disabled(store == nil)
        }
    }
}

/// View-menu toggle for the shared workbench inspector (⌥⌘I, as in Pages and Keynote).
private struct InspectorCommands: Commands {
    @AppStorage(WorkbenchInspectorChrome.visibilityKey) private var isInspectorVisible = true

    var body: some Commands {
        CommandGroup(after: .sidebar) {
            Button(isInspectorVisible ? "Hide Inspector" : "Show Inspector") {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isInspectorVisible.toggle()
                }
            }
            .keyboardShortcut("i", modifiers: [.command, .option])
        }
    }
}

/// Single-purpose project starters, shared by the File menu and the sidebar "+" menu.
struct QuickStartMenuItems: View {
    let store: AppStore?

    var body: some View {
        Button("Signature Layout") { store?.startQuickWork(.imposition) }
        Button("Zine Layout") { store?.startZineQuickWork() }
        Button("Cover & Spine") { store?.startQuickWork(.cover) }
        Button("Materials Log") { store?.startQuickWork(.materials) }
    }
}
