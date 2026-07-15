import AppKit
import SwiftUI

/// Collapse / expand control for workbench inspectors.
/// Uses adaptive label colors so shell `.tint` (navy/blue) cannot wash out the icon.
enum WorkbenchInspectorChrome {
    static let collapsedRailWidth: CGFloat = 32

    struct ToggleButton: View {
        @Binding var isVisible: Bool

        var body: some View {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isVisible.toggle()
                }
            } label: {
                Image(systemName: "sidebar.trailing")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(nsColor: .labelColor))
                    .frame(width: 28, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isVisible ? "Hide inspector" : "Show inspector")
            .accessibilityLabel(isVisible ? "Hide inspector" : "Show inspector")
        }
    }

    /// Narrow edge strip when the inspector is collapsed; the reopen icon stays
    /// near the same top-right location as the inspector header collapse button.
    struct CollapsedRail: View {
        @Binding var isVisible: Bool
        var title: String = "Inspector"

        var body: some View {
            VStack {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        isVisible = true
                    }
                } label: {
                    Image(systemName: "sidebar.trailing")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color(nsColor: .labelColor))
                        .frame(width: 28, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Show \(title.lowercased())")
                .accessibilityLabel("Show \(title.lowercased())")
                .padding(.top, 16)

                Spacer(minLength: 0)
            }
            .frame(width: WorkbenchInspectorChrome.collapsedRailWidth)
            .background(Color(nsColor: .windowBackgroundColor))
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(Color(nsColor: .separatorColor))
                    .frame(width: 1)
            }
        }
    }
}
