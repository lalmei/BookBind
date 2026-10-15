import XCTest
@testable import BookBind

final class DesignEditorUnificationTests: XCTestCase {
    private func makeProject(
        width: Double = 152,
        height: Double = 229,
        architecture: BindingArchitecture = .caseBound,
        turnIn: Double = 15,
        hinge: Double = 8,
        spineOverride: Double? = nil
    ) -> BinderyProject {
        var project = BinderyProject(title: "Guide Test")
        project.widthMM = width
        project.heightMM = height
        project.architecture = architecture
        project.coverTurnInMM = turnIn
        project.hingeGapMM = hinge
        project.spineWidthOverrideMM = spineOverride
        project.boardThicknessMM = 2
        project.estimatedPageCount = 200
        return project
    }

    // MARK: - Cover dimensions / guides

    func testMaterialSheetIncludesTurnIn() {
        let project = makeProject(turnIn: 15)
        let geo = CoverBlueprintService.Geometry(project: project, spineWidthMM: 20)
        XCTAssertEqual(geo.turnInMM, 15, accuracy: 0.01)
        XCTAssertEqual(geo.materialW, geo.totalW + 30, accuracy: 0.01)
        XCTAssertEqual(geo.materialH, geo.boardH + 30, accuracy: 0.01)
        XCTAssertEqual(geo.boardOriginXMM, 15, accuracy: 0.01)
        XCTAssertEqual(geo.boardOriginYMM, 15, accuracy: 0.01)
    }

    func testTurnInSuppressedWithoutWrap() {
        let project = makeProject(architecture: .perfectBound, turnIn: 15)
        let geo = CoverBlueprintService.Geometry(project: project, spineWidthMM: 12)
        XCTAssertEqual(geo.effectiveTurnInOrZero, 0, accuracy: 0.01)
        XCTAssertFalse(geo.hasTurnIn)
    }

    func testSpineAndHingeAffectGuideXs() {
        let project = makeProject(hinge: 8, spineOverride: 24)
        let geo = CoverBlueprintService.Geometry(project: project, spineWidthMM: 24)
        XCTAssertEqual(geo.midsection, 24, accuracy: 0.01)
        XCTAssertEqual(geo.hinge, 8, accuracy: 0.01)
        XCTAssertEqual(geo.spineFace, 8, accuracy: 0.01)
        let xs = geo.guideXsMM
        XCTAssertTrue(xs.contains(where: { abs($0 - geo.boardW) < 0.01 }))
        XCTAssertTrue(xs.contains(where: { abs($0 - (geo.boardW + geo.midsection)) < 0.01 }))
    }

    func testMaterialGuideXsOffsetByTurnIn() {
        let project = makeProject(turnIn: 12)
        let geo = CoverBlueprintService.Geometry(project: project, spineWidthMM: 18)
        let board = geo.guideXsMM
        let material = geo.materialGuideXsMM
        XCTAssertEqual(board.count, material.count)
        for (b, m) in zip(board, material) {
            XCTAssertEqual(m, b + 12, accuracy: 0.01)
        }
    }

    func testProductionLayoutCornerMiterCount() {
        let project = makeProject(turnIn: 15)
        let geo = CoverBlueprintService.Geometry(project: project, spineWidthMM: 20)
        var spec = CoverProductionSpec.default
        spec.cornerTreatment = .miter
        let layout = geo.productionLayout(spec: spec)
        XCTAssertEqual(layout.cornerCuts.count, 4)
        XCTAssertEqual(layout.boardRect.minX, 15, accuracy: 0.01)
        XCTAssertEqual(layout.foldXs.first ?? -1, 15 + geo.boardW, accuracy: 0.2)
    }

    func testProductionLayoutSquareCorners() {
        let project = makeProject(turnIn: 15)
        let geo = CoverBlueprintService.Geometry(project: project, spineWidthMM: 20)
        var spec = CoverProductionSpec.default
        spec.cornerTreatment = .square
        let layout = geo.productionLayout(spec: spec)
        XCTAssertEqual(layout.cornerCuts.count, 8)
    }

    func testReliefCutsWhenEnabled() {
        let project = makeProject(turnIn: 15, hinge: 8, spineOverride: 24)
        let geo = CoverBlueprintService.Geometry(project: project, spineWidthMM: 24)
        var spec = CoverProductionSpec.default
        spec.reliefCutsEnabled = true
        spec.reliefCutLengthMM = 6
        let layout = geo.productionLayout(spec: spec)
        XCTAssertEqual(layout.reliefCuts.count, 4)
    }

    func testBleedExpandsCutRect() {
        let project = makeProject(turnIn: 15)
        let geo = CoverBlueprintService.Geometry(project: project, spineWidthMM: 20)
        var spec = CoverProductionSpec.default
        spec.bleedMM = 3
        let layout = geo.productionLayout(spec: spec)
        XCTAssertEqual(layout.cutRect.width, geo.materialW + 6, accuracy: 0.01)
        XCTAssertEqual(layout.materialRect.minX, 3, accuracy: 0.01)
        XCTAssertEqual(layout.boardRect.minX, 18, accuracy: 0.01)
    }

    // MARK: - Clean vs production SVG

    func testProductionSVGIncludesGuideGroups() throws {
        let project = makeProject()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cover-prod-\(UUID().uuidString).svg")
        defer { try? FileManager.default.removeItem(at: url) }
        try CoverBlueprintService.writeSVG(
            for: project, pageCount: 200, spineWidthMM: 20, to: url, mode: .production
        )
        let svg = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(svg.contains("data-production-guide=\"true\""))
        XCTAssertTrue(svg.contains("id=\"guides-cut\"") || svg.contains("id=\"guides-fold\""))
        XCTAssertTrue(svg.contains("id=\"artwork\""))
    }

    func testCleanSVGOmitsProductionGuides() throws {
        let project = makeProject()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cover-clean-\(UUID().uuidString).svg")
        defer { try? FileManager.default.removeItem(at: url) }
        try CoverBlueprintService.writeSVG(
            for: project, pageCount: 200, spineWidthMM: 20, to: url, mode: .clean
        )
        let svg = try String(contentsOf: url, encoding: .utf8)
        XCTAssertFalse(svg.contains("data-production-guide"))
        XCTAssertFalse(svg.contains("guides-fold"))
        XCTAssertTrue(svg.contains("id=\"artwork\""))
    }

    // MARK: - Shared editor math

    func testAlignLeft() {
        let frames = [
            DesignFrame(id: UUID(), xMM: 10, yMM: 0, widthMM: 20, heightMM: 10, rotationDegrees: 0),
            DesignFrame(id: UUID(), xMM: 40, yMM: 5, widthMM: 10, heightMM: 10, rotationDegrees: 0)
        ]
        let aligned = DesignEditorMath.align(frames, edge: .left)
        XCTAssertEqual(aligned[0].xMM, 10, accuracy: 0.01)
        XCTAssertEqual(aligned[1].xMM, 10, accuracy: 0.01)
    }

    func testDistributeHorizontal() {
        let a = UUID(), b = UUID(), c = UUID()
        let frames = [
            DesignFrame(id: a, xMM: 0, yMM: 0, widthMM: 10, heightMM: 10, rotationDegrees: 0),
            DesignFrame(id: b, xMM: 10, yMM: 0, widthMM: 10, heightMM: 10, rotationDegrees: 0),
            DesignFrame(id: c, xMM: 40, yMM: 0, widthMM: 10, heightMM: 10, rotationDegrees: 0)
        ]
        let distributed = DesignEditorMath.distribute(frames, axis: .horizontal)
        let mids = distributed.map(\.midX).sorted()
        XCTAssertEqual(mids[1] - mids[0], mids[2] - mids[1], accuracy: 0.01)
    }

    func testGroupAndExpandSelection() {
        let id1 = UUID(), id2 = UUID(), id3 = UUID()
        let gid = UUID()
        let frames = [
            DesignFrame(id: id1, xMM: 0, yMM: 0, widthMM: 10, heightMM: 10, rotationDegrees: 0, groupID: gid),
            DesignFrame(id: id2, xMM: 20, yMM: 0, widthMM: 10, heightMM: 10, rotationDegrees: 0, groupID: gid),
            DesignFrame(id: id3, xMM: 40, yMM: 0, widthMM: 10, heightMM: 10, rotationDegrees: 0)
        ]
        let expanded = DesignEditorMath.expandSelection(selectedIDs: [id1], frames: frames)
        XCTAssertTrue(expanded.contains(id1))
        XCTAssertTrue(expanded.contains(id2))
        XCTAssertFalse(expanded.contains(id3))
    }

    // MARK: - Marble paint + endsheet migration

    func testMarbledPaintRoundTrip() throws {
        let spec = MarbledPaperSpec(style: .peacock, seed: 42)
        let paint: CoverPaint = .marbled(spec)
        let data = try JSONEncoder().encode(paint)
        let decoded = try JSONDecoder().decode(CoverPaint.self, from: data)
        XCTAssertEqual(decoded.marbling?.seed, 42)
        XCTAssertEqual(decoded.marbling?.style, .peacock)
        XCTAssertTrue(decoded.isMarbled)
    }

    func testEndsheetDocumentMigratesFromMarbledMode() {
        var face = EndpaperFaceDesign(mode: .marbled, marbling: MarbledPaperSpec(seed: 99))
        let geo = EndsheetGeometry(leafWidthMM: 100, leafHeightMM: 150)
        face.ensureDesignDocument(geometry: geo)
        XCTAssertFalse(face.document.elements.isEmpty)
        XCTAssertTrue(face.document.elements.contains { $0.fill.isMarbled })
    }

    func testEndsheetCleanSVGOmitsFoldGuides() throws {
        var face = EndpaperFaceDesign(mode: .solidColor, solidColor: .archivalIvory, showFoldGuides: true)
        let geo = EndsheetGeometry(leafWidthMM: 100, leafHeightMM: 150)
        face.ensureDesignDocument(geometry: geo)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("endsheet-clean-\(UUID().uuidString).svg")
        defer { try? FileManager.default.removeItem(at: url) }
        try EndsheetBlueprintService.writeSVG(
            face: face, geometry: geo, isFront: true,
            projectTitle: "T", to: url, mode: .clean
        )
        let svg = try String(contentsOf: url, encoding: .utf8)
        XCTAssertFalse(svg.contains("data-production-guide"))
        XCTAssertTrue(svg.contains("id=\"artwork\""))
    }
}

private extension CoverBlueprintService.Geometry {
    /// Test helper — turn-in already zeroed for non-wrapping architectures via project.effectiveTurnInMM.
    var effectiveTurnInOrZero: Double { turnInMM }
}
