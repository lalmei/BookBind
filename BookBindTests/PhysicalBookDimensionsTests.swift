import XCTest
@testable import BookBind

final class PhysicalBookDimensionsTests: XCTestCase {
    func testResolvingUsesGeometryAndBindingMath() {
        var project = BinderyProject(
            title: "Dims",
            heightMM: 229,
            widthMM: 152,
            architecture: .caseBound,
            boardThicknessMM: 2,
            hingeGapMM: 8,
            textPaperGSM: 80,
            estimatedPageCount: 200
        )
        project.spineWidthOverrideMM = nil

        let dims = PhysicalBookDimensions.resolving(project: project)
        let expectedSpine = BindingMath.spineWidthMM(
            architecture: .caseBound,
            pageCount: 200,
            gsm: 80,
            boardThicknessMM: 2,
            hingeGapMM: 8
        )
        let geo = CoverBlueprintService.Geometry(project: project, spineWidthMM: expectedSpine)

        XCTAssertEqual(dims.pageCount, 200)
        XCTAssertEqual(dims.spineWidthMM, expectedSpine, accuracy: 0.0001)
        XCTAssertEqual(dims.boardWidthMM, geo.boardW, accuracy: 0.0001)
        XCTAssertEqual(dims.boardHeightMM, geo.boardH, accuracy: 0.0001)
        XCTAssertEqual(dims.hingeMM, geo.hinge, accuracy: 0.0001)
        XCTAssertEqual(dims.spineFaceMM, geo.spineFace, accuracy: 0.0001)
        XCTAssertEqual(dims.midsectionMM, geo.midsection, accuracy: 0.0001)
        XCTAssertEqual(
            dims.textBlockThicknessMM,
            BindingMath.textBlockThicknessMM(pageCount: 200, gsm: 80),
            accuracy: 0.0001
        )
    }

    func testSpineOverrideIsHonored() {
        var project = BinderyProject(
            title: "Override",
            heightMM: 210,
            widthMM: 148,
            estimatedPageCount: 100
        )
        project.spineWidthOverrideMM = 22.5

        let dims = PhysicalBookDimensions.resolving(project: project)
        XCTAssertEqual(dims.spineWidthMM, 22.5, accuracy: 0.0001)
        XCTAssertEqual(dims.midsectionMM, 22.5, accuracy: 0.0001)
    }

    func testAssembledPageCountPreferredOverEstimate() {
        let project = BinderyProject(
            title: "Workspace",
            estimatedPageCount: 40
        )
        let dims = PhysicalBookDimensions.resolving(project: project, assembledPageCount: 120)
        XCTAssertEqual(dims.pageCount, 120)

        let dimsFallback = PhysicalBookDimensions.resolving(project: project, assembledPageCount: 0)
        XCTAssertEqual(dimsFallback.pageCount, 40)
    }

    func testArchitectureAffectsEffectiveBoardThickness() {
        let caseDims = PhysicalBookDimensions(
            boardWidthMM: 152,
            boardHeightMM: 229,
            boardThicknessMM: 2,
            hingeMM: 8,
            spineFaceMM: 20,
            midsectionMM: 36,
            textBlockThicknessMM: 10,
            spineWidthMM: 36,
            pageCount: 100,
            gsm: 80,
            architecture: .caseBound
        )
        let copticDims = PhysicalBookDimensions(
            boardWidthMM: 152,
            boardHeightMM: 229,
            boardThicknessMM: 2,
            hingeMM: 0,
            spineFaceMM: 16,
            midsectionMM: 16,
            textBlockThicknessMM: 10,
            spineWidthMM: 16,
            pageCount: 100,
            gsm: 80,
            architecture: .coptic
        )
        XCTAssertGreaterThan(caseDims.effectiveBoardThicknessMM, copticDims.effectiveBoardThicknessMM)
    }
}
