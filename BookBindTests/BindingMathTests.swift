import XCTest
@testable import BookBind

final class BindingMathTests: XCTestCase {
    func testSheetThicknessPositive() {
        XCTAssertGreaterThan(BindingMath.sheetThicknessMM(gsm: 80), 0)
    }

    func testTextBlockScalesWithPages() {
        let thin = BindingMath.textBlockThicknessMM(pageCount: 100, gsm: 80)
        let thick = BindingMath.textBlockThicknessMM(pageCount: 200, gsm: 80)
        XCTAssertEqual(thick, thin * 2, accuracy: 0.0001)
    }

    func testCaseSpineIncludesBoardsAndHinges() {
        let block = BindingMath.textBlockThicknessMM(pageCount: 200, gsm: 80)
        let spine = BindingMath.caseSpineWidthMM(
            pageCount: 200,
            gsm: 80,
            boardThicknessMM: 2,
            hingeGapMM: 8
        )
        XCTAssertEqual(spine, block + 4 + 16, accuracy: 0.0001)
    }

    func testGSMBondRoundTrip() {
        let gsm = 90.0
        let bond = BindingMath.gsmToBondLb(gsm)
        XCTAssertEqual(BindingMath.bondLbToGSM(bond), gsm, accuracy: 0.001)
    }

    func testCreepZeroForSingleSheet() {
        XCTAssertEqual(BindingMath.suggestedCreepPoints(gsm: 80, sheetsPerSignature: 1), 0)
    }

    func testMillimeterPointRoundTrip() {
        let mm = 152.0
        let points = BindingMath.points(fromMillimeters: mm)
        XCTAssertEqual(BindingMath.millimeters(fromPoints: points), mm, accuracy: 0.0001)
    }

    func testPaperSizeMatchesLetterPreset() {
        XCTAssertEqual(PaperSize.matching(widthPoints: 612, heightPoints: 792), .letter)
        XCTAssertEqual(PaperSize.matching(widthPoints: 792, heightPoints: 612), .letter)
    }

    func testBindingJobAppliesProjectTrimAsCustom() throws {
        var job = BindingJob()
        job.applyProjectTrim(widthMM: 152, heightMM: 229)
        XCTAssertEqual(job.paperSize, .custom)
        let trim = try XCTUnwrap(job.resolvedTrimSize)
        XCTAssertEqual(BindingMath.millimeters(fromPoints: trim.width), 152, accuracy: 0.05)
        XCTAssertEqual(BindingMath.millimeters(fromPoints: trim.height), 229, accuracy: 0.05)
    }

    func testBindingJobAppliesA5ProjectTrimAsPreset() {
        var job = BindingJob()
        // A5 is 148 × 210 mm
        job.applyProjectTrim(widthMM: 148, heightMM: 210)
        XCTAssertEqual(job.paperSize, .a5)
    }

    func testProjectAppliesImpositionTrim() {
        var project = BinderyProject(title: "Test", heightMM: 100, widthMM: 100)
        var job = BindingJob()
        job.paperSize = .letter
        project.applyImpositionTrim(from: job)
        XCTAssertEqual(project.widthMM, BindingMath.millimeters(fromPoints: 612), accuracy: 0.15)
        XCTAssertEqual(project.heightMM, BindingMath.millimeters(fromPoints: 792), accuracy: 0.15)
    }

    func testSpineWidthVariesByArchitecture() {
        let pages = 200
        let gsm = 80.0
        let caseSpine = BindingMath.spineWidthMM(
            architecture: .caseBound,
            pageCount: pages,
            gsm: gsm,
            boardThicknessMM: 2,
            hingeGapMM: 8
        )
        let perfectSpine = BindingMath.spineWidthMM(
            architecture: .perfectBound,
            pageCount: pages,
            gsm: gsm,
            boardThicknessMM: 0.35,
            hingeGapMM: 0
        )
        let copticSpine = BindingMath.spineWidthMM(
            architecture: .coptic,
            pageCount: pages,
            gsm: gsm,
            boardThicknessMM: 0,
            hingeGapMM: 0
        )
        let saddleSpine = BindingMath.spineWidthMM(
            architecture: .saddleStitch,
            pageCount: pages,
            gsm: gsm,
            boardThicknessMM: 0.25,
            hingeGapMM: 0
        )
        XCTAssertGreaterThan(caseSpine, copticSpine)
        XCTAssertGreaterThan(copticSpine, perfectSpine)
        XCTAssertGreaterThan(perfectSpine, saddleSpine)
    }

    func testArchitectureMapsToMatchingImposeStyle() {
        var job = BindingJob()
        job.applyArchitecture(.caseBound)
        XCTAssertEqual(job.bindingStyle, .caseBound)
        job.applyArchitecture(.sectionSewn)
        XCTAssertEqual(job.bindingStyle, .sectionSewn)
        job.applyArchitecture(.perfectBound)
        XCTAssertEqual(job.bindingStyle, .perfectBound)
        job.applyArchitecture(.coptic)
        XCTAssertEqual(job.bindingStyle, .coptic)
        job.applyArchitecture(.saddleStitch)
        XCTAssertEqual(job.bindingStyle, .saddleStitch)
    }
}
