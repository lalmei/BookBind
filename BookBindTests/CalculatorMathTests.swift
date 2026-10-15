import XCTest
@testable import BookBind

final class CalculatorMathTests: XCTestCase {
    func testCasePlanSizesBoardsSpineAndMaterial() {
        var input = CalculatorMath.CaseInputs()
        input.blockWidth = 150
        input.blockHeight = 220
        input.pageCount = 200   // 100 leaves × 0.1 mm = 10 mm block at 80 gsm
        input.gsm = 80
        input.boardThickness = 2
        input.square = 3
        input.jointGap = 7
        input.boardSetback = 3
        input.turnIn = 15

        let plan = CalculatorMath.casePlan(input)

        XCTAssertEqual(plan.blockThickness, 10, accuracy: 0.001)
        XCTAssertEqual(plan.boardWidth, 150, accuracy: 0.001)       // 150 − 3 setback + 3 square
        XCTAssertEqual(plan.boardHeight, 226, accuracy: 0.001)      // 220 + 2 × 3 square
        XCTAssertEqual(plan.spineWidth, 14, accuracy: 0.001)        // 10 block + 2 × 2 board
        let expectedCoverWidth: Double = 300 + 14 + 14 + 30          // boards + joints + spine + turn-ins
        XCTAssertEqual(plan.coverWidth, expectedCoverWidth, accuracy: 0.001)
        XCTAssertEqual(plan.coverHeight, 256, accuracy: 0.001)
        XCTAssertEqual(plan.cornerCutOffset, 3, accuracy: 0.001)
    }

    func testSignaturePlanPadsToWholeSignaturesAndReportsCreep() {
        let plan = CalculatorMath.signaturePlan(.init(pageCount: 250, sheetsPerSignature: 4, gsm: 80))

        XCTAssertEqual(plan.pagesPerSignature, 16)
        XCTAssertEqual(plan.signatureCount, 16)                     // 250 / 16 → 15.6 → 16
        XCTAssertEqual(plan.blankPages, 6)                          // 256 − 250
        XCTAssertEqual(plan.totalSheets, 64)
        XCTAssertEqual(plan.creepMM, 0.3, accuracy: 0.0001)         // 3 wrapping sheets × 0.1 mm
        XCTAssertEqual(plan.creepPoints, 0.3 * 72 / 25.4, accuracy: 0.0001)
    }

    func testSingleSheetSignatureHasNoCreep() {
        let plan = CalculatorMath.signaturePlan(.init(pageCount: 8, sheetsPerSignature: 1, gsm: 120))
        XCTAssertEqual(plan.signatureCount, 2)
        XCTAssertEqual(plan.creepMM, 0)
    }

    func testSewingStationsSpanKettlesEvenly() {
        let plan = CalculatorMath.sewingPlan(.init(spineHeight: 210, stationCount: 6, kettleInset: 15, signatureCount: 10))

        XCTAssertEqual(plan.stations.count, 6)
        XCTAssertEqual(plan.stations.first ?? -1, 15, accuracy: 0.001)
        XCTAssertEqual(plan.stations.last ?? -1, 195, accuracy: 0.001)
        XCTAssertEqual(plan.spacing, 36, accuracy: 0.001)           // (210 − 30) / 5
        XCTAssertEqual(plan.threadLength, 210 * 12, accuracy: 0.001)
    }

    func testSewingClampsKettleInsetToHalfTheSpine() {
        let plan = CalculatorMath.sewingPlan(.init(spineHeight: 20, stationCount: 2, kettleInset: 50, signatureCount: 1))
        XCTAssertEqual(plan.stations, [10, 10])
    }

    func testYieldKeepsGrainParallelToFold() {
        // A1 long grain runs along the 841 mm side. A5 folio flat = 302 × 216 incl. 3 mm trim;
        // the 216 mm fold must run along the 841 side, so the folio stays upright.
        let plan = CalculatorMath.yieldPlan(.init(
            parentWidth: 594, parentHeight: 841, parentGrain: .long,
            pageWidth: 148, pageHeight: 210, trimAllowance: 3, pageCount: 256
        ))

        XCTAssertFalse(plan.rotated)
        XCTAssertEqual(plan.folioWidth, 302, accuracy: 0.001)
        XCTAssertEqual(plan.folioHeight, 216, accuracy: 0.001)
        XCTAssertEqual(plan.columns, 1)                             // 594 / 302
        XCTAssertEqual(plan.rows, 3)                                // 841 / 216
        XCTAssertEqual(plan.perSheet, 3)
        XCTAssertEqual(plan.crossGrainCount, 4)                     // (594/216=2) × (841/302=2)
        XCTAssertEqual(plan.parentSheetsNeeded, 22)                 // 64 folios / 3
    }

    func testShortGrainRotatesFolio() {
        let plan = CalculatorMath.yieldPlan(.init(
            parentWidth: 594, parentHeight: 841, parentGrain: .short,
            pageWidth: 148, pageHeight: 210, trimAllowance: 3, pageCount: 16
        ))
        XCTAssertTrue(plan.rotated)
        XCTAssertEqual(plan.perSheet, 4)
    }

    func testFolioLargerThanSheetYieldsNothing() {
        let plan = CalculatorMath.yieldPlan(.init(
            parentWidth: 200, parentHeight: 200, parentGrain: .long,
            pageWidth: 148, pageHeight: 210, trimAllowance: 3, pageCount: 16
        ))
        XCTAssertEqual(plan.perSheet, 0)
        XCTAssertEqual(plan.parentSheetsNeeded, 0)
    }

    func testPagesPerInchFromCaliper() {
        XCTAssertEqual(CalculatorMath.pagesPerInch(gsm: 80), 508, accuracy: 0.5)
    }

    func testSewingTemplateIsSinglePagePDFAtTrueScale() throws {
        let plan = CalculatorMath.sewingPlan(.init(spineHeight: 200, stationCount: 4, kettleInset: 10, signatureCount: 4))
        let data = SewingTemplateExporter.pdfData(plan: plan, spineHeight: 200)
        let document = try XCTUnwrap(CGPDFDocument(CGDataProvider(data: data as CFData)!))
        XCTAssertEqual(document.numberOfPages, 1)
        let box = try XCTUnwrap(document.page(at: 1)).getBoxRect(.mediaBox)
        XCTAssertEqual(box.width, (200 + 30) * 72 / 25.4, accuracy: 0.01)
    }
}
