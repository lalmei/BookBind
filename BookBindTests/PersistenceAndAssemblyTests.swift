import PDFKit
import XCTest
@testable import BookBind

final class PersistenceAndAssemblyTests: XCTestCase {
    @MainActor
    func testQuickWorkCreatesScratchProjectAndOpensTool() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("app-state.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let store = AppStore(projectStore: ProjectStore(fileURL: url))
        XCTAssertTrue(store.projects.isEmpty)

        store.startQuickWork(.imposition)
        XCTAssertEqual(store.projects.count, 1)
        XCTAssertTrue(store.projects[0].title.hasPrefix("Signature "))
        XCTAssertEqual(store.projectTool, .imposition)
        XCTAssertEqual(store.projects[0].enabledTools, [.imposition])
        XCTAssertFalse(store.projects[0].allows(.cover))
        XCTAssertFalse(store.projects[0].allows(.materials))
        if case let .project(id) = store.selection {
            XCTAssertEqual(id, store.projects[0].id)
        } else {
            XCTFail("Expected project selection")
        }

        store.startQuickWork(.cover)
        XCTAssertEqual(store.projects.count, 2)
        XCTAssertTrue(store.projects[0].title.hasPrefix("Cover "))
        XCTAssertEqual(store.projectTool, .cover)
        XCTAssertEqual(store.projects[0].enabledTools, [.cover])
        XCTAssertFalse(store.projects[0].allows(.imposition))

        store.createMasterwork(
            title: "Full Atlas",
            author: "Bindery",
            heightMM: 229,
            widthMM: 152,
            architecture: .caseBound
        )
        XCTAssertEqual(store.projects.count, 3)
        XCTAssertTrue(store.projects[0].isFullMasterwork)
        XCTAssertEqual(store.projectTool, .imposition)
        XCTAssertTrue(store.projects[0].allows(.cover))
        XCTAssertTrue(store.projects[0].allows(.materials))

        // Re-open a cover-only scratch — land on Cover, not Imposition.
        let coverOnlyID = store.projects[1].id
        store.openProject(coverOnlyID)
        XCTAssertEqual(store.projectTool, .cover)

        store.enableTool(.materials)
        XCTAssertTrue(store.projects[1].allows(.materials))
        XCTAssertTrue(store.projects[1].allows(.cover))
        XCTAssertFalse(store.projects[1].allows(.imposition))
        XCTAssertEqual(store.projectTool, .materials)
    }

    @MainActor
    func testCreateMasterworkSeedsImpositionTrimFromBoardSize() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("app-state.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let store = AppStore(projectStore: ProjectStore(fileURL: url))
        store.createMasterwork(
            title: "Sized Atlas",
            author: "",
            heightMM: 210,
            widthMM: 148,
            architecture: .saddleStitch
        )

        let project = store.projects[0]
        let job = store.workspace(for: project.id).job
        XCTAssertEqual(job.paperSize, .a5)
        XCTAssertEqual(job.bindingStyle, .saddleStitch)
    }

    @MainActor
    func testUnlockImpositionSeedsPaperFromCoverTrim() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("app-state.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let store = AppStore(projectStore: ProjectStore(fileURL: url))
        store.createMasterwork(
            title: "Cover First",
            author: "",
            heightMM: 229,
            widthMM: 152,
            architecture: .caseBound,
            enabledTools: [.cover],
            initialTool: .cover
        )
        store.enableTool(.imposition)

        let project = store.projects[0]
        let job = store.workspace(for: project.id).job
        XCTAssertTrue(project.allows(.imposition))
        XCTAssertEqual(job.paperSize, .custom)
        let trim = try XCTUnwrap(job.resolvedTrimSize)
        XCTAssertEqual(BindingMath.millimeters(fromPoints: trim.width), 152, accuracy: 0.05)
        XCTAssertEqual(BindingMath.millimeters(fromPoints: trim.height), 229, accuracy: 0.05)
    }

    @MainActor
    func testBindingStyleChangeSyncsProjectArchitecture() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("app-state.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let store = AppStore(projectStore: ProjectStore(fileURL: url))
        store.startQuickWork(.imposition)
        let projectID = try XCTUnwrap(store.projects.first?.id)

        store.workspace(for: projectID).job.bindingStyle = .perfectBound
        store.syncProjectArchitectureFromImposition(projectID: projectID)

        XCTAssertEqual(store.projects.first?.architecture, .perfectBound)
    }

    @MainActor
    func testCreateMasterworkAppliesArchitectureCoverDefaults() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("app-state.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let store = AppStore(projectStore: ProjectStore(fileURL: url))
        store.createMasterwork(
            title: "Perfect",
            author: "",
            heightMM: 229,
            widthMM: 152,
            architecture: .perfectBound
        )

        let project = store.projects[0]
        XCTAssertEqual(project.boardThicknessMM, 0.35, accuracy: 0.001)
        XCTAssertEqual(project.hingeGapMM, 0, accuracy: 0.001)
        XCTAssertEqual(store.workspace(for: project.id).job.bindingStyle, .perfectBound)
    }

    @MainActor
    func testUnlockCoverSeedsBoardFromImpositionPaper() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("app-state.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let store = AppStore(projectStore: ProjectStore(fileURL: url))
        store.startQuickWork(.imposition)
        let projectID = store.projects[0].id
        store.workspace(for: projectID).job.paperSize = .letter
        store.enableTool(.cover)

        let project = store.projects[0]
        XCTAssertTrue(project.allows(.cover))
        XCTAssertEqual(project.widthMM, BindingMath.millimeters(fromPoints: 612), accuracy: 0.15)
        XCTAssertEqual(project.heightMM, BindingMath.millimeters(fromPoints: 792), accuracy: 0.15)
    }

    func testLegacyProjectsDecodeWithAllToolsEnabled() throws {
        let json = """
        {
          "id": "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
          "title": "Legacy Book",
          "author": "",
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
        let data = Data(json.utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let project = try decoder.decode(BinderyProject.self, from: data)
        XCTAssertTrue(project.isFullMasterwork)
        XCTAssertEqual(project.enabledTools, Set(ProjectTool.allCases))
    }

    func testProjectStoreRoundTripsProjectAndWorkspace() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("app-state.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let project = BinderyProject(title: "Dune", author: "Frank Herbert")
        var workspace = BindingWorkspaceState()
        workspace.job.creepPoints = 4
        workspace.bookBlockItems = [.blank()]

        let store = ProjectStore(fileURL: url)
        try store.save(PersistedAppState(projects: [
            PersistedProjectRecord(project: project, workspace: workspace)
        ]))

        let restored = store.load()
        XCTAssertEqual(restored.projects.count, 1)
        XCTAssertEqual(restored.projects[0].project.title, "Dune")
        XCTAssertEqual(restored.projects[0].workspace.job.creepPoints, 4)
        XCTAssertEqual(restored.projects[0].workspace.bookBlockItems.first?.kind, .blank)
    }

    func testAssemblyAddsBlankAndSourceRangeInOrder() throws {
        let pdfURL = try writeTestPDF(pageCount: 3)
        defer { try? FileManager.default.removeItem(at: pdfURL) }

        let (source, _) = try PDFDocumentService.load(url: pdfURL)
        let items: [BookBlockItem] = [
            .blank(label: "Opening blank"),
            BookBlockItem(
                kind: .sourceRange,
                sourceID: source.id,
                pageRange: 1...2,
                label: source.name
            )
        ]

        let assembled = try PDFDocumentService.assembleContent(
            items: items,
            sources: [source],
            targetPageSize: CGSize(width: 300, height: 400),
            normalizeOrientation: false
        )

        XCTAssertEqual(assembled.pageCount, 3)
    }

    func testColoredEndpaperAddsPages() throws {
        let source = PDFDocument()
        PDFDocumentService.appendBlankPage(to: source, size: CGSize(width: 200, height: 300))

        let block = PDFDocumentService.buildBookBlock(
            from: source,
            frontEndpapers: 1,
            backEndpapers: 1,
            padPages: 0,
            targetPageSize: CGSize(width: 200, height: 300),
            normalizeOrientation: false,
            frontEndpaperColor: .sage,
            backEndpaperColor: .mistBlue
        )

        XCTAssertEqual(block.pageCount, 3)
    }

    private func writeTestPDF(pageCount: Int) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("pdf")
        let data = NSMutableData()
        var mediaBox = CGRect(x: 0, y: 0, width: 200, height: 300)
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw BindingError.exportFailed
        }
        for index in 0..<pageCount {
            context.beginPage(mediaBox: &mediaBox)
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(mediaBox)
            context.setFillColor(CGColor(gray: 0, alpha: 1))
            context.fill(CGRect(x: 30 + index * 5, y: 40, width: 40, height: 40))
            context.endPage()
        }
        context.closePDF()
        try (data as Data).write(to: url)
        return url
    }
}
