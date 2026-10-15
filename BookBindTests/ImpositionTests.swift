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

    func testRecommendedStitchHoleCountScalesWithSheets() {
        XCTAssertEqual(ImpositionService.recommendedStitchHoleCount(sheetCount: 2, pageHeight: 792), 2)
        XCTAssertEqual(ImpositionService.recommendedStitchHoleCount(sheetCount: 4, pageHeight: 792), 2)
        XCTAssertEqual(ImpositionService.recommendedStitchHoleCount(sheetCount: 5, pageHeight: 792), 3)
        XCTAssertEqual(ImpositionService.recommendedStitchHoleCount(sheetCount: 8, pageHeight: 792), 3)
        XCTAssertEqual(ImpositionService.recommendedStitchHoleCount(sheetCount: 2, pageHeight: 60), 1)
    }

    func testResolvedStitchHoleCountHonorsAutoAndExplicitChoices() {
        XCTAssertEqual(
            ImpositionService.resolvedStitchHoleCount(setting: .auto, sheetCount: 2, pageHeight: 792),
            2
        )
        XCTAssertEqual(
            ImpositionService.resolvedStitchHoleCount(setting: .auto, sheetCount: 6, pageHeight: 792),
            3
        )
        XCTAssertEqual(
            ImpositionService.resolvedStitchHoleCount(setting: .three, sheetCount: 2, pageHeight: 792),
            3
        )
        XCTAssertEqual(
            ImpositionService.resolvedStitchHoleCount(setting: .three, sheetCount: 2, pageHeight: 60),
            1
        )
    }

    func testStitchHoleCentersUseHeadAndFootInsets() {
        let trimOrigin = CGPoint(x: 14, y: 14)
        let pageSize = CGSize(width: 100, height: 200)
        let spineX = trimOrigin.x + pageSize.width

        let centers = ImpositionService.stitchHoleCenters(
            spineX: spineX,
            trimOrigin: trimOrigin,
            pageSize: pageSize,
            holeCount: 2
        )

        XCTAssertEqual(centers.count, 2)
        XCTAssertEqual(centers[0].x, spineX, accuracy: 0.001)
        XCTAssertEqual(centers[1].x, spineX, accuracy: 0.001)
        XCTAssertEqual(centers[0].y, trimOrigin.y + pageSize.height - 36, accuracy: 0.001)
        XCTAssertEqual(centers[1].y, trimOrigin.y + 36, accuracy: 0.001)
    }

    func testStitchHoleCentersPlaceThreeAlongFold() {
        let trimOrigin = CGPoint(x: 0, y: 0)
        let pageSize = CGSize(width: 100, height: 200)
        let spineX: CGFloat = 100

        let centers = ImpositionService.stitchHoleCenters(
            spineX: spineX,
            trimOrigin: trimOrigin,
            pageSize: pageSize,
            holeCount: 3
        )

        XCTAssertEqual(centers.count, 3)
        XCTAssertEqual(centers[0].y, 164, accuracy: 0.001)
        XCTAssertEqual(centers[1].y, 100, accuracy: 0.001)
        XCTAssertEqual(centers[2].y, 36, accuracy: 0.001)
    }

    func testStitchHoleCentersFallbackToCenterOnShortPages() {
        let trimOrigin = CGPoint(x: 0, y: 0)
        let pageSize = CGSize(width: 100, height: 40)
        let spineX: CGFloat = 100

        let centers = ImpositionService.stitchHoleCenters(
            spineX: spineX,
            trimOrigin: trimOrigin,
            pageSize: pageSize,
            holeCount: 2
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

        // Marks sit outside the bleed: 3 pt gap + 12 pt mark + 2 pt slack per side.
        let marked = ImpositionService.spreadMediaSize(pageSize: page, bleed: 0, addCropMarks: true)
        XCTAssertEqual(marked.width, 234)
        XCTAssertEqual(marked.height, 234)

        let bledAndMarked = ImpositionService.spreadMediaSize(pageSize: page, bleed: 9, addCropMarks: true)
        XCTAssertEqual(bledAndMarked.width, 252)
        XCTAssertEqual(bledAndMarked.height, 252)
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

    func testMiniZine8PlanPadsToEightAndOneSheet() {
        var job = BindingJob()
        job.applyImpositionScheme(.miniZine8)
        job.frontEndpapers = 0
        job.backEndpapers = 0

        let plan = ImpositionService.plan(contentPageCount: 5, job: job)
        XCTAssertEqual(plan.padPages, 3)
        XCTAssertEqual(plan.pagesPerSignature, 8)
        XCTAssertEqual(plan.signatureCount, 1)
        XCTAssertEqual(plan.printSheetsRequired, 1)
        XCTAssertEqual(plan.impositionScheme, .miniZine8)
    }

    func testMiniZine8LayoutPageOrderAndCutGuide() {
        let layout = ImpositionService.miniZine8Layout(template: .classicNested)
        XCTAssertEqual(layout.columns, 4)
        XCTAssertEqual(layout.rows, 2)
        XCTAssertEqual(layout.cells.count, 8)

        // Bottom row (PDF): 6,7,8,1
        XCTAssertEqual(layout.cells.first { $0.column == 0 && $0.row == 0 }?.pageIndex, 5)
        XCTAssertEqual(layout.cells.first { $0.column == 3 && $0.row == 0 }?.pageIndex, 0)
        // Top row upside-down: 5,4,3,2
        XCTAssertEqual(layout.cells.first { $0.column == 0 && $0.row == 1 }?.pageIndex, 4)
        XCTAssertEqual(layout.cells.first { $0.column == 0 && $0.row == 1 }?.rotationDegrees, 180)

        let stock = CGSize(width: 792, height: 612)
        var job = BindingJob()
        job.applyImpositionScheme(.miniZine8)
        job.miniZine8Template = .classicNested
        job.paperSize = .custom
        job.customPageWidth = 792
        job.customPageHeight = 612
        let guided = ImpositionService.sheetLayout(for: job, stockSize: stock)
        let cuts = guided.guides.filter { $0.kind == .cut }
        XCTAssertEqual(cuts.count, 1)
        XCTAssertTrue(guided.guides.contains { $0.kind == .fold })
        let cut = cuts[0]
        // Center slit: middle two columns only (cellW … 3*cellW at mid height).
        XCTAssertEqual(cut.start.y, 306, accuracy: 0.01)
        XCTAssertEqual(cut.end.y, 306, accuracy: 0.01)
        XCTAssertEqual(cut.start.x, 198, accuracy: 0.01)
        XCTAssertEqual(cut.end.x, 594, accuracy: 0.01)
    }

    func testMiniZine8AlternateTemplatesChangePageMapNotCut() {
        let stock = CGSize(width: 792, height: 612)
        for template in MiniZine8Template.allCases {
            var job = BindingJob()
            job.impositionScheme = .miniZine8
            job.miniZine8Template = template
            let layout = ImpositionService.sheetLayout(for: job, stockSize: stock)
            XCTAssertEqual(layout.cells.count, 8, template.rawValue)
            let top = template.topRowPages
            let bottom = template.bottomRowPages
            for col in 0..<4 {
                XCTAssertEqual(
                    layout.cells.first { $0.column == col && $0.row == 1 }?.pageIndex,
                    top[col],
                    "\(template.rawValue) top col \(col)"
                )
                XCTAssertEqual(
                    layout.cells.first { $0.column == col && $0.row == 0 }?.pageIndex,
                    bottom[col],
                    "\(template.rawValue) bottom col \(col)"
                )
            }
            let cuts = layout.guides.filter { $0.kind == .cut }
            XCTAssertEqual(cuts.count, 1, template.rawValue)
            XCTAssertEqual(cuts[0].start.x, 198, accuracy: 0.01)
            XCTAssertEqual(cuts[0].end.x, 594, accuracy: 0.01)
        }
    }

    func testMiniZine16CutTemplates() {
        let stock = CGSize(width: 792, height: 612)
        var cross = BindingJob()
        cross.impositionScheme = .miniZine16
        cross.miniZine16Template = .crossCut
        let crossLayout = ImpositionService.sheetLayout(for: cross, stockSize: stock)
        XCTAssertEqual(crossLayout.guides.filter { $0.kind == .cut }.count, 2)

        var slits = BindingJob()
        slits.impositionScheme = .miniZine16
        slits.miniZine16Template = .horizontalSlits
        let slitsLayout = ImpositionService.sheetLayout(for: slits, stockSize: stock)
        XCTAssertEqual(slitsLayout.guides.filter { $0.kind == .cut }.count, 2)
        XCTAssertTrue(slitsLayout.guides.filter { $0.kind == .cut }.allSatisfy { abs($0.start.y - $0.end.y) < 0.01 })
    }

    func testMiniZine8TrimDerivesFromLetterStock() {
        var job = BindingJob()
        job.applyImpositionScheme(.miniZine8)
        job.paperSize = .custom
        job.customPageWidth = 792
        job.customPageHeight = 612
        guard let trim = job.resolvedTrimSize else {
            XCTFail("expected trim")
            return
        }
        XCTAssertEqual(trim.width, 198, accuracy: 0.01)
        XCTAssertEqual(trim.height, 306, accuracy: 0.01)
        XCTAssertEqual(ImpositionService.printerSheetLabel(for: job, pageSize: trim), "US Letter Landscape")
    }

    func testMiniZine16AndAccordionPlans() {
        var zine = BindingJob()
        zine.applyImpositionScheme(.miniZine16)
        zine.frontEndpapers = 0
        zine.backEndpapers = 0
        let zinePlan = ImpositionService.plan(contentPageCount: 10, job: zine)
        XCTAssertEqual(zinePlan.pagesPerSignature, 16)
        XCTAssertEqual(zinePlan.padPages, 6)
        XCTAssertEqual(zinePlan.printSheetsRequired, 1)

        var accordion = BindingJob()
        accordion.applyImpositionScheme(.accordion)
        accordion.accordionPanelCount = 6
        accordion.frontEndpapers = 0
        accordion.backEndpapers = 0
        let accordionPlan = ImpositionService.plan(contentPageCount: 4, job: accordion)
        XCTAssertEqual(accordionPlan.pagesPerSignature, 6)
        XCTAssertEqual(accordionPlan.padPages, 2)
        XCTAssertEqual(accordionPlan.printSheetsRequired, 1)
    }

    func testHalfFoldBookletUsesSaddleStitchFolio() {
        var job = BindingJob()
        job.applyImpositionScheme(.halfFoldBooklet)
        XCTAssertEqual(job.bindingStyle, .saddleStitch)
        XCTAssertTrue(job.impositionScheme.usesFolioImpose)
        XCTAssertEqual(job.frontEndpapers, 0)

        let plan = ImpositionService.plan(contentPageCount: 6, job: job)
        XCTAssertEqual(plan.pagesPerSignature, 8)
        XCTAssertEqual(plan.printSheetsRequired, 2)
    }

    func testImposeMiniZine8ProducesOneSheet() throws {
        var job = BindingJob()
        job.applyImpositionScheme(.miniZine8)
        job.paperSize = .custom
        job.customPageWidth = 792
        job.customPageHeight = 612
        job.showGuideMarks = true
        job.frontEndpapers = 0
        job.backEndpapers = 0

        let block = PDFDocument()
        let trim = job.resolvedTrimSize!
        for _ in 0..<8 {
            block.insert(PDFDocumentService.makeBlankPage(size: trim), at: block.pageCount)
        }
        let plan = ImpositionService.plan(contentPageCount: 8, job: job)
        let imposed = try ImpositionService.impose(bookBlock: block, plan: plan, job: job)
        XCTAssertEqual(imposed.pageCount, 1)
        let media = imposed.page(at: 0)!.bounds(for: .mediaBox).size
        XCTAssertEqual(media.width, 792, accuracy: 1)
        XCTAssertEqual(media.height, 612, accuracy: 1)
    }
}
