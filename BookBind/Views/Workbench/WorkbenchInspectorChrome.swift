import AppKit
import SwiftUI

/// Shared trailing-inspector chrome for every workbench tool.
///
/// Visibility is one app-wide setting (like Pages/Keynote) toggled from the window
/// toolbar or View ▸ Show Inspector (⌥⌘I), so switching tools never moves the control.
enum WorkbenchInspectorChrome {
    static let visibilityKey = "workbenchInspectorVisible"
    static let minWidth: CGFloat = 280
    static let idealWidth: CGFloat = 320
    static let maxWidth: CGFloat = 380

    /// Toolbar button that shows or hides the inspector; place last in `.primaryAction`.
    struct ToolbarToggle: View {
        @AppStorage(WorkbenchInspectorChrome.visibilityKey) private var isVisible = true

        var body: some View {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isVisible.toggle()
                }
            } label: {
                Label(isVisible ? "Hide Inspector" : "Show Inspector", systemImage: "sidebar.trailing")
            }
            .help(isVisible ? "Hide Inspector (⌥⌘I)" : "Show Inspector (⌥⌘I)")
        }
    }

    /// Scrolling inspector column with consistent padding, width, and background.
    struct Panel<Content: View>: View {
        @ViewBuilder var content: () -> Content

        var body: some View {
            ScrollView {
                content()
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(
                minWidth: WorkbenchInspectorChrome.minWidth,
                idealWidth: WorkbenchInspectorChrome.idealWidth,
                maxWidth: WorkbenchInspectorChrome.maxWidth
            )
            .background(.background)
        }
    }

    /// Small-caps section label used by every inspector section.
    struct SectionTitle: View {
        let title: String

        init(_ title: String) {
            self.title = title
        }

        var body: some View {
            Text(title.uppercased())
                .font(ArtisanTheme.labelFont)
                .tracking(0.6)
                .foregroundStyle(.secondary)
        }
    }
}
