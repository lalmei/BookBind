import AppKit
import Foundation
import UniformTypeIdentifiers

/// App-wide colour palette shown in every paint well; persists across launches and
/// imports / exports Adobe Swatch Exchange (`.ase`) files.
@MainActor
final class SwatchStore: ObservableObject {
    static let shared = SwatchStore()

    @Published private(set) var swatches: [Swatch] = []

    private let defaults: UserDefaults
    private let key = "swatchPalette"

    /// Starter palette: classic book cloths, paper, and foil.
    static let starter: [Swatch] = [
        Swatch(name: "Oxblood cloth", color: CodableColor(red: 0.42, green: 0.12, blue: 0.13)),
        Swatch(name: "Navy cloth", color: CodableColor(red: 0.12, green: 0.18, blue: 0.32)),
        Swatch(name: "Forest cloth", color: CodableColor(red: 0.16, green: 0.30, blue: 0.22)),
        Swatch(name: "Natural linen", color: CodableColor(red: 0.85, green: 0.80, blue: 0.70)),
        Swatch(name: "Cream paper", color: CodableColor(red: 0.96, green: 0.93, blue: 0.85)),
        Swatch(name: "Gold foil", color: CodableColor(red: 0.83, green: 0.67, blue: 0.29)),
        Swatch(name: "Black", color: CodableColor(red: 0.08, green: 0.08, blue: 0.09))
    ]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key),
           let stored = try? JSONDecoder().decode([Swatch].self, from: data) {
            swatches = stored
        } else {
            swatches = Self.starter
        }
    }

    func add(_ color: CodableColor, name: String? = nil) {
        guard !contains(color) else { return }
        swatches.append(Swatch(name: name ?? "Swatch \(swatches.count + 1)", color: color))
        persist()
    }

    func remove(_ swatch: Swatch) {
        swatches.removeAll { $0.id == swatch.id }
        persist()
    }

    /// Appends swatches from `.ase` data, skipping colours already in the palette.
    @discardableResult
    func importASE(_ data: Data) throws -> Int {
        let incoming = try ASESwatchFile.read(data)
        var added = 0
        for swatch in incoming where !contains(swatch.color) {
            swatches.append(swatch)
            added += 1
        }
        persist()
        return added
    }

    func exportASE() -> Data {
        ASESwatchFile.write(swatches, groupName: "InABind")
    }

    /// `.ase` stores float32 components, so compare within half an 8-bit step, not exactly.
    func contains(_ color: CodableColor) -> Bool {
        swatches.contains { Self.isSame($0.color, color) }
    }

    static func isSame(_ a: CodableColor, _ b: CodableColor) -> Bool {
        let tolerance = 0.5 / 255
        return abs(a.red - b.red) < tolerance
            && abs(a.green - b.green) < tolerance
            && abs(a.blue - b.blue) < tolerance
            && abs(a.opacity - b.opacity) < tolerance
    }

    // MARK: - Panels

    func runImportPanel() {
        let panel = NSOpenPanel()
        panel.title = "Import Swatches"
        panel.message = "Choose an Adobe Swatch Exchange (.ase) file."
        panel.allowedContentTypes = [UTType(filenameExtension: "ase") ?? .data]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            try importASE(Data(contentsOf: url))
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    func runExportPanel() {
        let panel = NSSavePanel()
        panel.title = "Export Swatches"
        panel.nameFieldStringValue = "InABind Swatches.ase"
        panel.allowedContentTypes = [UTType(filenameExtension: "ase") ?? .data]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try exportASE().write(to: url, options: .atomic)
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(swatches) {
            defaults.set(data, forKey: key)
        }
    }
}
