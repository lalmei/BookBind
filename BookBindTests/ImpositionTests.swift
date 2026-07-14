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
}
