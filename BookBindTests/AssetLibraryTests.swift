import XCTest
@testable import BookBind

final class AssetLibraryTests: XCTestCase {
    func testAutoLinksAppOwnedAssetsFolder() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let service = AssetLibraryService(appSupportBaseURL: root)
        let libraries = try service.discoveredLibraries(persisted: [])

        XCTAssertEqual(libraries.first?.name, "InABind Assets")
        XCTAssertEqual(libraries.first?.isAutoLinked, true)
        let expectedFolder = root
            .appendingPathComponent("BookBind", isDirectory: true)
            .appendingPathComponent("Assets", isDirectory: true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: expectedFolder.path))
    }

    func testDiscoveredLibrariesDedupesPersistedFolderByPath() throws {
        let root = temporaryDirectory()
        let folder = root
            .appendingPathComponent("BookBind", isDirectory: true)
            .appendingPathComponent("Assets", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let persisted = AssetLibrary(
            name: "Duplicate",
            pathHint: folder.path,
            isAutoLinked: false
        )
        let service = AssetLibraryService(appSupportBaseURL: root)
        let libraries = try service.discoveredLibraries(persisted: [persisted])

        XCTAssertEqual(libraries.filter { $0.pathHint == folder.path }.count, 1)
    }

    func testEnumerateItemsFiltersToPDFsAndImages() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("pdf".utf8).write(to: root.appendingPathComponent("cover.pdf"))
        try Data("image".utf8).write(to: root.appendingPathComponent("endpaper.PNG"))
        try Data("notes".utf8).write(to: root.appendingPathComponent("notes.txt"))

        let service = AssetLibraryService(appSupportBaseURL: temporaryDirectory())
        let library = AssetLibrary(name: "Test", pathHint: root.path)
        let items = service.enumerateItems(in: library)

        XCTAssertEqual(items.map(\.name), ["cover.pdf", "endpaper.PNG"])
        XCTAssertEqual(items.map(\.kind), [.pdf, .image])
    }

    func testProjectStoreRoundTripsLibraries() throws {
        let url = temporaryDirectory().appendingPathComponent("app-state.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let library = AssetLibrary(name: "Paper Scans", pathHint: "/tmp/Paper Scans")
        let store = ProjectStore(fileURL: url)
        try store.save(PersistedAppState(projects: [], libraries: [library]))

        let restored = store.load()
        XCTAssertEqual(restored.libraries, [library])
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }
}
