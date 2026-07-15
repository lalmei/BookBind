import PDFKit
import XCTest
@testable import BookBind

final class ImpositionTests: XCTestCase {
    func testFolioFourPageSignature() {
        let sides = ImpositionService.folioSheetSides(pageCount: 4)
        // Sheet 0 front: pages 4 | 1  (0-based: 3 | 0)
        // Sheet 0 back:  pages 2 | 3  (0-based: 1 | 2)
        XCTAssertEqual(sides.count, 2)
        XCTAssertEqual(sides[0].left, 3)
        XCTAssertEqual(sides[0].right, 0)
        XCTAssertEqual(sides[1].left, 1)
        XCTAssertEqual(sides[1].right, 2)
    }

    func testFolioSixteenPageOuterSheet() {
        let sides = ImpositionService.folioSheetSides(pageCount: 16)
        // First front: 16 | 1 → 15 | 0
        XCTAssertEqual(sides[0].left, 15)
        XCTAssertEqual(sides[0].right, 0)
        // First back: 2 | 15 → 1 | 14
        XCTAssertEqual(sides[1].left, 1)
        XCTAssertEqual(sides[1].right, 14)
    }

    func testSignatureMapUsesOneBasedPages() {
        var job = BindingJob()
        job.bindingStyle = .sectionSewn
        job.signatureSize = .quarto
        job.frontEndpapers = 0
        job.backEndpapers = 0

        let plan = ImpositionService.plan(contentPageCount: 4, job: job)
        let map = ImpositionService.signatureMap(for: plan)
        XCTAssertEqual(map.sides.count, 2)
        XCTAssertEqual(map.sides[0].leftPage, 4)
        XCTAssertEqual(map.sides[0].rightPage, 1)
        XCTAssertEqual(map.sides[1].leftPage, 2)
        XCTAssertEqual(map.sides[1].rightPage, 3)
    }

    func testSectionSewnPlanPadsToSignatureSize() {
        var job = BindingJob()
        job.bindingStyle = .sectionSewn
        job.signatureSize = .sextodecimo
        job.frontEndpapers = 2
        job.backEndpapers = 2

        // 10 content + 4 endpapers = 14 → pad to 16
        let plan = ImpositionService.plan(contentPageCount: 10, job: job)
        XCTAssertEqual(plan.padPages, 2)
        XCTAssertEqual(plan.signatureCount, 1)
        XCTAssertEqual(plan.totalBookPages, 16)
    }

    func testSaddleStitchPadsToMultipleOfFour() {
        var job = BindingJob()
        job.bindingStyle = .saddleStitch
        job.frontEndpapers = 0
        job.backEndpapers = 0

        let plan = ImpositionService.plan(contentPageCount: 5, job: job)
        XCTAssertEqual(plan.padPages, 3)
        XCTAssertEqual(plan.signatureCount, 1)
        XCTAssertEqual(plan.pagesPerSignature, 8)
    }

    func testCreepOffsetScalesWithNestDepth() {
        XCTAssertEqual(ImpositionService.creepOffset(sheetIndex: 0, sheetCount: 4, totalCreep: 12), 0)
        XCTAssertEqual(ImpositionService.creepOffset(sheetIndex: 1, sheetCount: 4, totalCreep: 12), 4)
        XCTAssertEqual(ImpositionService.creepOffset(sheetIndex: 2, sheetCount: 4, totalCreep: 12), 8)
        XCTAssertEqual(ImpositionService.creepOffset(sheetIndex: 3, sheetCount: 4, totalCreep: 12), 12)
        XCTAssertEqual(ImpositionService.creepOffset(sheetIndex: 1, sheetCount: 1, totalCreep: 12), 0)
        XCTAssertEqual(ImpositionService.creepOffset(sheetIndex: 2, sheetCount: 4, totalCreep: 0), 0)
    }

    func testStitchHoleCentersUseHeadAndFootInsets() {
        let trimOrigin = CGPoint(x: 14, y: 14)
        let pageSize = CGSize(width: 100, height: 200)
        let spineX = trimOrigin.x + pageSize.width

        let centers = ImpositionService.stitchHoleCenters(
            spineX: spineX,
            trimOrigin: trimOrigin,
            pageSize: pageSize
        )

        XCTAssertEqual(centers.count, 2)
        XCTAssertEqual(centers[0].x, spineX, accuracy: 0.001)
        XCTAssertEqual(centers[1].x, spineX, accuracy: 0.001)
        XCTAssertEqual(centers[0].y, trimOrigin.y + pageSize.height - 36, accuracy: 0.001)
        XCTAssertEqual(centers[1].y, trimOrigin.y + 36, accuracy: 0.001)
    }

    func testStitchHoleCentersFallbackToCenterOnShortPages() {
        let trimOrigin = CGPoint(x: 0, y: 0)
        let pageSize = CGSize(width: 100, height: 40)
        let spineX: CGFloat = 100

        let centers = ImpositionService.stitchHoleCenters(
            spineX: spineX,
            trimOrigin: trimOrigin,
            pageSize: pageSize
        )

        XCTAssertEqual(centers.count, 1)
        XCTAssertEqual(centers[0], CGPoint(x: spineX, y: 20))
    }

    func testSpreadMediaIncludesBleedAndCropRoom() {
        let page = CGSize(width: 100, height: 200)

        let flush = ImpositionService.spreadMediaSize(pageSize: page, bleed: 0, addCropMarks: false)
        XCTAssertEqual(flush.width, 200)
        XCTAssertEqual(flush.height, 200)

        let bled = ImpositionService.spreadMediaSize(pageSize: page, bleed: 9, addCropMarks: false)
        XCTAssertEqual(bled.width, 218)
        XCTAssertEqual(bled.height, 218)

        let marked = ImpositionService.spreadMediaSize(pageSize: page, bleed: 0, addCropMarks: true)
        XCTAssertEqual(marked.width, 228)
        XCTAssertEqual(marked.height, 228)
    }

    func testCustomTrimSizeResolvesFromJob() {
        var job = BindingJob()
        job.paperSize = .custom
        job.customPageWidth = 5.5 * 72
        job.customPageHeight = 8.5 * 72

        let size = job.resolvedTrimSize
        XCTAssertEqual(size?.width, 396)
        XCTAssertEqual(size?.height, 612)
    }

    func testOrientationHelpersDetectPortraitAndLandscape() {
        let portrait = PDFDocumentService.makeBlankPage(size: CGSize(width: 400, height: 600))
        let landscape = PDFDocumentService.makeBlankPage(size: CGSize(width: 600, height: 400))

        XCTAssertTrue(PDFDocumentService.isPortrait(portrait))
        XCTAssertFalse(PDFDocumentService.isPortrait(landscape))

        let oriented = PDFDocumentService.orientedPage(landscape, portrait: true)
        XCTAssertTrue(PDFDocumentService.isPortrait(oriented))
        let bounds = oriented.bounds(for: .mediaBox)
        XCTAssertEqual(bounds.width, 400, accuracy: 0.5)
        XCTAssertEqual(bounds.height, 600, accuracy: 0.5)
    }

    func testBuildBookBlockNormalizesMixedOrientation() {
        let mixed = PDFDocument()
        mixed.insert(PDFDocumentService.makeBlankPage(size: CGSize(width: 400, height: 600)), at: 0)
        mixed.insert(PDFDocumentService.makeBlankPage(size: CGSize(width: 600, height: 400)), at: 1)

        let block = PDFDocumentService.buildBookBlock(
            from: mixed,
            frontEndpapers: 0,
            backEndpapers: 0,
            padPages: 0,
            targetPageSize: nil,
            normalizeOrientation: true
        )

        XCTAssertEqual(block.pageCount, 2)
        for index in 0..<block.pageCount {
            guard let page = block.page(at: index) else {
                XCTFail("missing page \(index)")
                return
            }
            XCTAssertTrue(PDFDocumentService.isPortrait(page))
            let size = page.bounds(for: .mediaBox).size
            XCTAssertEqual(size.width, 400, accuracy: 0.5)
            XCTAssertEqual(size.height, 600, accuracy: 0.5)
        }
    }

    func testPrinterSheetLabelRecognizesCommonTrims() {
        XCTAssertEqual(
            ImpositionService.printerSheetLabel(pageSize: CGSize(width: 595.28, height: 841.89)),
            "A3 Landscape"
        )
        XCTAssertEqual(
            ImpositionService.printerSheetLabel(pageSize: CGSize(width: 612, height: 792)),
            "Tabloid Landscape"
        )
        XCTAssertEqual(
            ImpositionService.printerSheetLabel(pageSize: CGSize(width: 419.53, height: 595.28)),
            "A4 Landscape"
        )
    }

    func testImpositionSummaryUsesPlanCounts() {
        var job = BindingJob()
        job.bindingStyle = .sectionSewn
        job.signatureSize = .sextodecimo
        job.frontEndpapers = 0
        job.backEndpapers = 0

        // 128 content pages → 8 signatures of 16 → 32 sheets
        let plan = ImpositionService.plan(contentPageCount: 128, job: job)
        let summary = plan.impositionSummary(sheetSizeLabel: "A3 Landscape")
        XCTAssertEqual(summary.totalPDFPages, 128)
        XCTAssertEqual(summary.totalSignatures, 8)
        XCTAssertEqual(summary.printSheetsRequired, 32)
        XCTAssertEqual(summary.sheetSizeLabel, "A3 Landscape")
    }
}
