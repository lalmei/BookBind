import Foundation

enum AssetLibraryItemKind: String, Codable, Hashable {
    case image
    case pdf
}

struct AssetLibraryItem: Identifiable, Hashable {
    var id: URL { url }
    var url: URL
    var name: String
    var kind: AssetLibraryItemKind
    var modifiedAt: Date?
}

struct AssetLibraryService {
    var fileManager: FileManager
    var appSupportBaseURL: URL?
    var documentsURL: URL?

    private let supportedExtensions: [String: AssetLibraryItemKind] = [
        "pdf": .pdf,
        "png": .image,
        "jpg": .image,
        "jpeg": .image,
        "heic": .image,
        "tif": .image,
        "tiff": .image,
        "gif": .image
    ]

    init(
        fileManager: FileManager = .default,
        appSupportBaseURL: URL? = nil,
        documentsURL: URL? = nil
    ) {
        self.fileManager = fileManager
        self.appSupportBaseURL = appSupportBaseURL
        self.documentsURL = documentsURL
    }

    func discoveredLibraries(persisted: [AssetLibrary]) throws -> [AssetLibrary] {
        var libraries: [AssetLibrary] = []
        libraries.append(try appOwnedLibrary())

        if let documentsLibrary = documentsBookBindLibrary(),
           !containsLibrary(in: libraries, matching: documentsLibrary) {
            libraries.append(documentsLibrary)
        }

        for library in persisted where !library.isCloudStub {
            if !containsLibrary(in: libraries, matching: library) {
                libraries.append(library)
            }
        }

        return libraries
    }

    func cloudStubs() -> [AssetLibrary] {
        CloudAssetProvider.allCases.map { provider in
            AssetLibrary(
                id: UUID(uuidString: "00000000-0000-0000-0000-\(provider.stableSuffix)") ?? UUID(),
                name: provider.rawValue,
                kind: .cloudStub(provider),
                pathHint: "Connect \(provider.rawValue)",
                isAutoLinked: true
            )
        }
    }

    func library(fromFolder url: URL) -> AssetLibrary {
        let bookmark = try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        return AssetLibrary(
            name: url.lastPathComponent,
            kind: .localFolder,
            bookmarkData: bookmark,
            pathHint: url.path,
            isAutoLinked: false
        )
    }

    func resolvedURL(for library: AssetLibrary) -> URL? {
        guard !library.isCloudStub else { return nil }
        if let bookmarkData = library.bookmarkData {
            var isStale = false
            if let resolved = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                return resolved
            }
        }
        guard let pathHint = library.pathHint else { return nil }
        return URL(fileURLWithPath: NSString(string: pathHint).expandingTildeInPath)
    }

    func enumerateItems(in library: AssetLibrary) -> [AssetLibraryItem] {
        guard let url = resolvedURL(for: library) else { return [] }
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        guard let urls = try? fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return urls.compactMap { itemURL in
            let fileExtension = itemURL.pathExtension.lowercased()
            guard let kind = supportedExtensions[fileExtension] else { return nil }
            let values = try? itemURL.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
            if values?.isRegularFile == false { return nil }
            return AssetLibraryItem(
                url: itemURL,
                name: itemURL.lastPathComponent,
                kind: kind,
                modifiedAt: values?.contentModificationDate
            )
        }
        .sorted { lhs, rhs in
            lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    func isAvailable(_ library: AssetLibrary) -> Bool {
        guard let url = resolvedURL(for: library) else { return false }
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    private func appOwnedLibrary() throws -> AssetLibrary {
        let url = appAssetsDirectory()
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return AssetLibrary(
            name: "BookBind Assets",
            kind: .localFolder,
            pathHint: url.path,
            isAutoLinked: true
        )
    }

    private func documentsBookBindLibrary() -> AssetLibrary? {
        guard let documentsURL = documentsURL ?? fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        let url = documentsURL.appendingPathComponent("BookBind Assets", isDirectory: true)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue,
              fileManager.isReadableFile(atPath: url.path) else {
            return nil
        }
        return AssetLibrary(
            name: "BookBind Assets",
            kind: .localFolder,
            pathHint: url.path,
            isAutoLinked: true
        )
    }

    private func appAssetsDirectory() -> URL {
        let base = appSupportBaseURL
            ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return base
            .appendingPathComponent("BookBind", isDirectory: true)
            .appendingPathComponent("Assets", isDirectory: true)
    }

    private func containsLibrary(in libraries: [AssetLibrary], matching candidate: AssetLibrary) -> Bool {
        guard let candidatePath = normalizedPath(for: candidate) else {
            return libraries.contains { $0.id == candidate.id }
        }
        return libraries.contains { normalizedPath(for: $0) == candidatePath }
    }

    private func normalizedPath(for library: AssetLibrary) -> String? {
        resolvedURL(for: library)?.standardizedFileURL.path
    }
}

private extension CloudAssetProvider {
    var stableSuffix: String {
        switch self {
        case .iCloudDrive: return "000000000001"
        case .dropbox: return "000000000002"
        }
    }
}
