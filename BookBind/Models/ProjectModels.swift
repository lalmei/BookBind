import CoreGraphics
import Foundation

/// Binding structure chosen when creating a masterwork.
enum BindingArchitecture: String, CaseIterable, Identifiable, Codable {
    case caseBound = "Case Bound"
    case coptic = "Coptic"
    case perfectBound = "Perfect Bound"
    case saddleStitch = "Saddle-stitch"
    case sectionSewn = "Section-sewn"

    var id: String { rawValue }

    var help: String {
        switch self {
        case .caseBound:
            return "Hard covers, boards, and a wrapped spine — the standard cloth or leather case."
        case .coptic:
            return "Exposed spine sewing with visible chain stitches; lays flat."
        case .perfectBound:
            return "Adhesive-bound book block with a flexible spine wrap."
        case .saddleStitch:
            return "Single nested signature, stapled or stitched through the fold."
        case .sectionSewn:
            return "Multiple sewn signatures — typical for durable hardbacks."
        }
    }
}

/// A cover/spine material option for the designer.
enum CoverMaterial: String, CaseIterable, Identifiable, Codable {
    case moroccanGoat = "Moroccan Goat Leather"
    case bookram = "Bookram"
    case buckram = "Buckram"
    case bookCloth = "Book Cloth"
    case paper = "Decorative Paper"

    var id: String { rawValue }
}

/// Panel on the flat cover wrap (outside-up).
/// Order: back board · back joint · spine · front joint · front board.
enum CoverPanel: String, CaseIterable, Identifiable, Codable, Hashable {
    case back
    case backHinge
    case spine
    case frontHinge
    case front

    var id: String { rawValue }

    var title: String {
        switch self {
        case .back: return "Back"
        case .backHinge: return "Back joint"
        case .spine: return "Spine"
        case .frontHinge: return "Front joint"
        case .front: return "Front"
        }
    }

    /// Short caption for the canvas ruler under each band.
    var canvasLabel: String {
        switch self {
        case .back: return "Back"
        case .backHinge: return "Joint"
        case .spine: return "Spine"
        case .frontHinge: return "Joint"
        case .front: return "Front"
        }
    }

    /// Prefer upright type on boards; rotate into the narrow spine / joints.
    var prefersVerticalText: Bool {
        switch self {
        case .spine, .backHinge, .frontHinge: return true
        case .back, .front: return false
        }
    }
}

/// Finish / die channel for cover artwork.
enum CoverElementLayer: String, CaseIterable, Identifiable, Codable, Hashable {
    case ink
    case foil
    case deboss

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ink: return "Ink"
        case .foil: return "Foil"
        case .deboss: return "Deboss"
        }
    }
}

enum CoverFontStyle: String, CaseIterable, Identifiable, Codable, Hashable {
    case display
    case subtitle
    case body

    var id: String { rawValue }

    var title: String {
        switch self {
        case .display: return "Display"
        case .subtitle: return "Subtitle"
        case .body: return "Body"
        }
    }

    /// Default letter height in millimeters for new stamps.
    var defaultSizeMM: Double {
        switch self {
        case .display: return 14
        case .subtitle: return 5
        case .body: return 4
        }
    }
}

enum CoverElementKind: String, CaseIterable, Identifiable, Codable, Hashable {
    case text
    case image

    var id: String { rawValue }

    var title: String {
        switch self {
        case .text: return "Text"
        case .image: return "Image"
        }
    }
}

/// Named stack layer in the cover editor (visibility / ordering group).
struct CoverDesignLayer: Identifiable, Equatable, Codable, Hashable {
    var id: UUID
    var name: String
    var isVisible: Bool
    var zIndex: Int

    init(id: UUID = UUID(), name: String, isVisible: Bool = true, zIndex: Int = 0) {
        self.id = id
        self.name = name
        self.isVisible = isVisible
        self.zIndex = zIndex
    }

    static func defaults() -> [CoverDesignLayer] {
        [
            CoverDesignLayer(name: "Artwork", zIndex: 0),
            CoverDesignLayer(name: "Typography", zIndex: 1),
            CoverDesignLayer(name: "Finishing", zIndex: 2)
        ]
    }
}

/// Placed cover-wrap element (text stamp or image).
struct CoverDesignElement: Identifiable, Equatable, Codable, Hashable {
    var id: UUID
    var kind: CoverElementKind
    /// Nearest / export panel hint (guides & individual-panel printing).
    var panel: CoverPanel
    var text: String
    /// Position in mm. With `usesWrapCoordinates`, from the wrap’s top-left
    /// (back board left edge); otherwise legacy panel-local.
    var xMM: Double
    var yMM: Double
    /// Image (or optional text frame) size in mm — may span the full wrap.
    var widthMM: Double
    var heightMM: Double
    var fontSizeMM: Double
    var rotationDegrees: Double
    var layer: CoverElementLayer
    var fontStyle: CoverFontStyle
    var designLayerID: UUID
    var opacity: Double
    var isVisible: Bool
    /// Coordinates are absolute across the back→front wrap.
    var usesWrapCoordinates: Bool
    /// When true, drag/placement clamps to `panel`. When false, free across the full wrap.
    var isPanelLocked: Bool
    var imageBookmarkData: Data?
    var imagePathHint: String?
    var imageName: String

    init(
        id: UUID = UUID(),
        kind: CoverElementKind = .text,
        panel: CoverPanel,
        text: String = "",
        xMM: Double,
        yMM: Double,
        widthMM: Double = 0,
        heightMM: Double = 0,
        fontSizeMM: Double = CoverFontStyle.body.defaultSizeMM,
        rotationDegrees: Double = 0,
        layer: CoverElementLayer = .ink,
        fontStyle: CoverFontStyle = .body,
        designLayerID: UUID,
        opacity: Double = 1,
        isVisible: Bool = true,
        usesWrapCoordinates: Bool = true,
        isPanelLocked: Bool = false,
        imageBookmarkData: Data? = nil,
        imagePathHint: String? = nil,
        imageName: String = ""
    ) {
        self.id = id
        self.kind = kind
        self.panel = panel
        self.text = text
        self.xMM = xMM
        self.yMM = yMM
        self.widthMM = widthMM
        self.heightMM = heightMM
        self.fontSizeMM = fontSizeMM
        self.rotationDegrees = rotationDegrees
        self.layer = layer
        self.fontStyle = fontStyle
        self.designLayerID = designLayerID
        self.opacity = opacity
        self.isVisible = isVisible
        self.usesWrapCoordinates = usesWrapCoordinates
        self.isPanelLocked = isPanelLocked
        self.imageBookmarkData = imageBookmarkData
        self.imagePathHint = imagePathHint
        self.imageName = imageName
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        kind = try container.decodeIfPresent(CoverElementKind.self, forKey: .kind) ?? .text
        panel = try container.decode(CoverPanel.self, forKey: .panel)
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        xMM = try container.decode(Double.self, forKey: .xMM)
        yMM = try container.decode(Double.self, forKey: .yMM)
        widthMM = try container.decodeIfPresent(Double.self, forKey: .widthMM) ?? 0
        heightMM = try container.decodeIfPresent(Double.self, forKey: .heightMM) ?? 0
        fontSizeMM = try container.decodeIfPresent(Double.self, forKey: .fontSizeMM) ?? CoverFontStyle.body.defaultSizeMM
        rotationDegrees = try container.decodeIfPresent(Double.self, forKey: .rotationDegrees) ?? 0
        layer = try container.decodeIfPresent(CoverElementLayer.self, forKey: .layer) ?? .ink
        fontStyle = try container.decodeIfPresent(CoverFontStyle.self, forKey: .fontStyle) ?? .body
        designLayerID = try container.decodeIfPresent(UUID.self, forKey: .designLayerID) ?? UUID()
        opacity = try container.decodeIfPresent(Double.self, forKey: .opacity) ?? 1
        isVisible = try container.decodeIfPresent(Bool.self, forKey: .isVisible) ?? true
        // Legacy elements were panel-local and implicitly locked to a panel.
        usesWrapCoordinates = try container.decodeIfPresent(Bool.self, forKey: .usesWrapCoordinates) ?? false
        isPanelLocked = try container.decodeIfPresent(Bool.self, forKey: .isPanelLocked) ?? true
        imageBookmarkData = try container.decodeIfPresent(Data.self, forKey: .imageBookmarkData)
        imagePathHint = try container.decodeIfPresent(String.self, forKey: .imagePathHint)
        imageName = try container.decodeIfPresent(String.self, forKey: .imageName) ?? ""
    }

    func resolvedImageURL() -> URL? {
        if let imageBookmarkData {
            var isStale = false
            if let resolved = try? URL(
                resolvingBookmarkData: imageBookmarkData,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                return resolved
            }
        }
        if let imagePathHint {
            return URL(fileURLWithPath: imagePathHint)
        }
        return nil
    }

    var displayLabel: String {
        switch kind {
        case .text:
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "Text" : trimmed
        case .image:
            return imageName.isEmpty ? "Image" : imageName
        }
    }

    /// Center X in wrap-absolute millimeters.
    func wrapCenterX(geometry: CoverBlueprintService.Geometry) -> Double {
        if usesWrapCoordinates { return xMM }
        return geometry.panelOriginX(panel) + xMM
    }

    static func defaults(
        title: String,
        author: String,
        geometry: CoverBlueprintService.Geometry,
        typographyLayerID: UUID,
        finishingLayerID: UUID
    ) -> [CoverDesignElement] {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAuthor = author.trimmingCharacters(in: .whitespacesAndNewlines)
        var elements: [CoverDesignElement] = []

        if !trimmedTitle.isEmpty {
            let fontSize = CoverFontStyle.display.defaultSizeMM
            let text = trimmedTitle.uppercased()
            let measured = CoverEditorMath.measuredTextSizeMM(
                text: text,
                fontSizeMM: fontSize,
                fontStyle: .display
            )
            elements.append(
                CoverDesignElement(
                    kind: .text,
                    panel: .front,
                    text: text,
                    xMM: geometry.panelOriginX(.front) + geometry.boardW * 0.5,
                    yMM: geometry.boardH * 0.42,
                    widthMM: measured.width,
                    heightMM: measured.height,
                    fontSizeMM: fontSize,
                    layer: .foil,
                    fontStyle: .display,
                    designLayerID: finishingLayerID,
                    usesWrapCoordinates: true,
                    isPanelLocked: false
                )
            )
        }

        if !trimmedAuthor.isEmpty {
            let fontSize = CoverFontStyle.body.defaultSizeMM
            let text = trimmedAuthor.uppercased()
            let measured = CoverEditorMath.measuredTextSizeMM(
                text: text,
                fontSizeMM: fontSize,
                fontStyle: .body
            )
            elements.append(
                CoverDesignElement(
                    kind: .text,
                    panel: .spine,
                    text: text,
                    xMM: geometry.panelOriginX(.spine) + geometry.spineFace * 0.5,
                    yMM: geometry.boardH * 0.5,
                    widthMM: measured.width,
                    heightMM: measured.height,
                    fontSizeMM: fontSize,
                    rotationDegrees: -90,
                    layer: .foil,
                    fontStyle: .body,
                    designLayerID: typographyLayerID,
                    usesWrapCoordinates: true,
                    isPanelLocked: false
                )
            )
        }

        return elements
    }
}

struct MaterialEntry: Identifiable, Equatable, Codable {
    var id: UUID
    var name: String
    var quantity: String
    var notes: String

    init(id: UUID = UUID(), name: String, quantity: String = "", notes: String = "") {
        self.id = id
        self.name = name
        self.quantity = quantity
        self.notes = notes
    }
}

/// Project metadata and cover/materials context. Imposition job state lives in `BindingWorkspace`.
struct BinderyProject: Identifiable, Equatable, Codable {
    var id: UUID
    var title: String
    var author: String
    var heightMM: Double
    var widthMM: Double
    var architecture: BindingArchitecture
    var createdAt: Date
    var updatedAt: Date

    /// Board / cover blueprinting (mm).
    var boardThicknessMM: Double
    var hingeGapMM: Double
    var coverMaterial: CoverMaterial
    var showFoilLayer: Bool
    var showDebossLayer: Bool
    var folioStampText: String
    /// Named design layers for the cover editor stack.
    var coverDesignLayers: [CoverDesignLayer]
    /// Active layer for newly placed elements.
    var activeCoverLayerID: UUID?
    /// Placed cover/spine artwork (text / images). Empty until seeded in the designer.
    var coverElements: [CoverDesignElement]

    var materials: [MaterialEntry]

    /// Optional paper GSM for spine estimates when no impose plan exists yet.
    var textPaperGSM: Double
    var estimatedPageCount: Int

    /// Workbench tools unlocked for this project.
    /// Full masterworks enable all three; Quick Actions enable only the started tool.
    var enabledTools: Set<ProjectTool>

    init(
        id: UUID = UUID(),
        title: String,
        author: String = "",
        heightMM: Double = 229,
        widthMM: Double = 152,
        architecture: BindingArchitecture = .caseBound,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        boardThicknessMM: Double = 2.0,
        hingeGapMM: Double = 8.0,
        coverMaterial: CoverMaterial = .bookCloth,
        showFoilLayer: Bool = false,
        showDebossLayer: Bool = false,
        folioStampText: String = "",
        coverDesignLayers: [CoverDesignLayer] = [],
        activeCoverLayerID: UUID? = nil,
        coverElements: [CoverDesignElement] = [],
        materials: [MaterialEntry] = [],
        textPaperGSM: Double = 80,
        estimatedPageCount: Int = 0,
        enabledTools: Set<ProjectTool> = Set(ProjectTool.allCases)
    ) {
        self.id = id
        self.title = title
        self.author = author
        self.heightMM = heightMM
        self.widthMM = widthMM
        self.architecture = architecture
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.boardThicknessMM = boardThicknessMM
        self.hingeGapMM = hingeGapMM
        self.coverMaterial = coverMaterial
        self.showFoilLayer = showFoilLayer
        self.showDebossLayer = showDebossLayer
        self.folioStampText = folioStampText
        self.coverDesignLayers = coverDesignLayers
        self.activeCoverLayerID = activeCoverLayerID
        self.coverElements = coverElements
        self.materials = materials
        self.textPaperGSM = textPaperGSM
        self.estimatedPageCount = estimatedPageCount
        self.enabledTools = enabledTools.isEmpty ? Set(ProjectTool.allCases) : enabledTools
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        author = try container.decode(String.self, forKey: .author)
        heightMM = try container.decode(Double.self, forKey: .heightMM)
        widthMM = try container.decode(Double.self, forKey: .widthMM)
        architecture = try container.decode(BindingArchitecture.self, forKey: .architecture)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        boardThicknessMM = try container.decode(Double.self, forKey: .boardThicknessMM)
        hingeGapMM = try container.decode(Double.self, forKey: .hingeGapMM)
        coverMaterial = try container.decode(CoverMaterial.self, forKey: .coverMaterial)
        showFoilLayer = try container.decode(Bool.self, forKey: .showFoilLayer)
        showDebossLayer = try container.decode(Bool.self, forKey: .showDebossLayer)
        folioStampText = try container.decode(String.self, forKey: .folioStampText)
        coverDesignLayers = try container.decodeIfPresent([CoverDesignLayer].self, forKey: .coverDesignLayers) ?? []
        activeCoverLayerID = try container.decodeIfPresent(UUID.self, forKey: .activeCoverLayerID)
        coverElements = try container.decodeIfPresent([CoverDesignElement].self, forKey: .coverElements) ?? []
        materials = try container.decode([MaterialEntry].self, forKey: .materials)
        textPaperGSM = try container.decode(Double.self, forKey: .textPaperGSM)
        estimatedPageCount = try container.decode(Int.self, forKey: .estimatedPageCount)
        let tools = try container.decodeIfPresent([ProjectTool].self, forKey: .enabledTools)
        enabledTools = Set(tools ?? Array(ProjectTool.allCases))
        if enabledTools.isEmpty {
            enabledTools = Set(ProjectTool.allCases)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(author, forKey: .author)
        try container.encode(heightMM, forKey: .heightMM)
        try container.encode(widthMM, forKey: .widthMM)
        try container.encode(architecture, forKey: .architecture)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(boardThicknessMM, forKey: .boardThicknessMM)
        try container.encode(hingeGapMM, forKey: .hingeGapMM)
        try container.encode(coverMaterial, forKey: .coverMaterial)
        try container.encode(showFoilLayer, forKey: .showFoilLayer)
        try container.encode(showDebossLayer, forKey: .showDebossLayer)
        try container.encode(folioStampText, forKey: .folioStampText)
        try container.encode(coverDesignLayers, forKey: .coverDesignLayers)
        try container.encodeIfPresent(activeCoverLayerID, forKey: .activeCoverLayerID)
        try container.encode(coverElements, forKey: .coverElements)
        try container.encode(materials, forKey: .materials)
        try container.encode(textPaperGSM, forKey: .textPaperGSM)
        try container.encode(estimatedPageCount, forKey: .estimatedPageCount)
        let ordered = ProjectTool.allCases.filter { enabledTools.contains($0) }
        try container.encode(ordered, forKey: .enabledTools)
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, author, heightMM, widthMM, architecture
        case createdAt, updatedAt
        case boardThicknessMM, hingeGapMM, coverMaterial
        case showFoilLayer, showDebossLayer, folioStampText
        case coverDesignLayers, activeCoverLayerID, coverElements
        case materials, textPaperGSM, estimatedPageCount, enabledTools
    }

    /// Ensure design layers + editable stamps exist; migrate legacy `folioStampText` when present.
    mutating func seedCoverElementsIfNeeded(spineWidthMM: Double? = nil) {
        ensureCoverDesignLayers()
        let mid = spineWidthMM ?? BindingMath.caseSpineWidthMM(
            pageCount: max(estimatedPageCount, 0),
            gsm: textPaperGSM,
            boardThicknessMM: boardThicknessMM,
            hingeGapMM: hingeGapMM
        )
        let geo = CoverBlueprintService.Geometry(project: self, spineWidthMM: mid)
        migrateCoverElementsToWrapCoordinates(geometry: geo)

        guard coverElements.isEmpty else {
            reattachOrphanElementsToLayers()
            return
        }

        let typography = coverDesignLayers.first { $0.name == "Typography" } ?? coverDesignLayers[0]
        let finishing = coverDesignLayers.first { $0.name == "Finishing" } ?? coverDesignLayers[0]
        activeCoverLayerID = finishing.id

        let stamp = folioStampText.trimmingCharacters(in: .whitespacesAndNewlines)
        let seedTitle = stamp.isEmpty ? title : stamp
        coverElements = CoverDesignElement.defaults(
            title: seedTitle,
            author: author,
            geometry: geo,
            typographyLayerID: typography.id,
            finishingLayerID: finishing.id
        )
        // Full-wrap free placement by default (guides still show joints/spine).
        for index in coverElements.indices {
            coverElements[index].isPanelLocked = false
        }
        if showFoilLayer == false, coverElements.contains(where: { $0.layer == .foil }) {
            showFoilLayer = true
        }
        syncFolioStampTextFromElements()
    }

    /// Convert legacy panel-local coordinates to wrap-absolute once.
    mutating func migrateCoverElementsToWrapCoordinates(geometry: CoverBlueprintService.Geometry) {
        for index in coverElements.indices where !coverElements[index].usesWrapCoordinates {
            let panel = coverElements[index].panel
            coverElements[index].xMM = geometry.panelOriginX(panel) + coverElements[index].xMM
            coverElements[index].usesWrapCoordinates = true
            // Keep locked false so graphics can span joints/spine freely after migration.
            coverElements[index].isPanelLocked = false
        }
    }

    mutating func ensureCoverDesignLayers() {
        if coverDesignLayers.isEmpty {
            coverDesignLayers = CoverDesignLayer.defaults()
        }
        if activeCoverLayerID == nil || !coverDesignLayers.contains(where: { $0.id == activeCoverLayerID }) {
            activeCoverLayerID = coverDesignLayers.sorted(by: { $0.zIndex < $1.zIndex }).last?.id
        }
    }

    mutating func reattachOrphanElementsToLayers() {
        ensureCoverDesignLayers()
        let known = Set(coverDesignLayers.map(\.id))
        let fallback = activeCoverLayerID ?? coverDesignLayers[0].id
        for index in coverElements.indices where !known.contains(coverElements[index].designLayerID) {
            coverElements[index].designLayerID = fallback
        }
    }

    mutating func addCoverDesignLayer(named name: String? = nil) {
        ensureCoverDesignLayers()
        let nextIndex = (coverDesignLayers.map(\.zIndex).max() ?? -1) + 1
        let layer = CoverDesignLayer(
            name: name ?? "Layer \(coverDesignLayers.count + 1)",
            zIndex: nextIndex
        )
        coverDesignLayers.append(layer)
        activeCoverLayerID = layer.id
    }

    mutating func renameCoverDesignLayer(_ id: UUID, to name: String) {
        guard let index = coverDesignLayers.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        coverDesignLayers[index].name = trimmed
    }

    mutating func removeCoverDesignLayer(_ id: UUID) {
        ensureCoverDesignLayers()
        guard coverDesignLayers.count > 1,
              coverDesignLayers.contains(where: { $0.id == id }) else { return }
        let fallback = activeCoverLayerID == id
            ? coverDesignLayers.first { $0.id != id }?.id
            : activeCoverLayerID
        let targetLayerID = fallback ?? coverDesignLayers.first { $0.id != id }?.id
        guard let targetLayerID else { return }
        for index in coverElements.indices where coverElements[index].designLayerID == id {
            coverElements[index].designLayerID = targetLayerID
        }
        coverDesignLayers.removeAll { $0.id == id }
        activeCoverLayerID = targetLayerID
        normalizeCoverLayerZIndexes()
    }

    mutating func moveCoverElement(_ elementID: UUID, toLayer layerID: UUID) {
        guard coverDesignLayers.contains(where: { $0.id == layerID }),
              let index = coverElements.firstIndex(where: { $0.id == elementID }) else { return }
        coverElements[index].designLayerID = layerID
    }

    mutating func moveCoverElementWithinLayer(_ elementID: UUID, direction: Int) {
        guard direction != 0,
              let index = coverElements.firstIndex(where: { $0.id == elementID }) else { return }
        let layerID = coverElements[index].designLayerID
        let sameLayerIndexes = coverElements.indices.filter { coverElements[$0].designLayerID == layerID }
        guard let position = sameLayerIndexes.firstIndex(of: index) else { return }
        let targetPosition = position + direction
        guard sameLayerIndexes.indices.contains(targetPosition) else { return }
        coverElements.swapAt(index, sameLayerIndexes[targetPosition])
    }

    mutating func applyCoverSizeFloor(widthMM floorWidth: Double, heightMM floorHeight: Double) {
        widthMM = max(widthMM, floorWidth, 40)
        heightMM = max(heightMM, floorHeight, 40)
    }

    private mutating func normalizeCoverLayerZIndexes() {
        let ordered = coverDesignLayers.sorted { lhs, rhs in
            if lhs.zIndex != rhs.zIndex { return lhs.zIndex < rhs.zIndex }
            return lhs.name < rhs.name
        }
        for (zIndex, layer) in ordered.enumerated() {
            guard let index = coverDesignLayers.firstIndex(where: { $0.id == layer.id }) else { continue }
            coverDesignLayers[index].zIndex = zIndex
        }
    }

    mutating func syncFolioStampTextFromElements() {
        let front = coverElements.first {
            $0.kind == .text && !$0.text.isEmpty && $0.panel == .front
        }
        folioStampText = front?.text ?? ""
    }

    func orderedCoverElementsForRendering() -> [CoverDesignElement] {
        let layerOrder = Dictionary(uniqueKeysWithValues: coverDesignLayers.map { ($0.id, $0.zIndex) })
        let layerVisible = Dictionary(uniqueKeysWithValues: coverDesignLayers.map { ($0.id, $0.isVisible) })
        return coverElements
            .enumerated()
            .filter { _, element in
                guard element.isVisible else { return false }
                return layerVisible[element.designLayerID] ?? true
            }
            .sorted { lhs, rhs in
                let lz = layerOrder[lhs.element.designLayerID] ?? 0
                let rz = layerOrder[rhs.element.designLayerID] ?? 0
                if lz != rz { return lz < rz }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    var displaySubtitle: String {
        let by = author.trimmingCharacters(in: .whitespacesAndNewlines)
        if by.isEmpty {
            return architecture.rawValue
        }
        return "\(by) · \(architecture.rawValue)"
    }

    var trimLabel: String {
        String(format: "%.0f × %.0f mm", widthMM, heightMM)
    }

    /// Apply an imposition trim (PDF points) so cover boards match the page size.
    mutating func applyImpositionTrim(widthPoints: CGFloat, heightPoints: CGFloat) {
        let trimWidth = max(1, (BindingMath.millimeters(fromPoints: widthPoints) * 10).rounded() / 10)
        let trimHeight = max(1, (BindingMath.millimeters(fromPoints: heightPoints) * 10).rounded() / 10)
        applyCoverSizeFloor(widthMM: trimWidth, heightMM: trimHeight)
    }

    /// Apply a resolved imposition trim when paper is not “keep source size”.
    mutating func applyImpositionTrim(from job: BindingJob) {
        guard let trim = job.resolvedTrimSize else { return }
        applyImpositionTrim(widthPoints: trim.width, heightPoints: trim.height)
    }

    var isFullMasterwork: Bool {
        Set(ProjectTool.allCases).isSubset(of: enabledTools)
    }

    func allows(_ tool: ProjectTool) -> Bool {
        enabledTools.contains(tool)
    }

    /// First enabled tool in display order (Imposition → Cover → Materials).
    var primaryTool: ProjectTool {
        ProjectTool.allCases.first { enabledTools.contains($0) } ?? .imposition
    }
}

/// Tools available only inside an open project workbench.
enum ProjectTool: String, CaseIterable, Identifiable, Hashable, Codable {
    case imposition
    case cover
    case materials

    var id: String { rawValue }

    var title: String {
        switch self {
        case .imposition: return "Imposition"
        case .cover: return "Cover"
        case .materials: return "Materials"
        }
    }

    var systemImage: String {
        switch self {
        case .imposition: return "rectangle.split.2x1"
        case .cover: return "book.closed"
        case .materials: return "list.bullet.clipboard"
        }
    }

    var help: String {
        switch self {
        case .imposition:
            return "Signature folding, creep, and print sheet mapping."
        case .cover:
            return "SVG cover & spine editor — boards, grooves, foil and deboss."
        case .materials:
            return "Inventory tied to this project’s requirements."
        }
    }

    /// Short name used when offering to unlock this tool on a single-purpose project.
    var sectionName: String {
        switch self {
        case .imposition: return "signature layout"
        case .cover: return "cover"
        case .materials: return "materials"
        }
    }

    var unlockPromptTitle: String {
        "Add \(title)?"
    }

    var unlockPromptMessage: String {
        "This project doesn’t include a \(sectionName) section yet. Create one for it?"
    }
}

/// Global destinations in the app sidebar (not project-scoped).
enum GlobalDestination: String, CaseIterable, Identifiable, Hashable {
    case home
    case calculators
    case settings
    case support

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Home"
        case .calculators: return "Calculators"
        case .settings: return "Settings"
        case .support: return "Support"
        }
    }

    var systemImage: String {
        switch self {
        case .home: return "house"
        case .calculators: return "function"
        case .settings: return "gearshape"
        case .support: return "questionmark.circle"
        }
    }
}

enum CloudAssetProvider: String, CaseIterable, Identifiable, Codable, Hashable {
    case iCloudDrive = "iCloud Drive"
    case dropbox = "Dropbox"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .iCloudDrive: return "icloud"
        case .dropbox: return "shippingbox"
        }
    }
}

enum AssetLibraryKind: Codable, Hashable {
    case localFolder
    case cloudStub(CloudAssetProvider)
}

struct AssetLibrary: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var kind: AssetLibraryKind
    var bookmarkData: Data?
    var pathHint: String?
    var isAutoLinked: Bool

    init(
        id: UUID = UUID(),
        name: String,
        kind: AssetLibraryKind = .localFolder,
        bookmarkData: Data? = nil,
        pathHint: String? = nil,
        isAutoLinked: Bool = false
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.bookmarkData = bookmarkData
        self.pathHint = pathHint
        self.isAutoLinked = isAutoLinked
    }

    var isCloudStub: Bool {
        if case .cloudStub = kind { return true }
        return false
    }
}

enum SidebarSelection: Hashable {
    case global(GlobalDestination)
    case project(UUID)
    case library(UUID)
}
