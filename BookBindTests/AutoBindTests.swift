import XCTest
@testable import BookBind

@MainActor
final class AutoBindTests: XCTestCase {
    /// Polls the main actor until `condition` holds or the timeout passes.
    private func waitUntil(timeout: TimeInterval = 10, _ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    func testEditsBindAutomaticallyAndExportWaitsForCurrentPreview() async {
        let workspace = BindingWorkspace()
        XCTAssertFalse(workspace.canExport)

        workspace.addBlankPages(count: 8)
        XCTAssertTrue(workspace.isPreviewStale, "an edit marks the preview stale immediately")
        XCTAssertFalse(workspace.canExport)

        await waitUntil { workspace.canExport }
        XCTAssertNotNil(workspace.previewDocument)
        XCTAssertFalse(workspace.isPreviewStale)

        // A further edit keeps the old preview visible but blocks export until it re-binds.
        let previous = workspace.previewDocument
        workspace.addBlankPages(count: 8)
        XCTAssertTrue(workspace.previewDocument === previous)
        XCTAssertFalse(workspace.canExport)

        await waitUntil { workspace.canExport }
        XCTAssertFalse(workspace.previewDocument === previous)
    }

    func testRapidEditsCoalesceIntoOneCurrentResult() async {
        let workspace = BindingWorkspace()
        for _ in 0..<5 {
            workspace.addBlankPage()
        }
        await waitUntil { workspace.canExport }
        XCTAssertEqual(workspace.assembledPageCount, 5)
        XCTAssertFalse(workspace.isWorking)
        XCTAssertNotNil(workspace.previewDocument)
    }

    func testRemovingAllPagesClearsPreview() async {
        let workspace = BindingWorkspace()
        workspace.addBlankPages(count: 4)
        await waitUntil { workspace.canExport }

        workspace.bookBlockItems.removeAll()
        workspace.refreshPlan()

        XCTAssertNil(workspace.previewDocument)
        XCTAssertFalse(workspace.isPreviewStale)
        XCTAssertFalse(workspace.canExport)
    }
}
