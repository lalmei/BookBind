import PDFKit
import XCTest
@testable import BookBind

final class PrinterMarksTests: XCTestCase {
    func testMarksStartOutsideTheBleed() {
        XCTAssertEqual(PrinterMarks.markStart(bleed: 9), 12)
        XCTAssertEqual(PrinterMarks.margin(bleed: 9, marks: true), 9 + 3 + 12 + 2)
        XCTAssertEqual(PrinterMarks.margin(bleed: 9, marks: false), 9)
        XCTAssertEqual(PrinterMarks.margin(bleed: -4, marks: false), 0)
    }

    func testMediaGrowsSoMarksNeverOverlapBleed() {
        let page = CGSize(width: 432, height: 648)
        let media = ImpositionService.spreadMediaSize(pageSize: page, bleed: 9, addCropMarks: true)
        let margin = (media.width - page.width * 2) / 2
        XCTAssertGreaterThanOrEqual(margin, 9 + PrinterMarks.offset + PrinterMarks.length)
    }

    func testSlugTextNamesTheSheet() {
        let date = ISO8601DateFormatter().date(from: "2026-10-12T12:00:00Z")!
        let text = PrinterMarks.slugText(
            title: "  Field Notes ",
            parts: ["Sig 2 of 8", "Sheet 3 Back", PrinterMarks.pageRange([20, 27]), ""],
            date: date
        )
        XCTAssertEqual(text, "Field Notes · Sig 2 of 8 · Sheet 3 Back · pp 21–28 · 2026-10-12")
        XCTAssertEqual(PrinterMarks.pageRange([nil, 4]), "p 5")
        XCTAssertEqual(PrinterMarks.pageRange([nil, nil]), "")
    }

    func testImposedSheetsCarryTheSlugLine() throws {
        var job = BindingJob()
        job.addCropMarks = true
        job.bleedPoints = 9
        let plan = ImpositionService.plan(contentPageCount: 8, job: job)
        let block = try XCTUnwrap(Self.blankDocument(pages: plan.totalBookPages, size: CGSize(width: 300, height: 400)))
        let imposed = try ImpositionService.impose(bookBlock: block, plan: plan, job: job, slugTitle: "Field Notes")
        let text = try XCTUnwrap(imposed.page(at: 0)?.string)
        XCTAssertTrue(text.contains("Field Notes"), text)
        XCTAssertTrue(text.contains("Front"), text)
    }

    private static func blankDocument(pages: Int, size: CGSize) -> PDFDocument? {
        let data = NSMutableData()
        var box = CGRect(origin: .zero, size: size)
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &box, nil) else { return nil }
        for _ in 0..<pages {
            context.beginPage(mediaBox: &box)
            context.endPage()
        }
        context.closePDF()
        return PDFDocument(data: data as Data)
    }
}
