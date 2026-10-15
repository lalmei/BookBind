import AppKit
import XCTest
@testable import BookBind

final class CoverDesignTests: XCTestCase {
    func testLegacyProjectsDecodeWithoutCoverElements() throws {
        let json = """
        {
          "id": "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
          "title": "Legacy Book",
          "author": "Ada",
          "heightMM": 229,
          "widthMM": 152,
          "architecture": "Case Bound",
          "createdAt": "2026-01-01T00:00:00Z",
          "updatedAt": "2026-01-01T00:00:00Z",
          "boardThicknessMM": 2,
          "hingeGapMM": 8,
          "coverMaterial": "Book Cloth",
          "showFoilLayer": false,
          "showDebossLayer": false,
          "folioStampText": "LEGACY STAMP",
          "materials": [],
          "textPaperGSM": 80,
          "estimatedPageCount": 0
        }
        """
        let data = Data(json.utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var project = try decoder.decode(BinderyProject.self, from: data)
        XCTAssertTrue(project.coverElements.isEmpty)

        project.seedCoverElementsIfNeeded(spineWidthMM: 28.5)
        XCTAssertFalse(project.coverElements.isEmpty)
        XCTAssertFalse(project.coverDesignLayers.isEmpty)
        XCTAssertEqual(project.coverDesignLayers.count, 1)
        XCTAssertTrue(project.showFoilLayer)
        XCTAssertEqual(project.folioStampText, "LEGACY STAMP")
        XCTAssertTrue(project.coverElements.contains { $0.panel == .front && $0.text == "LEGACY STAMP" })
        XCTAssertTrue(project.coverElements.contains { $0.panel == .spine })
        XCTAssertTrue(project.coverElements.allSatisfy(\.usesWrapCoordinates))
    }

    func testWrapGeometrySplitsJointsAndSpineFace() {
        var project = BinderyProject(title: "Dune", heightMM: 297, widthMM: 210)
        project.hingeGapMM = 8
        let mid = 28.5
        let geo = CoverBlueprintService.Geometry(project: project, spineWidthMM: mid)

        XCTAssertEqual(geo.midsection, mid, accuracy: 0.01)
        XCTAssertEqual(geo.hinge, 8, accuracy: 0.01)
        XCTAssertEqual(geo.spineFace, mid - 16, accuracy: 0.01)
        XCTAssertEqual(geo.layoutPanels, [.back, .backHinge, .spine, .frontHinge, .front])
        XCTAssertEqual(geo.panel(containingWrapX: geo.boardW + geo.hinge + 1), .spine)
        XCTAssertEqual(geo.panel(containingWrapX: 1), .back)
        XCTAssertEqual(geo.totalW, geo.boardW * 2 + geo.midsection, accuracy: 0.01)
    }

    func testTurnInExpandsMaterialSheetForWrappingArchitecture() {
        var project = BinderyProject(title: "Turned", heightMM: 297, widthMM: 210)
        project.architecture = .caseBound
        project.coverTurnInMM = 15
        let geo = CoverBlueprintService.Geometry(project: project, spineWidthMM: 28.5)

        XCTAssertTrue(geo.hasTurnIn)
        XCTAssertEqual(geo.turnInMM, 15, accuracy: 0.001)
        XCTAssertEqual(geo.materialW, geo.totalW + 30, accuracy: 0.01)
        XCTAssertEqual(geo.materialH, geo.boardH + 30, accuracy: 0.01)
        XCTAssertEqual(geo.boardOriginXMM, 15, accuracy: 0.001)
        XCTAssertEqual(geo.boardOriginYMM, 15, accuracy: 0.001)

        let layout = geo.turnInLayout(foldXsMM: geo.guideXsMM)
        XCTAssertEqual(layout.materialRect.width, geo.materialW, accuracy: 0.01)
        XCTAssertEqual(Double(layout.boardRect.minX), 15, accuracy: 0.001)
        XCTAssertEqual(layout.miterCuts.count, 4)
    }

    func testTurnInSuppressedForNonWrappingArchitecture() {
        var project = BinderyProject(title: "Softcover", heightMM: 297, widthMM: 210)
        project.architecture = .perfectBound
        project.coverTurnInMM = 15 // ignored — perfect-bound does not wrap boards
        let geo = CoverBlueprintService.Geometry(project: project, spineWidthMM: 20)

        XCTAssertFalse(geo.hasTurnIn)
        XCTAssertEqual(project.effectiveTurnInMM, 0, accuracy: 0.001)
        XCTAssertEqual(geo.materialW, geo.totalW, accuracy: 0.01)
        XCTAssertEqual(geo.materialH, geo.boardH, accuracy: 0.01)
    }

    func testLegacyProjectDefaultsTurnInFromArchitecture() throws {
        let json = """
        {
          "id": "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
          "title": "Legacy Book",
          "author": "Ada",
          "heightMM": 229,
          "widthMM": 152,
          "architecture": "Case Bound",
          "createdAt": "2026-01-01T00:00:00Z",
          "updatedAt": "2026-01-01T00:00:00Z",
          "boardThicknessMM": 2,
          "hingeGapMM": 8,
          "coverMaterial": "Book Cloth",
          "showFoilLayer": false,
          "showDebossLayer": false,
          "folioStampText": "",
          "materials": [],
          "textPaperGSM": 80,
          "estimatedPageCount": 0
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let project = try decoder.decode(BinderyProject.self, from: Data(json.utf8))

        XCTAssertEqual(project.coverTurnInMM, 15, accuracy: 0.001)
        XCTAssertEqual(project.pastedownInsetMM, 3, accuracy: 0.001)
    }

    func testInsetPastedownFillsBoardFaceWithRevealBorder() throws {
        let boardWMM = 152.0
        let boardHMM = 229.0
        let dpi: CGFloat = 150
        let pastedown = Self.solidNSImage(color: .systemBlue, widthPx: 200, heightPx: 300)

        let composed = try XCTUnwrap(CoverWrapTextureService.insetPastedown(
            pastedown,
            boardWidthMM: boardWMM,
            boardHeightMM: boardHMM,
            insetMM: 3,
            material: .bookCloth,
            dpi: dpi
        ))
        let cg = try XCTUnwrap(composed.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let expectedW = Int(ceil(boardWMM * Double(dpi) / 25.4))
        let expectedH = Int(ceil(boardHMM * Double(dpi) / 25.4))
        XCTAssertEqual(cg.width, expectedW)
        XCTAssertEqual(cg.height, expectedH)

        // Zero inset returns the original pastedown untouched.
        let untouched = CoverWrapTextureService.insetPastedown(
            pastedown,
            boardWidthMM: boardWMM,
            boardHeightMM: boardHMM,
            insetMM: 0,
            material: .bookCloth,
            dpi: dpi
        )
        XCTAssertEqual(untouched?.size, pastedown.size)
    }

    private static func solidNSImage(color: NSColor, widthPx: Int, heightPx: Int) -> NSImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(
            data: nil,
            width: widthPx,
            height: heightPx,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.setFillColor(color.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: widthPx, height: heightPx))
        let cg = ctx.makeImage()!
        return NSImage(cgImage: cg, size: NSSize(width: widthPx, height: heightPx))
    }

    func testMigratePanelLocalCoordinatesToWrapAbsolute() {
        var project = BinderyProject(title: "Dune", heightMM: 297, widthMM: 210)
        project.hingeGapMM = 8
        let geo = CoverBlueprintService.Geometry(project: project, spineWidthMM: 28.5)
        let layerID = UUID()
        project.coverDesignLayers = CoverDesignLayer.defaults()
        project.coverElements = [
            CoverDesignElement(
                kind: .text,
                panel: .spine,
                text: "AUTHOR",
                xMM: 5, // panel-local
                yMM: 100,
                designLayerID: layerID,
                usesWrapCoordinates: false,
                isPanelLocked: true
            )
        ]

        project.migrateCoverElementsToWrapCoordinates(geometry: geo)
        let element = project.coverElements[0]
        XCTAssertTrue(element.usesWrapCoordinates)
        XCTAssertEqual(element.xMM, geo.panelOriginX(.spine) + 5, accuracy: 0.01)
        XCTAssertFalse(element.isPanelLocked)
    }

    func testAddCoverDesignLayerAndImageElementRoundTrip() throws {
        var project = BinderyProject(title: "Dune", author: "Frank Herbert")
        project.seedCoverElementsIfNeeded(spineWidthMM: 20)
        project.addCoverDesignLayer(named: "Motifs")

        let layerID = try XCTUnwrap(project.activeCoverLayerID)
        XCTAssertEqual(project.coverDesignLayers.last?.name, "Motifs")

        let image = CoverDesignElement(
            kind: .image,
            panel: .back,
            xMM: 40,
            yMM: 60,
            widthMM: 30,
            heightMM: 40,
            designLayerID: layerID,
            usesWrapCoordinates: true,
            imagePathHint: "/tmp/motif.png",
            imageName: "motif.png"
        )
        project.coverElements.append(image)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(project)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let restored = try decoder.decode(BinderyProject.self, from: data)

        XCTAssertEqual(restored.coverDesignLayers.count, 2)
        XCTAssertTrue(restored.coverElements.contains { $0.kind == .image && $0.imageName == "motif.png" })
        XCTAssertEqual(restored.activeCoverLayerID, layerID)
    }

    func testLayerRenameMoveAndElementOrder() throws {
        var project = BinderyProject(title: "Dune")
        project.ensureCoverDesignLayers()
        let base = try XCTUnwrap(project.coverDesignLayers.first)
        project.addCoverDesignLayer(named: "Typography")
        let typography = try XCTUnwrap(project.coverDesignLayers.first { $0.name == "Typography" })

        let first = CoverDesignElement(
            kind: .text,
            panel: .front,
            text: "First",
            xMM: 10,
            yMM: 10,
            designLayerID: base.id
        )
        let second = CoverDesignElement(
            kind: .text,
            panel: .front,
            text: "Second",
            xMM: 12,
            yMM: 12,
            designLayerID: base.id
        )
        project.coverElements = [first, second]

        project.renameCoverDesignLayer(base.id, to: "Background Art")
        XCTAssertTrue(project.coverDesignLayers.contains { $0.id == base.id && $0.name == "Background Art" })

        project.moveCoverElement(second.id, toLayer: typography.id)
        XCTAssertEqual(project.coverElements.first { $0.id == second.id }?.designLayerID, typography.id)

        project.moveCoverElement(second.id, toLayer: base.id)
        project.moveCoverElementWithinLayer(first.id, direction: 1)
        let ordered = project.orderedCoverElementsForRendering()
        XCTAssertLessThan(
            try XCTUnwrap(ordered.firstIndex(where: { $0.id == second.id })),
            try XCTUnwrap(ordered.firstIndex(where: { $0.id == first.id }))
        )
    }

    func testDeletingLayerReassignsElementsToFallback() throws {
        var project = BinderyProject(title: "Dune")
        project.ensureCoverDesignLayers()
        project.addCoverDesignLayer(named: "Temporary")
        let temporary = try XCTUnwrap(project.coverDesignLayers.first { $0.name == "Temporary" })
        let element = CoverDesignElement(
            kind: .text,
            panel: .front,
            text: "Temp",
            xMM: 20,
            yMM: 20,
            designLayerID: temporary.id
        )
        project.coverElements = [element]

        project.removeCoverDesignLayer(temporary.id)

        XCTAssertFalse(project.coverDesignLayers.contains { $0.id == temporary.id })
        XCTAssertNotEqual(project.coverElements.first?.designLayerID, temporary.id)
        XCTAssertTrue(project.coverDesignLayers.contains { $0.id == project.coverElements.first?.designLayerID })
    }

    func testResizeMathMovesEdgesAndLocksAspectRatio() {
        let start = CoverElementBounds(centerX: 50, centerY: 50, width: 40, height: 20)

        let free = CoverEditorMath.resizedBounds(
            from: start,
            handle: .bottomRight,
            deltaX: 20,
            deltaY: 5,
            locksAspectRatio: false
        )
        XCTAssertEqual(free.width, 60, accuracy: 0.01)
        XCTAssertEqual(free.height, 25, accuracy: 0.01)
        XCTAssertEqual(free.centerX, 60, accuracy: 0.01)
        XCTAssertEqual(free.centerY, 52.5, accuracy: 0.01)

        let locked = CoverEditorMath.resizedBounds(
            from: start,
            handle: .bottomRight,
            deltaX: 20,
            deltaY: 5,
            locksAspectRatio: true
        )
        XCTAssertEqual(locked.width / locked.height, 2, accuracy: 0.01)
    }

    func testBoardSizeAllowsShrinkBelowImpositionButKeepsHardMinimum() {
        XCTAssertEqual(CoverEditorMath.boardSize(current: 210, proposed: 260), 260)
        // Below the imposition bound is allowed — warnings handle it, not clamps.
        XCTAssertEqual(CoverEditorMath.boardSize(current: 260, proposed: 190), 190)
        XCTAssertEqual(CoverEditorMath.boardSize(current: 210, proposed: 10), CoverEditorMath.hardMinimumBoardSizeMM)
        XCTAssertEqual(CoverEditorMath.boardSize(current: 210, proposed: .nan), 210)
    }

    func testSpineWidthOverrideNormalization() {
        XCTAssertEqual(CoverEditorMath.spineWidthOverride(proposed: 24.5), 24.5)
        XCTAssertEqual(CoverEditorMath.spineWidthOverride(proposed: 1), CoverEditorMath.hardMinimumSpineWidthMM)
        XCTAssertNil(CoverEditorMath.spineWidthOverride(proposed: 0))
        XCTAssertNil(CoverEditorMath.spineWidthOverride(proposed: -3))
    }

    func testMeasurementWarningsFlagRegionsBelowTheirBounds() {
        let none = CoverEditorMath.measurementWarnings(
            boardWidthMM: 210,
            boardHeightMM: 297,
            minimumBoardWidthMM: 210,
            minimumBoardHeightMM: 297,
            spineWidthMM: 28.5,
            requiredSpineWidthMM: 28.5
        )
        XCTAssertTrue(none.isEmpty)

        let all = CoverEditorMath.measurementWarnings(
            boardWidthMM: 190,
            boardHeightMM: 280,
            minimumBoardWidthMM: 210,
            minimumBoardHeightMM: 297,
            spineWidthMM: 20,
            requiredSpineWidthMM: 28.5
        )
        XCTAssertEqual(all.count, 3)
        XCTAssertTrue(all[0].contains("width"))
        XCTAssertTrue(all[1].contains("height"))
        XCTAssertTrue(all[2].contains("Spine"))
    }

    func testEffectiveSpineWidthUsesOverrideAndRoundTrips() throws {
        var project = BinderyProject(title: "Dune", heightMM: 297, widthMM: 210, architecture: .caseBound)
        project.textPaperGSM = 80
        project.boardThicknessMM = 2
        project.hingeGapMM = 8

        let computed = project.effectiveSpineWidthMM(pageCount: 256)
        XCTAssertEqual(
            computed,
            BindingMath.spineWidthMM(
                architecture: .caseBound,
                pageCount: 256,
                gsm: 80,
                boardThicknessMM: 2,
                hingeGapMM: 8
            ),
            accuracy: 0.001
        )

        project.spineWidthOverrideMM = 18
        XCTAssertEqual(project.effectiveSpineWidthMM(pageCount: 256), 18, accuracy: 0.001)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let restored = try decoder.decode(BinderyProject.self, from: encoder.encode(project))
        XCTAssertEqual(restored.spineWidthOverrideMM, 18)

        project.spineWidthOverrideMM = nil
        XCTAssertEqual(project.effectiveSpineWidthMM(pageCount: 256), computed, accuracy: 0.001)
    }

    func testRotationGestureMathKeepsRelativeDelta() {
        let degrees = CoverEditorMath.rotationDegrees(
            pointerAngle: 40,
            gestureStartPointerAngle: 10,
            elementStartRotation: -20
        )
        XCTAssertEqual(degrees, 10, accuracy: 0.01)

        let wrapped = CoverEditorMath.rotationDegrees(
            pointerAngle: -170,
            gestureStartPointerAngle: 170,
            elementStartRotation: 0
        )
        XCTAssertEqual(wrapped, 20, accuracy: 0.01)
    }

    func testMeasuredTextBoundsProducePositiveBox() {
        let measured = CoverEditorMath.measuredTextSizeMM(
            text: "TITLE",
            fontSizeMM: 12,
            fontStyle: .display
        )
        XCTAssertGreaterThan(measured.width, CoverEditorMath.minimumElementSizeMM)
        XCTAssertGreaterThan(measured.height, 0)
        XCTAssertGreaterThan(measured.width, measured.height)
    }

    func testImpositionTrimDoesNotShrinkOversizedCover() {
        var project = BinderyProject(title: "Dune", heightMM: 300, widthMM: 240)
        project.applyImpositionTrim(
            widthPoints: BindingMath.points(fromMillimeters: 152),
            heightPoints: BindingMath.points(fromMillimeters: 229)
        )

        XCTAssertEqual(project.widthMM, 240, accuracy: 0.01)
        XCTAssertEqual(project.heightMM, 300, accuracy: 0.01)
    }

    func testShapeElementStrokeStylesRoundTrip() throws {
        var project = BinderyProject(title: "Dune")
        project.ensureCoverDesignLayers()
        let layerID = try XCTUnwrap(project.coverDesignLayers.first?.id)
        project.coverElements = [
            CoverDesignElement(
                kind: .shape,
                panel: .front,
                xMM: 120,
                yMM: 80,
                widthMM: 60,
                heightMM: 40,
                layer: .deboss,
                designLayerID: layerID,
                shapeType: .rectangle,
                strokeWidthMM: 1.2,
                strokeStyle: .ornament,
                ornamentPattern: .diamonds,
                stroke: .solid(.foilGold),
                fill: .solid(.debossGray)
            )
        ]

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let restored = try decoder.decode(BinderyProject.self, from: encoder.encode(project))
        let shape = try XCTUnwrap(restored.coverElements.first)
        XCTAssertEqual(shape.kind, .shape)
        XCTAssertEqual(shape.layer, .deboss)
        XCTAssertEqual(shape.strokeStyle, .ornament)
        XCTAssertEqual(shape.ornamentPattern, .diamonds)
        XCTAssertTrue(shape.isStroked)
        XCTAssertEqual(shape.stroke.solidColor, .foilGold)
        XCTAssertTrue(shape.isFilled)
        XCTAssertEqual(shape.fill.solidColor, .debossGray)
    }

    func testLegacyIsFilledAndChainStrokeDecode() throws {
        let json = """
        {
          "id": "00000000-0000-0000-0000-000000000001",
          "kind": "shape",
          "panel": "front",
          "text": "",
          "xMM": 10,
          "yMM": 10,
          "widthMM": 40,
          "heightMM": 20,
          "fontSizeMM": 4,
          "rotationDegrees": 0,
          "layer": "ink",
          "fontStyle": "body",
          "designLayerID": "00000000-0000-0000-0000-000000000002",
          "strokeStyle": "chain",
          "isFilled": true
        }
        """.data(using: .utf8)!
        let element = try JSONDecoder().decode(CoverDesignElement.self, from: json)
        XCTAssertEqual(element.strokeStyle, .ornament)
        XCTAssertEqual(element.ornamentPattern, .dashDots)
        XCTAssertTrue(element.isFilled)
        XCTAssertTrue(element.isStroked)
        XCTAssertEqual(element.stroke.solidColor, .inkBlack)
        XCTAssertEqual(element.dashLengthScale, 1)
        XCTAssertEqual(element.dashGapScale, 1)
    }

    func testDashDotStrokePatternAndScales() {
        let base = CoverOrnamentPattern.dashDots.dashPatternMM(strokeWidthMM: 1)
        XCTAssertEqual(base.count, 4)
        let stretched = CoverOrnamentPattern.dashDots.dashPatternMM(
            strokeWidthMM: 1,
            lengthScale: 2,
            gapScale: 0.5
        )
        XCTAssertEqual(stretched[0], base[0] * 2, accuracy: 0.0001)
        XCTAssertEqual(stretched[1], base[1] * 0.5, accuracy: 0.0001)
        XCTAssertTrue(CoverOrnamentPattern.dashDots.usesRoundCap)
        XCTAssertTrue(CoverStrokeStyle.ornament.drawsOrnamentMarks)
        XCTAssertTrue(CoverOrnamentPattern.dashes.allowsDashScaling)
        XCTAssertTrue(CoverOrnamentPattern.dots.drawsStamps)
    }

    func testSVGExportGroupsElementsByFinishChannel() throws {
        var project = BinderyProject(title: "Dune", author: "Frank Herbert", heightMM: 297, widthMM: 210)
        project.showFoilLayer = true
        project.showDebossLayer = true
        project.seedCoverElementsIfNeeded(spineWidthMM: 28.5)
        project.ensureCoverDesignLayers()
        let layerID = try XCTUnwrap(project.coverDesignLayers.first?.id)
        project.coverElements.append(
            CoverDesignElement(
                kind: .shape,
                panel: .front,
                xMM: 300,
                yMM: 120,
                widthMM: 50,
                heightMM: 30,
                layer: .deboss,
                designLayerID: layerID,
                shapeType: .rectangle,
                strokeStyle: .ornament,
                ornamentPattern: .dashDots
            )
        )

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cover-\(UUID().uuidString).svg")
        defer { try? FileManager.default.removeItem(at: url) }

        try CoverBlueprintService.writeSVG(
            for: project,
            pageCount: 256,
            spineWidthMM: 28.5,
            to: url
        )

        let svg = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(svg.contains("id=\"finish-foil\""))
        XCTAssertTrue(svg.contains("id=\"finish-deboss\""))
    }

    func testSVGExportContainsPanelsAndText() throws {
        var project = BinderyProject(title: "Dune", author: "Frank Herbert", heightMM: 297, widthMM: 210)
        project.showFoilLayer = true
        project.seedCoverElementsIfNeeded(spineWidthMM: 28.5)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cover-\(UUID().uuidString).svg")
        defer { try? FileManager.default.removeItem(at: url) }

        try CoverBlueprintService.writeSVG(
            for: project,
            pageCount: 256,
            spineWidthMM: 28.5,
            to: url
        )

        let svg = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(svg.contains("<svg"))
        XCTAssertTrue(svg.contains("BACK:"))
        XCTAssertTrue(svg.contains("SPINE:"))
        XCTAssertTrue(svg.contains("JOINT:"))
        XCTAssertTrue(svg.contains("FRONT:"))
        XCTAssertTrue(svg.contains("DUNE") || svg.contains("FRANK"))
    }

    func testPDFBlueprintExportWritesFile() throws {
        var project = BinderyProject(title: "Dune", author: "Frank Herbert")
        project.seedCoverElementsIfNeeded(spineWidthMM: 20)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cover-\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: url) }

        try CoverBlueprintService.writeBlueprint(
            for: project,
            pageCount: 128,
            spineWidthMM: 20,
            to: url
        )

        let data = try Data(contentsOf: url)
        XCTAssertGreaterThan(data.count, 500)
        XCTAssertTrue(String(data: data.prefix(5), encoding: .ascii)?.hasPrefix("%PDF") == true)
    }
}
