import XCTest
@testable import BookBind

final class PreflightServiceTests: XCTestCase {
    private let layerID = UUID()

    private func input(
        project: BinderyProject = BinderyProject(title: "Test"),
        job: BindingJob = BindingJob(),
        sources: [SourceDocument] = [],
        pages: Int = 64
    ) -> PreflightService.Input {
        PreflightService.Input(
            project: project,
            job: job,
            sources: sources,
            assembledPageCount: pages,
            plan: pages > 0 ? ImpositionService.plan(contentPageCount: pages, job: job) : nil
        )
    }

    private func run(_ input: PreflightService.Input, pixels: CGSize? = nil, exists: Bool = true) -> [PreflightIssue] {
        PreflightService.run(input, imageSize: { _ in pixels }, fileExists: { _ in exists })
    }

    private func source(_ name: String, _ size: CGSize) -> SourceDocument {
        SourceDocument(id: UUID(), url: URL(fileURLWithPath: "/tmp/\(name)"), name: name, pageCount: 8, pageSize: size, bookmarkData: nil)
    }

    private func imageElement(widthMM: Double, heightMM: Double) -> CoverDesignElement {
        CoverDesignElement(
            kind: .image, panel: .front, xMM: 10, yMM: 10, widthMM: widthMM, heightMM: heightMM,
            designLayerID: layerID, imagePathHint: "/tmp/art.png", imageName: "art.png"
        )
    }

    func testEmptyProjectOnlySaysAddPages() {
        let issues = run(input(pages: 0))
        XCTAssertEqual(issues.map(\.id), ["no-pages"])
        XCTAssertEqual(issues.first?.severity, .info)
    }

    func testThickSignaturesWithoutCreepOfferTheCalculatedFix() throws {
        var job = BindingJob()
        job.creepPoints = 0
        let issue = try XCTUnwrap(run(input(job: job)).first { $0.id == "creep" })
        XCTAssertEqual(issue.severity, .warning)
        guard case .applyCreep(let points) = issue.fix else { return XCTFail("expected creep fix") }
        XCTAssertGreaterThan(points, 0)

        job.creepPoints = 1
        XCTAssertNil(run(input(job: job)).first { $0.id == "creep" })
    }

    func testBleedWithoutCropMarksOffersToTurnThemOn() {
        var job = BindingJob()
        job.bleedPoints = 9
        job.addCropMarks = false
        XCTAssertEqual(run(input(job: job)).first { $0.id == "bleed-no-marks" }?.fix, .enableCropMarks)
        job.addCropMarks = true
        XCTAssertNil(run(input(job: job)).first { $0.id == "bleed-no-marks" })
    }

    func testMixedSourceSizesAndMissingFilesAreFlagged() {
        let sources = [source("a.pdf", CGSize(width: 432, height: 648)), source("b.pdf", CGSize(width: 612, height: 792))]
        let ids = run(input(sources: sources), exists: false).map(\.id)
        XCTAssertTrue(ids.contains("mixed-sizes"))
        XCTAssertEqual(ids.filter { $0.hasPrefix("source-missing") }.count, 2)
        XCTAssertEqual(run(input(sources: sources), exists: false).first?.severity, .error, "errors sort first")
    }

    func testCoverImageResolutionThresholds() {
        var project = BinderyProject(title: "Test", enabledTools: [.cover])
        // 100 mm wide ≈ 3.94 in.
        project.coverElements = [imageElement(widthMM: 100, heightMM: 100)]

        let soft = run(input(project: project), pixels: CGSize(width: 400, height: 400))
        XCTAssertEqual(soft.first?.severity, .error)
        XCTAssertTrue(soft.first?.title.contains("102 ppi") ?? false, soft.first?.title ?? "")

        let okay = run(input(project: project), pixels: CGSize(width: 900, height: 900))
        XCTAssertEqual(okay.first?.severity, .warning)

        XCTAssertTrue(run(input(project: project), pixels: CGSize(width: 1300, height: 1300)).isEmpty)
        XCTAssertEqual(run(input(project: project), exists: false).first?.severity, .error)
    }

    func testCoverSmallerThanImpositionTrim() {
        var project = BinderyProject(title: "Test", heightMM: 200, widthMM: 120, enabledTools: [.cover, .imposition])
        project.widthMM = 120
        var job = BindingJob()
        job.paperSize = .custom
        job.customPageWidth = BindingMath.points(fromMillimeters: 148)
        job.customPageHeight = BindingMath.points(fromMillimeters: 210)
        job.creepPoints = 1
        let issue = run(input(project: project, job: job)).first { $0.id == "cover-smaller-than-block" }
        XCTAssertEqual(issue?.fix, .matchCoverToTrim)
    }

    func testEffectivePPI() {
        XCTAssertEqual(PreflightService.effectivePPI(pixels: CGSize(width: 1200, height: 3000), widthMM: 101.6, heightMM: 101.6), 300)
        XCTAssertNil(PreflightService.effectivePPI(pixels: .zero, widthMM: 10, heightMM: 10))
    }
}
