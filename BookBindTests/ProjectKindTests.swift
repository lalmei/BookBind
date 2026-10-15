import XCTest
@testable import BookBind

@MainActor
final class ProjectKindTests: XCTestCase {
    func testEveryKindBelongsToExactlyOneGroup() {
        let grouped = ProjectKind.Group.allCases.flatMap { ProjectKind.kinds(in: $0) }
        XCTAssertEqual(Set(grouped), Set(ProjectKind.allCases))
        XCTAssertEqual(grouped.count, ProjectKind.allCases.count)
    }

    func testFoldPageSizesComeFromLandscapeStock() {
        let zine = ProjectKind.miniZine8.pageSize(fromStock: .letter)
        XCTAssertEqual(zine.width, 279.4 / 4, accuracy: 0.001)
        XCTAssertEqual(zine.height, 215.9 / 2, accuracy: 0.001)

        let booklet = ProjectKind.halfFoldBooklet.pageSize(fromStock: .a4)
        XCTAssertEqual(booklet.width, 148.5, accuracy: 0.001)
        XCTAssertEqual(booklet.height, 210, accuracy: 0.001)
    }

    func testBooksUnlockAllToolsAndFoldsStayFocused() {
        XCTAssertEqual(ProjectKind.caseBound.enabledTools, Set(ProjectTool.allCases))
        XCTAssertNil(ProjectKind.caseBound.scheme)
        XCTAssertEqual(ProjectKind.accordion.enabledTools, [.imposition, .materials])
        XCTAssertEqual(ProjectKind.accordion.scheme, .accordion)
    }

    func testCreatingAZineConfiguresStockAndScheme() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("app-state.json")
        let store = AppStore(projectStore: ProjectStore(fileURL: url))

        store.createProject(NewProjectRequest(
            title: "Pocket Zine",
            author: "",
            kind: .miniZine8,
            widthMM: 0,
            heightMM: 0,
            stock: .a4
        ))

        let project = try XCTUnwrap(store.selectedProject)
        XCTAssertEqual(project.title, "Pocket Zine")
        XCTAssertEqual(project.architecture, .saddleStitch)
        XCTAssertEqual(project.widthMM, 297 / 4, accuracy: 0.01)
        XCTAssertEqual(store.projectTool, .imposition)

        let job = store.workspace(for: project.id).job
        XCTAssertEqual(job.impositionScheme, .miniZine8)
        XCTAssertEqual(Double(job.customPageWidth), Double(BindingMath.points(fromMillimeters: 297)), accuracy: 0.01)
        XCTAssertEqual(Double(job.customPageHeight), Double(BindingMath.points(fromMillimeters: 210)), accuracy: 0.01)
    }

    func testCreatingABookKeepsTypedTrim() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("app-state.json")
        let store = AppStore(projectStore: ProjectStore(fileURL: url))

        store.createProject(NewProjectRequest(
            title: "Field Notes",
            author: "A. Binder",
            kind: .coptic,
            widthMM: 120,
            heightMM: 180,
            stock: .letter
        ))

        let project = try XCTUnwrap(store.selectedProject)
        XCTAssertEqual(project.architecture, .coptic)
        XCTAssertEqual(project.widthMM, 120)
        XCTAssertEqual(project.heightMM, 180)
        XCTAssertEqual(project.enabledTools, Set(ProjectTool.allCases))
        XCTAssertEqual(store.workspace(for: project.id).job.impositionScheme, .folioSignatures)
    }
}
