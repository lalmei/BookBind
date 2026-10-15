import AppKit
import Foundation
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class BindingWorkspace: ObservableObject {
    @Published var sources: [SourceDocument] = []
    @Published var job = BindingJob()
    @Published var bookBlockItems: [BookBlockItem] = []
    @Published var plan: BindingPlan?
    @Published var signatureMap: SignatureMap?
    @Published var previewDocument: PDFDocument?
    @Published var isWorking = false
    @Published var statusMessage: String?
    @Published var errorMessage: String?
    @Published var showSignatureMap = false
    @Published var showFoldGuide = false
    /// True from an edit until the matching auto-bind lands; Export waits for a current preview.
    @Published private(set) var isPreviewStale = false

    /// Pause after the last edit before re-binding, so typing in a field binds once.
    static let autoBindDelay: Duration = .milliseconds(600)
    private var autoBindTask: Task<Void, Never>?
    /// Bumped on every edit; a bind whose generation is outdated when it finishes is discarded.
    private var bindGeneration = 0

    private let scopedAccess = SecurityScopedAccess()
    var onChange: (() -> Void)?
    /// Project title printed in the slug line of imposed sheets.
    var documentTitle = ""

    var totalSourcePages: Int {
        sources.reduce(0) { $0 + $1.pageCount }
    }

    var assembledPageCount: Int {
        bookBlockItems.reduce(0) { $0 + $1.pageCount }
    }

    var canBind: Bool {
        assembledPageCount > 0 && !isWorking
    }

    /// Export only what matches the current settings.
    var canExport: Bool {
        previewDocument != nil && !isPreviewStale && !isWorking
    }

    /// Live imposition summary for the sidebar card.
    var impositionSummary: ImpositionSummary? {
        guard let plan else { return nil }
        let trim = job.resolvedTrimSize ?? sources.first?.pageSize ?? CGSize(width: 612, height: 792)
        return plan.impositionSummary(
            sheetSizeLabel: ImpositionService.printerSheetLabel(for: job, pageSize: trim)
        )
    }

    func addPDFs(urls: [URL]) {
        errorMessage = nil
        for url in urls {
            guard url.pathExtension.lowercased() == "pdf" else { continue }
            do {
                let (source, _) = try PDFDocumentService.load(url: url)
                if !sources.contains(where: { $0.url == source.url }) {
                    sources.append(source)
                    bookBlockItems.append(.sourceRange(source: source))
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        refreshPlan()
        onChange?()
    }

    func removeSource(_ source: SourceDocument) {
        sources.removeAll { $0.id == source.id }
        bookBlockItems.removeAll { $0.sourceID == source.id }
        refreshPlan()
        onChange?()
    }

    func moveSource(from offsets: IndexSet, to offset: Int) {
        sources.move(fromOffsets: offsets, toOffset: offset)
        refreshPlan()
        onChange?()
    }

    func moveBookBlockItem(from offsets: IndexSet, to offset: Int) {
        bookBlockItems.move(fromOffsets: offsets, toOffset: offset)
        markChanged()
    }

    func deleteBookBlockItem(at offsets: IndexSet) {
        bookBlockItems.remove(atOffsets: offsets)
        markChanged()
    }

    func addBlankPage() {
        addBlankPages(count: 1)
    }

    func addBlankPages(count: Int) {
        let n = max(0, min(200, count))
        guard n > 0 else { return }
        for index in 0..<n {
            let label = n == 1 ? "Blank page" : "Blank page \(index + 1)"
            bookBlockItems.append(.blank(label: label))
        }
        markChanged()
    }

    func addCoverSlot(_ kind: BookBlockItem.Kind) {
        bookBlockItems.append(.cover(kind))
        markChanged()
    }

    func rotateBookBlockItem(_ item: BookBlockItem) {
        guard let index = bookBlockItems.firstIndex(where: { $0.id == item.id }) else { return }
        bookBlockItems[index].rotationDegrees = (bookBlockItems[index].rotationDegrees + 90) % 360
        markChanged()
    }

    func splitBookBlockItem(_ item: BookBlockItem, afterPageCount: Int) {
        guard let index = bookBlockItems.firstIndex(where: { $0.id == item.id }),
              item.kind == .sourceRange,
              let range = item.pageRange,
              afterPageCount > 0,
              afterPageCount < item.pageCount else { return }

        let firstEnd = range.lowerBound + afterPageCount - 1
        let first = BookBlockItem(
            kind: .sourceRange,
            sourceID: item.sourceID,
            pageRange: range.lowerBound...firstEnd,
            rotationDegrees: item.rotationDegrees,
            label: "\(item.label) p\(range.lowerBound + 1)-\(firstEnd + 1)"
        )
        let second = BookBlockItem(
            kind: .sourceRange,
            sourceID: item.sourceID,
            pageRange: (firstEnd + 1)...range.upperBound,
            rotationDegrees: item.rotationDegrees,
            label: "\(item.label) p\(firstEnd + 2)-\(range.upperBound + 1)"
        )
        bookBlockItems.replaceSubrange(index...index, with: [first, second])
        markChanged()
    }

    func chooseFrontEndpaperArtwork() {
        chooseEndpaperArtwork { [weak self] artwork in
            self?.job.frontEndpaperArtwork = artwork
        }
    }

    func chooseBackEndpaperArtwork() {
        chooseEndpaperArtwork { [weak self] artwork in
            self?.job.backEndpaperArtwork = artwork
        }
    }

    func clearFrontEndpaperArtwork() {
        job.frontEndpaperArtwork = nil
        markChanged()
    }

    func clearBackEndpaperArtwork() {
        job.backEndpaperArtwork = nil
        markChanged()
    }

    private func chooseEndpaperArtwork(completion: @escaping (EndpaperArtwork) -> Void) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf, .png, .jpeg, .heic, .tiff, .gif]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose an image or PDF for endpaper pages"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let isPDF = url.pathExtension.lowercased() == "pdf"
        completion(EndpaperArtwork(url: url, isPDF: isPDF))
        markChanged()
    }

    func markChanged() {
        refreshPlan()
        onChange?()
    }

    func refreshPlan() {
        guard assembledPageCount > 0 else {
            plan = nil
            signatureMap = nil
            cancelAutoBind()
            previewDocument = nil
            return
        }
        let next = ImpositionService.plan(contentPageCount: assembledPageCount, job: job)
        plan = next
        signatureMap = ImpositionService.signatureMap(for: next, job: job)
        scheduleAutoBind()
    }

    /// Every plan refresh means the imposed preview is out of date: bind again after a short pause.
    /// The previous preview stays on screen until the new one lands, so edits don't flicker.
    func scheduleAutoBind(after delay: Duration = BindingWorkspace.autoBindDelay) {
        bindGeneration += 1
        isPreviewStale = true
        autoBindTask?.cancel()
        autoBindTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.runBinding()
        }
    }

    private func cancelAutoBind() {
        autoBindTask?.cancel()
        autoBindTask = nil
        bindGeneration += 1
        isPreviewStale = false
        statusMessage = nil
    }

    /// Merge → endpapers → decorate → impose → ready to export. Runs automatically after edits.
    func runBinding() {
        guard assembledPageCount > 0 else { return }
        // A bind already in flight will notice its generation is stale and run again.
        guard !isWorking else { return }
        let generation = bindGeneration
        isWorking = true
        statusMessage = "Binding…"

        let resolvedURLs = sources.map { $0.resolvedURL() }
        let endpaperURLs = [job.frontEndpaperArtwork, job.backEndpaperArtwork]
            .compactMap { $0?.resolvedURL() }
        let jobSnapshot = job
        let titleSnapshot = documentTitle
        let sourcesSnapshot = sources
        let itemsSnapshot = bookBlockItems
        scopedAccess.start(urls: resolvedURLs + endpaperURLs)

        Task.detached(priority: .userInitiated) { [scopedAccess] in
            defer {
                Task { @MainActor in
                    scopedAccess.stop()
                }
            }

            do {
                let assembled = try PDFDocumentService.assembleContent(
                    items: itemsSnapshot,
                    sources: sourcesSnapshot,
                    targetPageSize: jobSnapshot.resolvedTrimSize,
                    normalizeOrientation: jobSnapshot.normalizeOrientation
                )
                let plan = ImpositionService.plan(
                    contentPageCount: assembled.pageCount,
                    job: jobSnapshot
                )
                let map = ImpositionService.signatureMap(for: plan, job: jobSnapshot)

                let targetSize = jobSnapshot.resolvedTrimSize
                let bookBlock = PDFDocumentService.buildBookBlock(
                    from: assembled,
                    frontEndpapers: jobSnapshot.frontEndpapers,
                    backEndpapers: jobSnapshot.backEndpapers,
                    padPages: plan.padPages,
                    targetPageSize: targetSize,
                    normalizeOrientation: jobSnapshot.normalizeOrientation,
                    frontEndpaperDesign: jobSnapshot.endpapers.front,
                    backEndpaperDesign: jobSnapshot.endpapers.back
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
                    job: jobSnapshot,
                    slugTitle: titleSnapshot
                )

                await MainActor.run {
                    self.isWorking = false
                    // Settings changed while binding: drop this result and bind the latest.
                    guard generation == self.bindGeneration else {
                        self.runBinding()
                        return
                    }
                    self.plan = plan
                    self.signatureMap = map
                    self.previewDocument = imposed
                    self.isPreviewStale = false
                    self.statusMessage =
                        "Ready · \(plan.sheetCount) print sheets · \(plan.summary). \(jobSnapshot.duplexHint)"
                }
            } catch {
                await MainActor.run {
                    self.isWorking = false
                    guard generation == self.bindGeneration else {
                        self.runBinding()
                        return
                    }
                    // Automatic: report in the status bar rather than interrupting with an alert.
                    self.isPreviewStale = false
                    self.previewDocument = nil
                    self.statusMessage = "Couldn't bind — \(error.localizedDescription)"
                }
            }
        }
    }

    func exportBoundPDF() {
        guard canExport, let document = previewDocument else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = suggestedExportName()
        panel.canCreateDirectories = true
        panel.message = job.duplexHint

        guard panel.runModal() == .OK, let url = panel.url else { return }

        if document.write(to: url) {
            statusMessage = "Saved \(url.lastPathComponent) — \(job.duplexHint)"
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

    func restore(_ state: BindingWorkspaceState) {
        sources = state.sources
        job = state.job
        job.normalizeEndpaperLeafCounts()
        bookBlockItems = state.bookBlockItems.isEmpty
            ? state.sources.map(BookBlockItem.sourceRange(source:))
            : state.bookBlockItems
        previewDocument = nil
        statusMessage = nil
        errorMessage = nil
        refreshPlan()
    }

    func snapshot() -> BindingWorkspaceState {
        BindingWorkspaceState(
            sources: sources,
            job: job,
            bookBlockItems: bookBlockItems
        )
    }
}

struct BindingWorkspaceState: Equatable, Codable {
    var sources: [SourceDocument] = []
    var job = BindingJob()
    var bookBlockItems: [BookBlockItem] = []
}

/// View/zoom state shared between the cover canvas and the workbench header.
@MainActor
final class CoverEditorChrome: ObservableObject {
    enum ViewMode: String, CaseIterable, Identifiable {
        case fit
        case oneToOne

        var id: String { rawValue }

        var shortLabel: String {
            switch self {
            case .fit: return "Fit"
            case .oneToOne: return "1:1"
            }
        }
    }

    @Published var viewMode: ViewMode = .fit
    @Published var zoomFactor: Double = 1.0
}
