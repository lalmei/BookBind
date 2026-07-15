import Foundation

struct PersistedProjectRecord: Equatable, Codable {
    var project: BinderyProject
    var workspace: BindingWorkspaceState
}

struct PersistedAppState: Equatable, Codable {
    var projects: [PersistedProjectRecord] = []
    var libraries: [AssetLibrary] = []
}

enum ProjectStoreError: LocalizedError {
    case cannotCreateDirectory(URL)

    var errorDescription: String? {
        switch self {
        case .cannotCreateDirectory(let url):
            return "Could not create BookBind data directory at \(url.path)."
        }
    }
}

/// Local-only persistence for masterworks and per-project workbench state.
struct ProjectStore {
    var fileURL: URL

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
                .first ?? FileManager.default.temporaryDirectory
            self.fileURL = base
                .appendingPathComponent("BookBind", isDirectory: true)
                .appendingPathComponent("app-state.json")
        }
    }

    func load() -> PersistedAppState {
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL) else {
            return PersistedAppState()
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(PersistedAppState.self, from: data)) ?? PersistedAppState()
    }

    func save(_ state: PersistedAppState) throws {
        let directory = fileURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            throw ProjectStoreError.cannotCreateDirectory(directory)
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(state)
        try data.write(to: fileURL, options: [.atomic])
    }
}
