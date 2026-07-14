import AppKit
import Foundation
import PDFKit

/// Source PDF opened for a binding job.
struct SourceDocument: Identifiable, Equatable {
    let id: UUID
    var url: URL
    var name: String
    var pageCount: Int
    var bookmarkData: Data?

    init(url: URL, document: PDFDocument) {
        self.id = UUID()
        self.url = url
        self.name = url.lastPathComponent
        self.pageCount = document.pageCount
        self.bookmarkData = try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    static func == (lhs: SourceDocument, rhs: SourceDocument) -> Bool {
        lhs.id == rhs.id
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
    static func merge(urls: [URL]) throws -> PDFDocument {
        guard !urls.isEmpty else { throw BindingError.noDocuments }

        let output = PDFDocument()
        var insertIndex = 0

        for url in urls {
            let accessing = url.startAccessingSecurityScopedResource()
            defer {
                if accessing { url.stopAccessingSecurityScopedResource() }
            }

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

    static func pageSize(of document: PDFDocument) -> CGSize {
        document.page(at: 0)?.bounds(for: .mediaBox).size
            ?? CGSize(width: 612, height: 792)
    }

    static func makeBlankPage(size: CGSize) -> PDFPage {
        let bounds = CGRect(origin: .zero, size: size)
        let data = renderBlankPDF(bounds: bounds)
        if let doc = PDFDocument(data: data), let page = doc.page(at: 0) {
            return page
        }
        let page = PDFPage()
        page.setBounds(bounds, for: .mediaBox)
        return page
    }

    /// Build the linear book block: front endpapers + content + back endpapers + pad blanks.
    static func buildBookBlock(
        from content: PDFDocument,
        frontEndpapers: Int,
        backEndpapers: Int,
        padPages: Int,
        targetPageSize: CGSize?
    ) -> PDFDocument {
        let size = targetPageSize ?? pageSize(of: content)
        let output = PDFDocument()
        var index = 0

        for _ in 0..<max(0, frontEndpapers) {
            output.insert(makeBlankPage(size: size), at: index)
            index += 1
        }

        for pageIndex in 0..<content.pageCount {
            guard let page = content.page(at: pageIndex),
                  let copy = copyPage(page) else { continue }
            output.insert(copy, at: index)
            index += 1
        }

        for _ in 0..<max(0, backEndpapers) {
            output.insert(makeBlankPage(size: size), at: index)
            index += 1
        }

        for _ in 0..<max(0, padPages) {
            output.insert(makeBlankPage(size: size), at: index)
            index += 1
        }

        return output
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
        let mutableData = NSMutableData()
        var mediaBox = bounds
        guard let consumer = CGDataConsumer(data: mutableData as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            return Data()
        }
        context.beginPage(mediaBox: &mediaBox)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(bounds)
        context.endPage()
        context.closePDF()
        return mutableData as Data
    }
}
