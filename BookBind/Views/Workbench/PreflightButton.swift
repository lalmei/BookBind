import SwiftUI

/// Toolbar status for live preflight: a quiet check when clean, a count when something needs
/// attention. The popover lists issues with one-click fixes and a jump to the right tool.
struct PreflightButton: View {
    @EnvironmentObject private var store: AppStore
    let project: BinderyProject
    @ObservedObject var workspace: BindingWorkspace
    @State private var isPresented = false

    private var issues: [PreflightIssue] {
        PreflightService.run(.init(
            project: project,
            job: workspace.job,
            sources: workspace.sources,
            assembledPageCount: workspace.assembledPageCount,
            plan: workspace.plan
        ))
    }

    var body: some View {
        let issues = issues
        let worst = issues.map(\.severity).max()
        let attention = issues.filter { $0.severity >= .warning }.count
        Button {
            isPresented.toggle()
        } label: {
            Label {
                Text("Preflight")
            } icon: {
                Image(systemName: Self.symbol(for: worst))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(Self.color(for: worst))
            }
            .labelStyle(.iconOnly)
            .overlay(alignment: .topTrailing) {
                if attention > 0 {
                    Text("\(attention)")
                        .font(.system(size: 9, weight: .bold).monospacedDigit())
                        .foregroundStyle(.black)
                        .padding(.horizontal, 3.5)
                        .background(Self.color(for: worst), in: Capsule())
                        .offset(x: 8, y: -6)
                }
            }
        }
        .help(attention == 0 ? "Preflight: ready to print" : "Preflight: \(attention) item\(attention == 1 ? "" : "s") to check")
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            PreflightList(issues: issues, onFix: apply, onShow: show)
        }
    }

    private func apply(_ issue: PreflightIssue) {
        guard let fix = issue.fix else { return }
        store.applyPreflightFix(fix, projectID: project.id)
    }

    private func show(_ issue: PreflightIssue) {
        isPresented = false
        if project.allows(issue.tool) {
            store.selectProjectTool(issue.tool)
        }
    }

    static func symbol(for severity: PreflightIssue.Severity?) -> String {
        switch severity {
        case .error: return "xmark.octagon.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .info, nil: return "checkmark.seal"
        }
    }

    static func color(for severity: PreflightIssue.Severity?) -> Color {
        switch severity {
        case .error: return Color(nsColor: .systemRed)
        case .warning: return ArtisanTheme.secondary
        case .info, nil: return ArtisanTheme.textSecondary
        }
    }
}

private struct PreflightList: View {
    let issues: [PreflightIssue]
    let onFix: (PreflightIssue) -> Void
    let onShow: (PreflightIssue) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                WorkbenchInspectorChrome.SectionTitle("Preflight")
                Spacer()
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(ArtisanTheme.textSecondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            Divider()

            if issues.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.seal")
                        .foregroundStyle(ArtisanTheme.textSecondary)
                    Text("Nothing to fix — ready to print.")
                        .foregroundStyle(ArtisanTheme.textPrimary)
                }
                .padding(14)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(issues) { issue in
                            row(issue)
                            Divider().padding(.leading, 38)
                        }
                    }
                }
                .frame(maxHeight: 360)
            }
        }
        .frame(width: 360)
    }

    private var summary: String {
        let errors = issues.filter { $0.severity == .error }.count
        let warnings = issues.filter { $0.severity == .warning }.count
        if errors + warnings == 0 { return "All clear" }
        return [errors > 0 ? "\(errors) error\(errors == 1 ? "" : "s")" : nil,
                warnings > 0 ? "\(warnings) warning\(warnings == 1 ? "" : "s")" : nil]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    private func row(_ issue: PreflightIssue) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: PreflightButton.symbol(for: issue.severity == .info ? nil : issue.severity))
                .foregroundStyle(PreflightButton.color(for: issue.severity == .info ? nil : issue.severity))
                .frame(width: 16)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text(issue.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ArtisanTheme.textPrimary)
                Text(issue.detail)
                    .font(.system(size: 11))
                    .foregroundStyle(ArtisanTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    if let fixTitle = issue.fixTitle {
                        Button(fixTitle) { onFix(issue) }
                            .controlSize(.small)
                    }
                    Button("Show in \(issue.tool.title)") { onShow(issue) }
                        .buttonStyle(.link)
                        .controlSize(.small)
                }
                .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}
