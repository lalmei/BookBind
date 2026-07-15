import AppKit
import Foundation
import PDFKit

/// Source PDF opened for a binding job.
struct SourceDocument: Identifiable, Equatable, Codable {
    let id: UUID
    var url: URL
    var name: String
    var pageCount: Int
    /// First-page display size (rotation-aware), used for plan sheet-size labels.
    var pageSize: CGSize
    var bookmarkData: Data?

    init(url: URL, document: PDFDocument) {
        self.id = UUID()
        self.url = url
        self.name = url.lastPathComponent
        self.pageCount = document.pageCount
        self.pageSize = PDFDocumentService.pageSize(of: document)
        self.bookmarkData = try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    init(
        id: UUID = UUID(),
        url: URL,
        name: String,
        pageCount: Int,
        pageSize: CGSize,
        bookmarkData: Data?
    ) {
        self.id = id
        self.url = url
        self.name = name
        self.pageCount = pageCount
        self.pageSize = pageSize
        self.bookmarkData = bookmarkData
    }

    /// Resolve a usable file URL, preferring a security-scoped bookmark when present.
    func resolvedURL() -> URL {
        guard let bookmarkData else { return url }
        var isStale = false
        guard let resolved = try? URL(
            resolvingBookmarkData: bookmarkData,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            return url
        }
        return resolved
    }

    static func == (lhs: SourceDocument, rhs: SourceDocument) -> Bool {
        lhs.id == rhs.id
    }
}

/// Holds security-scoped resource access for a set of URLs until stopped.
final class SecurityScopedAccess {
    private var accessed: [URL] = []

    func start(urls: [URL]) {
        stop()
        for url in urls {
            if url.startAccessingSecurityScopedResource() {
                accessed.append(url)
            }
        }
    }

    func stop() {
        accessed.forEach { $0.stopAccessingSecurityScopedResource() }
        accessed.removeAll()
    }

    deinit {
        stop()
    }
}

enum PDFDocumentService {
    static func load(url: URL) throws -> (SourceDocument, PDFDocument) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing { url.stopAccessingSecurityScopedResource() }
        }

        guard let document = PDFDocument(url: url) else {
            throw BindingError.emptyDocument
        }
        guard document.pageCount > 0 else {
            throw BindingError.emptyDocument
        }
        return (SourceDocument(url: url, document: document), document)
    }

    /// Merge documents in order into a single PDFDocument.
    /// Caller must hold security-scoped access for the duration if sandboxed.
    static func merge(urls: [URL]) throws -> PDFDocument {
        guard !urls.isEmpty else { throw BindingError.noDocuments }

        let output = PDFDocument()
        var insertIndex = 0

        for url in urls {
            guard let doc = PDFDocument(url: url) else { continue }
            for pageIndex in 0..<doc.pageCount {
                guard let page = doc.page(at: pageIndex),
                      let copy = copyPage(page) else { continue }
                output.insert(copy, at: insertIndex)
                insertIndex += 1
            }
        }

        guard output.pageCount > 0 else { throw BindingError.emptyDocument }
        return output
    }

    /// Rebuild the user-arranged book block content before endpapers,
    /// decoration, padding, and imposition are applied.
    static func assembleContent(
        items: [BookBlockItem],
        sources: [SourceDocument],
        targetPageSize: CGSize?,
        normalizeOrientation: Bool
    ) throws -> PDFDocument {
        guard !items.isEmpty else { throw BindingError.noDocuments }

        let sourceLookup = Dictionary(uniqueKeysWithValues: sources.map { ($0.id, $0) })
        let output = PDFDocument()
        let fallbackSize = targetPageSize ?? sources.first?.pageSize ?? CGSize(width: 612, height: 792)

        for item in items {
            switch item.kind {
            case .blank, .frontCover, .backCover:
                appendBlankPage(to: output, size: fallbackSize)

            case .sourceRange:
                guard let sourceID = item.sourceID,
                      let source = sourceLookup[sourceID],
                      let range = item.pageRange else { continue }
                let url = source.resolvedURL()
                let accessing = url.startAccessingSecurityScopedResource()
                defer {
                    if accessing { url.stopAccessingSecurityScopedResource() }
                }
                guard let document = PDFDocument(url: url) else { continue }
                let sourceSize = targetPageSize ?? source.pageSize
                let wantPortrait = sourceSize.height >= sourceSize.width
                let lower = max(0, range.lowerBound)
                let upper = min(document.pageCount - 1, range.upperBound)
                guard lower <= upper else { continue }

                for index in lower...upper {
                    guard var page = document.page(at: index) else { continue }
                    if item.rotationDegrees != 0 {
                        page = renderPage(
                            page,
                            into: displaySize(of: page),
                            additionalRotationDegrees: item.rotationDegrees
                        ) ?? page
                    }
                    let pageToPlace = normalizeOrientation
                        ? orientedPage(page, portrait: wantPortrait)
                        : page
                    appendPDFData(fitPageData(pageToPlace, to: sourceSize), to: output)
                }
            }
        }

        guard output.pageCount > 0 else { throw BindingError.emptyDocument }
        return output
    }

    static func pageSize(of document: PDFDocument) -> CGSize {
        guard let page = document.page(at: 0) else {
            return CGSize(width: 612, height: 792)
        }
        return displaySize(of: page)
    }

    /// Visible size after applying the page’s rotation metadata.
    static func displaySize(of page: PDFPage) -> CGSize {
        let box = page.bounds(for: .mediaBox)
        let rotation = normalizedRotation(page.rotation)
        if rotation == 90 || rotation == 270 {
            return CGSize(width: box.height, height: box.width)
        }
        return box.size
    }

    static func isPortrait(_ page: PDFPage) -> Bool {
        let size = displaySize(of: page)
        return size.height >= size.width
    }

    /// True when a majority of pages are portrait (ties → portrait).
    static func majorityIsPortrait(_ document: PDFDocument) -> Bool {
        var portrait = 0
        var landscape = 0
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            if isPortrait(page) {
                portrait += 1
            } else {
                landscape += 1
            }
        }
        return portrait >= landscape
    }

    /// Bake rotation metadata into an upright page (rotation 0).
    static func flattenPage(_ page: PDFPage) -> PDFPage {
        let size = displaySize(of: page)
        return renderPage(page, into: size, additionalRotationDegrees: 0)
            ?? copyPage(page)
            ?? makeBlankPage(size: size)
    }

    /// Rotate a page so it matches the target orientation, then flatten.
    static func orientedPage(_ page: PDFPage, portrait: Bool) -> PDFPage {
        let flat = flattenPage(page)
        if isPortrait(flat) == portrait {
            return flat
        }
        // Rotate 90° clockwise so landscape ↔ portrait.
        let size = displaySize(of: flat)
        let swapped = CGSize(width: size.height, height: size.width)
        return renderPage(flat, into: swapped, additionalRotationDegrees: 90)
            ?? flat
    }

    /// Canonical trim size when keeping source dimensions but normalizing orientation.
    static func canonicalSize(for document: PDFDocument, portrait: Bool) -> CGSize {
        var maxShort: CGFloat = 0
        var maxLong: CGFloat = 0
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            let size = displaySize(of: page)
            maxShort = max(maxShort, min(size.width, size.height))
            maxLong = max(maxLong, max(size.width, size.height))
        }
        if maxShort == 0 || maxLong == 0 {
            return CGSize(width: 612, height: 792)
        }
        return portrait
            ? CGSize(width: maxShort, height: maxLong)
            : CGSize(width: maxLong, height: maxShort)
    }

    static func makeBlankPage(size: CGSize) -> PDFPage {
        let bounds = CGRect(origin: .zero, size: size)
        let data = renderBlankPDF(bounds: bounds)
        // Keep the backing document alive by transferring into a carrier that the
        // caller must insert into their output while this page is retained…
        // Prefer `appendPDFData` / `appendBlankPage` when building documents.
        if let doc = PDFDocument(data: data), let page = doc.page(at: 0),
           let copy = page.copy() as? PDFPage {
            return copy
        }
        let page = PDFPage()
        page.setBounds(bounds, for: .mediaBox)
        return page
    }

    /// Insert the first page of a PDF data blob into `document` while the temp doc is alive.
    @discardableResult
    static func appendPDFData(_ data: Data, to document: PDFDocument) -> Bool {
        guard !data.isEmpty,
              let doc = PDFDocument(data: data),
              let page = doc.page(at: 0) else {
            return false
        }
        document.insert(page, at: document.pageCount)
        return true
    }

    @discardableResult
    static func appendBlankPage(to document: PDFDocument, size: CGSize) -> Bool {
        let bounds = CGRect(origin: .zero, size: size)
        return appendPDFData(renderBlankPDF(bounds: bounds), to: document)
    }

    /// Aspect-fit `page` into `targetSize`, centered on a white page. Returns PDF data.
    static func fitPageData(_ page: PDFPage, to targetSize: CGSize) -> Data {
        // Keep the live page when already upright so `pageRef` stays valid for vector draw.
        // Flattening into an orphaned PDFPage loses the backing document and forces raster.
        let upright = normalizedRotation(page.rotation) == 0 ? page : flattenPage(page)
        let sourceSize = displaySize(of: upright)
        guard sourceSize.width > 0, sourceSize.height > 0 else {
            return renderBlankPDF(bounds: CGRect(origin: .zero, size: targetSize))
        }

        let scale = min(targetSize.width / sourceSize.width, targetSize.height / sourceSize.height)
        let drawSize = CGSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
        let origin = CGPoint(
            x: (targetSize.width - drawSize.width) / 2,
            y: (targetSize.height - drawSize.height) / 2
        )

        let bounds = CGRect(origin: .zero, size: targetSize)
        let mutableData = NSMutableData()
        var mediaBox = bounds
        guard let consumer = CGDataConsumer(data: mutableData as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            return renderBlankPDF(bounds: bounds)
        }

        context.beginPage(mediaBox: &mediaBox)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(bounds)
        context.saveGState()
        context.translateBy(x: origin.x, y: origin.y)
        PDFPageDrawing.draw(
            upright,
            in: context,
            dest: CGRect(origin: .zero, size: drawSize)
        )
        context.restoreGState()
        context.endPage()
        context.closePDF()
        return mutableData as Data
    }

    /// Aspect-fit `page` into `targetSize`, centered on a white page.
    static func fitPage(_ page: PDFPage, to targetSize: CGSize) -> PDFPage {
        let data = fitPageData(page, to: targetSize)
        if let doc = PDFDocument(data: data), let fitted = doc.page(at: 0),
           let copy = fitted.copy() as? PDFPage {
            return copy
        }
        return makeBlankPage(size: targetSize)
    }

    /// Build the linear book block: front endpapers + content + back endpapers + pad blanks.
    /// When `targetPageSize` is set, every page (including content) is fitted to that size.
    /// When `normalizeOrientation` is set, mixed landscape/portrait pages are rotated to match.
    /// Endpaper priority: marbled → artwork → solid color → blank.
    static func buildBookBlock(
        from content: PDFDocument,
        frontEndpapers: Int,
        backEndpapers: Int,
        padPages: Int,
        targetPageSize: CGSize?,
        normalizeOrientation: Bool = true,
        frontEndpaperArtwork: EndpaperArtwork? = nil,
        backEndpaperArtwork: EndpaperArtwork? = nil,
        frontEndpaperColor: EndpaperColor = .none,
        backEndpaperColor: EndpaperColor = .none,
        frontEndpaperDesign: EndpaperFaceDesign? = nil,
        backEndpaperDesign: EndpaperFaceDesign? = nil
    ) -> PDFDocument {
        let wantPortrait: Bool = {
            if let targetPageSize {
                return targetPageSize.height >= targetPageSize.width
            }
            return majorityIsPortrait(content)
        }()

        let size: CGSize = {
            if let targetPageSize { return targetPageSize }
            if normalizeOrientation {
                return canonicalSize(for: content, portrait: wantPortrait)
            }
            return pageSize(of: content)
        }()

        let output = PDFDocument()

        let frontFace = frontEndpaperDesign ?? EndpaperFaceDesign(
            mode: frontEndpaperArtwork != nil ? .artwork : (frontEndpaperColor == .none ? .blank : .solidColor),
            solidColor: frontEndpaperColor,
            artwork: frontEndpaperArtwork
        )
        let backFace = backEndpaperDesign ?? EndpaperFaceDesign(
            mode: backEndpaperArtwork != nil ? .artwork : (backEndpaperColor == .none ? .blank : .solidColor),
            solidColor: backEndpaperColor,
            artwork: backEndpaperArtwork
        )

        appendEndpaperPages(to: output, count: max(0, frontEndpapers), size: size, face: frontFace)

        for pageIndex in 0..<content.pageCount {
            guard let page = content.page(at: pageIndex) else { continue }
            // Always re-encode via fitPageData — PDFPage.copy() often yields blank
            // pages once the source document is released.
            let pageToPlace: PDFPage = normalizeOrientation
                ? orientedPage(page, portrait: wantPortrait)
                : page
            appendPDFData(fitPageData(pageToPlace, to: size), to: output)
        }

        appendEndpaperPages(to: output, count: max(0, backEndpapers), size: size, face: backFace)

        for _ in 0..<max(0, padPages) {
            appendBlankPage(to: output, size: size)
        }

        return output
    }

    /// Append blank or decorative endpaper pages.
    static func appendEndpaperPages(
        to document: PDFDocument,
        count: Int,
        size: CGSize,
        face: EndpaperFaceDesign
    ) {
        guard count > 0 else { return }

        switch face.mode {
        case .marbled:
            if let spec = face.marbling,
               let image = MarbledPaperGenerator.nsImage(spec: spec, sizePoints: size, dpi: 300) {
                let data = fitImageData(image, to: size)
                for _ in 0..<count {
                    appendPDFData(data, to: document)
                }
                return
            }
            // Fall through if marbling failed to render.
            fallthrough
        case .blank:
            for _ in 0..<count {
                appendBlankPage(to: document, size: size)
            }
            return
        case .solidColor:
            for _ in 0..<count {
                if face.solidColor == .none {
                    appendBlankPage(to: document, size: size)
                } else {
                    appendPDFData(
                        renderColorPDF(bounds: CGRect(origin: .zero, size: size), color: face.solidColor.cgColor),
                        to: document
                    )
                }
            }
            return
        case .artwork:
            break
        }

        guard let artwork = face.artwork else {
            for _ in 0..<count {
                if face.solidColor == .none {
                    appendBlankPage(to: document, size: size)
                } else {
                    appendPDFData(
                        renderColorPDF(bounds: CGRect(origin: .zero, size: size), color: face.solidColor.cgColor),
                        to: document
                    )
                }
            }
            return
        }

        let url = artwork.resolvedURL()
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing { url.stopAccessingSecurityScopedResource() }
        }

        if artwork.isPDF {
            guard let pdf = PDFDocument(url: url), pdf.pageCount > 0 else {
                for _ in 0..<count {
                    appendBlankPage(to: document, size: size)
                }
                return
            }
            for index in 0..<count {
                guard let page = pdf.page(at: index % pdf.pageCount) else {
                    appendBlankPage(to: document, size: size)
                    continue
                }
                appendPDFData(fitPageData(page, to: size), to: document)
            }
            return
        }

        guard let image = NSImage(contentsOf: url) else {
            for _ in 0..<count {
                appendBlankPage(to: document, size: size)
            }
            return
        }
        let data = fitImageData(image, to: size)
        for _ in 0..<count {
            appendPDFData(data, to: document)
        }
    }

    /// Aspect-fill `image` into `targetSize`, centered and clipped.
    static func fitImageData(_ image: NSImage, to targetSize: CGSize) -> Data {
        let bounds = CGRect(origin: .zero, size: targetSize)
        let mutableData = NSMutableData()
        var mediaBox = bounds
        guard let consumer = CGDataConsumer(data: mutableData as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            return renderBlankPDF(bounds: bounds)
        }

        context.beginPage(mediaBox: &mediaBox)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(bounds)

        var proposed = NSRect(origin: .zero, size: image.size)
        if let cgImage = image.cgImage(forProposedRect: &proposed, context: nil, hints: nil) {
            let iw = CGFloat(cgImage.width)
            let ih = CGFloat(cgImage.height)
            if iw > 0, ih > 0 {
                let scale = max(targetSize.width / iw, targetSize.height / ih)
                let drawSize = CGSize(width: iw * scale, height: ih * scale)
                let origin = CGPoint(
                    x: (targetSize.width - drawSize.width) / 2,
                    y: (targetSize.height - drawSize.height) / 2
                )
                context.saveGState()
                context.clip(to: bounds)
                context.interpolationQuality = .high
                context.draw(cgImage, in: CGRect(origin: origin, size: drawSize))
                context.restoreGState()
            }
        }

        context.endPage()
        context.closePDF()
        return mutableData as Data
    }

    private static func normalizedRotation(_ degrees: Int) -> Int {
        var value = degrees % 360
        if value < 0 { value += 360 }
        return value
    }

    /// Draw `page` into a new PDF page of `targetSize`, optionally rotating an extra 90/180/270°.
    private static func renderPage(
        _ page: PDFPage,
        into targetSize: CGSize,
        additionalRotationDegrees: Int
    ) -> PDFPage? {
        let bounds = CGRect(origin: .zero, size: targetSize)
        let mutableData = NSMutableData()
        var mediaBox = bounds
        guard let consumer = CGDataConsumer(data: mutableData as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            return nil
        }

        context.beginPage(mediaBox: &mediaBox)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(bounds)

        context.saveGState()
        let extra = normalizedRotation(additionalRotationDegrees)
        switch extra {
        case 90:
            context.translateBy(x: targetSize.width, y: 0)
            context.rotate(by: .pi / 2)
        case 180:
            context.translateBy(x: targetSize.width, y: targetSize.height)
            context.rotate(by: .pi)
        case 270:
            context.translateBy(x: 0, y: targetSize.height)
            context.rotate(by: -.pi / 2)
        default:
            break
        }

        // After an extra 90/270 turn, the upright page fills the swapped axes.
        let drawSize = (extra == 90 || extra == 270)
            ? CGSize(width: targetSize.height, height: targetSize.width)
            : targetSize
        PDFPageDrawing.draw(
            page,
            in: context,
            dest: CGRect(origin: .zero, size: drawSize)
        )
        context.restoreGState()
        context.endPage()
        context.closePDF()

        guard let doc = PDFDocument(data: mutableData as Data),
              let rendered = doc.page(at: 0) else {
            return nil
        }
        return rendered
    }

    static func thumbnail(for page: PDFPage, size: CGSize = CGSize(width: 120, height: 160)) -> NSImage {
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 0, bounds.height > 0 else {
            return NSImage(size: size)
        }

        let scale = min(size.width / bounds.width, size.height / bounds.height)
        let drawSize = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        let image = NSImage(size: drawSize)
        image.lockFocus()
        if let context = NSGraphicsContext.current?.cgContext {
            context.saveGState()
            context.scaleBy(x: scale, y: scale)
            page.draw(with: .mediaBox, to: context)
            context.restoreGState()
        }
        image.unlockFocus()
        return image
    }

    /// Deep-copy a page. Never insert the original into another document —
    /// PDFKit moves pages between documents.
    static func copyPage(_ page: PDFPage) -> PDFPage? {
        guard let copy = page.copy() as? PDFPage else { return nil }
        return copy
    }

    private static func renderBlankPDF(bounds: CGRect) -> Data {
        renderColorPDF(bounds: bounds, color: CGColor(gray: 1, alpha: 1))
    }

    private static func renderColorPDF(bounds: CGRect, color: CGColor) -> Data {
        let mutableData = NSMutableData()
        var mediaBox = bounds
        guard let consumer = CGDataConsumer(data: mutableData as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            return Data()
        }
        context.beginPage(mediaBox: &mediaBox)
        context.setFillColor(color)
        context.fill(bounds)
        context.endPage()
        context.closePDF()
        return mutableData as Data
    }
}
