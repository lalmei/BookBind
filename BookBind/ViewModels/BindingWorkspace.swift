import AppKit
import Foundation
import PDFKit
import SwiftUI

@MainActor
final class BindingWorkspace: ObservableObject {
    @Published var sources: [SourceDocument] = []
    @Published var job = BindingJob()
    @Published var plan: BindingPlan?
    @Published var previewDocument: PDFDocument?
    @Published var isWorking = false
    @Published var statusMessage: String?
    @Published var errorMessage: String?

    var totalSourcePages: Int {
        sources.reduce(0) { $0 + $1.pageCount }
    }

    var canBind: Bool {
        !sources.isEmpty && !isWorking
    }

    func addPDFs(urls: [URL]) {
        errorMessage = nil
        for url in urls {
            guard url.pathExtension.lowercased() == "pdf" else { continue }
            do {
                let (source, _) = try PDFDocumentService.load(url: url)
                if !sources.contains(where: { $0.url == source.url }) {
                    sources.append(source)
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        refreshPlan()
    }

    func removeSource(_ source: SourceDocument) {
        sources.removeAll { $0.id == source.id }
        previewDocument = nil
        refreshPlan()
    }

    func moveSource(from offsets: IndexSet, to offset: Int) {
        sources.move(fromOffsets: offsets, toOffset: offset)
        previewDocument = nil
        refreshPlan()
    }

    func refreshPlan() {
        guard totalSourcePages > 0 else {
            plan = nil
            return
        }
        plan = ImpositionService.plan(contentPageCount: totalSourcePages, job: job)
    }

    /// One-shot: merge → endpapers → decorate → impose → ready to export.
    func runBinding() {
        guard canBind else { return }
        isWorking = true
        errorMessage = nil
        statusMessage = "Binding…"

        let urls = sources.map(\.url)
        let jobSnapshot = job

        Task.detached(priority: .userInitiated) {
            do {
                let merged = try PDFDocumentService.merge(urls: urls)
                let plan = ImpositionService.plan(
                    contentPageCount: merged.pageCount,
                    job: jobSnapshot
                )

                let targetSize = jobSnapshot.paperSize.size
                let bookBlock = PDFDocumentService.buildBookBlock(
                    from: merged,
                    frontEndpapers: jobSnapshot.frontEndpapers,
                    backEndpapers: jobSnapshot.backEndpapers,
                    padPages: plan.padPages,
                    targetPageSize: targetSize
                )

                let decorated = PageDecorationService.decorate(
                    bookBlock,
                    pageNumbers: jobSnapshot.pageNumbers,
                    watermark: jobSnapshot.watermark,
                    frontEndpapers: jobSnapshot.frontEndpapers,
                    backEndpapers: jobSnapshot.backEndpapers + plan.padPages
                )

                let imposed = try ImpositionService.impose(
                    bookBlock: decorated,
                    plan: plan,
                    style: jobSnapshot.bindingStyle,
                    addCropMarks: jobSnapshot.addCropMarks
                )

                await MainActor.run {
                    self.plan = plan
                    self.previewDocument = imposed
                    self.statusMessage = "Ready — \(imposed.pageCount) printer sheets · \(plan.summary)"
                    self.isWorking = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.statusMessage = nil
                    self.isWorking = false
                }
            }
        }
    }

    func exportBoundPDF() {
        guard let document = previewDocument else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = suggestedExportName()
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }

        if document.write(to: url) {
            statusMessage = "Saved \(url.lastPathComponent)"
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            errorMessage = BindingError.exportFailed.localizedDescription
        }
    }

    private func suggestedExportName() -> String {
        let base = sources.first?.name.replacingOccurrences(of: ".pdf", with: "", options: .caseInsensitive)
            ?? "book"
        return "\(base)-bound.pdf"
    }
}
