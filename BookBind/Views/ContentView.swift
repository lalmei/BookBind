import AppKit
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var workspace = BindingWorkspace()
    @State private var isDropTargeted = false

    var body: some View {
        HSplitView {
            sourceSidebar
                .frame(minWidth: 220, idealWidth: 260, maxWidth: 320)

            VStack(spacing: 0) {
                configurationBar
                Divider()
                previewArea
                Divider()
                footerBar
            }
            .frame(minWidth: 560)
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
        }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [8, 4]))
                    .padding(12)
                    .allowsHitTesting(false)
            }
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { workspace.errorMessage != nil },
            set: { if !$0 { workspace.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { workspace.errorMessage = nil }
        } message: {
            Text(workspace.errorMessage ?? "")
        }
    }

    // MARK: - Sidebar

    private var sourceSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Sources")
                    .font(.headline)
                Spacer()
                Button {
                    openPanel()
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help("Add PDFs")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            Divider()

            if workspace.sources.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "doc.badge.plus")
                        .font(.system(size: 36, weight: .light))
                        .foregroundStyle(.secondary)
                    Text("Drop PDFs here")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text("or click + to browse")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(workspace.sources) { source in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "doc.richtext")
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(source.name)
                                    .lineLimit(2)
                                Text("\(source.pageCount) pages")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            Button {
                                workspace.removeSource(source)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.tertiary)
                            }
                            .buttonStyle(.borderless)
                        }
                        .padding(.vertical, 2)
                    }
                    .onMove(perform: workspace.moveSource)
                }
                .listStyle(.sidebar)
            }

            if let plan = workspace.plan {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Text("Plan")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(plan.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
            }
        }
        .background(.background)
    }

    // MARK: - Config

    private var configurationBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 20) {
                labeled("Binding") {
                    Picker("", selection: $workspace.job.bindingStyle) {
                        ForEach(BindingStyle.allCases) { style in
                            Text(style.rawValue).tag(style)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 140)
                    .onChange(of: workspace.job.bindingStyle) { _ in workspace.refreshPlan() }
                }

                if workspace.job.bindingStyle == .sectionSewn {
                    labeled("Signature") {
                        Picker("", selection: $workspace.job.signatureSize) {
                            ForEach(SignatureSize.allCases) { size in
                                Text(size.label).tag(size)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 160)
                        .onChange(of: workspace.job.signatureSize) { _ in workspace.refreshPlan() }
                    }
                }

                labeled("Endpapers") {
                    HStack(spacing: 6) {
                        Stepper("Front \(workspace.job.frontEndpapers)", value: $workspace.job.frontEndpapers, in: 0...16)
                            .onChange(of: workspace.job.frontEndpapers) { _ in workspace.refreshPlan() }
                        Stepper("Back \(workspace.job.backEndpapers)", value: $workspace.job.backEndpapers, in: 0...16)
                            .onChange(of: workspace.job.backEndpapers) { _ in workspace.refreshPlan() }
                    }
                }

                labeled("Paper") {
                    Picker("", selection: $workspace.job.paperSize) {
                        ForEach(PaperSize.allCases) { size in
                            Text(size.rawValue).tag(size)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 140)
                }

                Toggle("Page numbers", isOn: $workspace.job.pageNumbers.enabled)
                Toggle("Watermark", isOn: $workspace.job.watermark.enabled)
                Toggle("Crop marks", isOn: $workspace.job.addCropMarks)

                if workspace.job.pageNumbers.enabled {
                    labeled("Start #") {
                        TextField("", value: $workspace.job.pageNumbers.startAt, format: .number)
                            .frame(width: 44)
                    }
                }

                if workspace.job.watermark.enabled {
                    labeled("Mark") {
                        TextField("Watermark", text: $workspace.job.watermark.text)
                            .frame(width: 100)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(.bar)
    }

    // MARK: - Preview

    private var previewArea: some View {
        Group {
            if let document = workspace.previewDocument {
                PDFKitView(document: document)
            } else {
                VStack(spacing: 14) {
                    Image(systemName: "book.closed")
                        .font(.system(size: 48, weight: .ultraLight))
                        .foregroundStyle(.secondary)
                    Text("One-shot bind")
                        .font(.title2)
                    Text("Add PDFs, set signatures and endpapers, then bind.\nYou’ll get printer spreads ready to fold and sew.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 420)

                    if workspace.job.bindingStyle == .sectionSewn {
                        Text(BindingStyle.sectionSewn.help)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: 400)
                            .multilineTextAlignment(.center)
                    } else {
                        Text(BindingStyle.saddleStitch.help)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: 400)
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    // MARK: - Footer

    private var footerBar: some View {
        HStack(spacing: 12) {
            if workspace.isWorking {
                ProgressView()
                    .controlSize(.small)
            }

            if let status = workspace.statusMessage {
                Text(status)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else if workspace.totalSourcePages > 0 {
                Text("\(workspace.sources.count) file(s) · \(workspace.totalSourcePages) pages")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Bind") {
                workspace.runBinding()
            }
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(!workspace.canBind)

            Button("Export PDF…") {
                workspace.exportBoundPDF()
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])
            .disabled(workspace.previewDocument == nil)
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    // MARK: - Helpers

    private func labeled<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func openPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        if panel.runModal() == .OK {
            workspace.addPDFs(urls: panel.urls)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var handled = false
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                handled = true
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    guard let data = item as? Data,
                          let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                    Task { @MainActor in
                        workspace.addPDFs(urls: [url])
                    }
                }
            }
        }
        return handled
    }
}

#Preview {
    ContentView()
        .frame(width: 1000, height: 700)
}
