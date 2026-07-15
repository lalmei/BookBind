import AppKit
import PDFKit
import XCTest
@testable import BookBind

final class PDFRenderTests: XCTestCase {
    func testDecoratedPageIsNotBlank() throws {
        let source = try makeSamplePDF(text: "Hello BookBind")
        guard let page = source.page(at: 0) else {
            return XCTFail("missing page")
        }

        var numbers = PageNumberOptions()
        numbers.enabled = true
        numbers.skipEndpapers = false

        let decorated = PageDecorationService.decorate(
            source,
            pageNumbers: numbers,
            watermark: WatermarkOptions(enabled: false),
            frontEndpapers: 0,
            backEndpapers: 0
        )
        guard let out = decorated.page(at: 0) else {
            return XCTFail("missing decorated page")
        }

        XCTAssertGreaterThan(nonWhitePixelRatio(of: page), 0.001, "source should have ink")
        XCTAssertGreaterThan(nonWhitePixelRatio(of: out), 0.001, "decorated page should keep content")
    }

    func testImposedSpreadIsNotBlank() throws {
        let source = try makeSamplePDF(text: "Page Content", pageCount: 4)
        XCTAssertGreaterThan(nonWhitePixelRatio(of: source.page(at: 0)!), 0.001)

        var job = BindingJob()
        job.bindingStyle = .saddleStitch
        job.frontEndpapers = 0
        job.backEndpapers = 0
        job.pageNumbers.enabled = false
        job.showGuideMarks = true
        job.addCropMarks = false
        job.creepPoints = 0
        job.bleedPoints = 0

        let plan = ImpositionService.plan(contentPageCount: source.pageCount, job: job)
        let block = PDFDocumentService.buildBookBlock(
            from: source,
            frontEndpapers: 0,
            backEndpapers: 0,
            padPages: plan.padPages,
            targetPageSize: nil,
            normalizeOrientation: false
        )
        XCTAssertGreaterThan(nonWhitePixelRatio(of: block.page(at: 0)!), 0.001, "book block should keep content")

        let imposed = try ImpositionService.impose(
            bookBlock: block,
            plan: plan,
            style: job.bindingStyle,
            addCropMarks: false,
            showGuideMarks: true,
            creepPoints: 0,
            bleedPoints: 0
        )
        XCTAssertGreaterThan(imposed.pageCount, 0)
        guard let spread = imposed.page(at: 0) else {
            return XCTFail("missing spread")
        }
        XCTAssertGreaterThan(nonWhitePixelRatio(of: spread), 0.001, "imposed spread should show page content")
    }

    func testDecorativeImageEndpapersAreNotBlank() throws {
        let source = try makeSamplePDF(text: "Body", pageCount: 2)
        let imageURL = try writeTestPNG()
        defer { try? FileManager.default.removeItem(at: imageURL) }

        let artwork = EndpaperArtwork(url: imageURL, isPDF: false)
        let block = PDFDocumentService.buildBookBlock(
            from: source,
            frontEndpapers: 2,
            backEndpapers: 1,
            padPages: 0,
            targetPageSize: CGSize(width: 400, height: 600),
            normalizeOrientation: false,
            frontEndpaperArtwork: artwork,
            backEndpaperArtwork: artwork
        )

        XCTAssertEqual(block.pageCount, 5)
        // Front endpapers (0,1) and back endpaper (4) should carry artwork ink.
        for index in [0, 1, 4] {
            guard let page = block.page(at: index) else {
                return XCTFail("missing endpaper \(index)")
            }
            XCTAssertGreaterThan(
                nonWhitePixelRatio(of: page),
                0.01,
                "decorative endpaper \(index) should not be blank"
            )
        }
    }

    func testVectorDrawKeepsContentWhenPageRefExists() throws {
        let source = try makeSamplePDF(text: "Vector Source")
        guard let page = source.page(at: 0) else {
            return XCTFail("missing page")
        }
        XCTAssertNotNil(page.pageRef, "sample pages from CGPDFContext should expose pageRef")

        let destSize = CGSize(width: 400, height: 600)
        let data = PDFDocumentService.fitPageData(page, to: destSize)
        guard let fittedDoc = PDFDocument(data: data),
              let fitted = fittedDoc.page(at: 0) else {
            return XCTFail("fit failed")
        }
        // Keep fittedDoc alive while sampling pixels.
        XCTAssertGreaterThan(nonWhitePixelRatio(of: fitted), 0.001)
        _ = fittedDoc
    }

    // MARK: - Helpers

    private func writeTestPNG() throws -> URL {
        let size = NSSize(width: 64, height: 64)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.systemRed.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
        image.unlockFocus()

        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            throw BindingError.exportFailed
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("bookbind-endpaper-\(UUID().uuidString).png")
        try png.write(to: url)
        return url
    }

    private func makeSamplePDF(text: String, pageCount: Int = 1) throws -> PDFDocument {
        let size = CGSize(width: 400, height: 600)
        let output = PDFDocument()
        for index in 0..<pageCount {
            let data = renderTextPage(text: "\(text) \(index + 1)", size: size)
            guard let doc = PDFDocument(data: data), let page = doc.page(at: 0) else {
                throw BindingError.exportFailed
            }
            output.insert(page, at: index)
        }
        return output
    }

    private func renderTextPage(text: String, size: CGSize) -> Data {
        let mutable = NSMutableData()
        var mediaBox = CGRect(origin: .zero, size: size)
        guard let consumer = CGDataConsumer(data: mutable as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            return Data()
        }
        context.beginPage(mediaBox: &mediaBox)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(mediaBox)
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(x: 40, y: 200, width: 320, height: 80))
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 28),
            .foregroundColor: NSColor.white
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attrs))
        context.textPosition = CGPoint(x: 50, y: 230)
        CTLineDraw(line, context)
        context.endPage()
        context.closePDF()
        return mutable as Data
    }

    /// Fraction of pixels that are not near-white (detects blank pages).
    private func nonWhitePixelRatio(of page: PDFPage) -> CGFloat {
        let image = page.thumbnail(of: CGSize(width: 120, height: 160), for: .mediaBox)
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return 0
        }
        let width = cgImage.width
        let height = cgImage.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var data = [UInt8](repeating: 0, count: height * bytesPerRow)
        guard let ctx = CGContext(
            data: &data,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return 0
        }
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var ink = 0
        let total = width * height
        for i in stride(from: 0, to: data.count, by: 4) {
            let r = data[i], g = data[i + 1], b = data[i + 2]
            if r < 250 || g < 250 || b < 250 {
                ink += 1
            }
        }
        return CGFloat(ink) / CGFloat(max(total, 1))
    }
}
