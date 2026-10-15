import CoreGraphics
import Foundation

/// Named stack layer shared by cover and endsheet editors.
struct DesignLayer: Identifiable, Equatable, Codable, Hashable {
    var id: UUID
    var name: String
    var isVisible: Bool
    /// Locked layers render but their elements can't be selected or moved.
    var isLocked: Bool
    var zIndex: Int

    init(id: UUID = UUID(), name: String, isVisible: Bool = true, isLocked: Bool = false, zIndex: Int = 0) {
        self.id = id
        self.name = name
        self.isVisible = isVisible
        self.isLocked = isLocked
        self.zIndex = zIndex
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        isVisible = try container.decodeIfPresent(Bool.self, forKey: .isVisible) ?? true
        isLocked = try container.decodeIfPresent(Bool.self, forKey: .isLocked) ?? false
        zIndex = try container.decodeIfPresent(Int.self, forKey: .zIndex) ?? 0
    }

    static func defaults() -> [DesignLayer] {
        [DesignLayer(name: "Layer 1", zIndex: 0)]
    }
}

/// Cover editor layers are the shared design-layer type.
typealias CoverDesignLayer = DesignLayer

/// Element kinds shared across design surfaces.
enum DesignElementKind: String, CaseIterable, Identifiable, Codable, Hashable {
    case text
    case image
    case shape

    var id: String { rawValue }

    var title: String {
        switch self {
        case .text: return "Text"
        case .image: return "Image"
        case .shape: return "Shape"
        }
    }
}

/// Shape primitives shared by cover and endsheet editors.
enum DesignShapeType: String, CaseIterable, Identifiable, Codable, Hashable {
    case rectangle
    case ellipse
    case line

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rectangle: return "Rectangle"
        case .ellipse: return "Ellipse"
        case .line: return "Line"
        }
    }

    var systemImage: String {
        switch self {
        case .rectangle: return "rectangle"
        case .ellipse: return "oval"
        case .line: return "line.diagonal"
        }
    }

    var asCoverShape: CoverShapeType {
        switch self {
        case .rectangle: return .rectangle
        case .ellipse: return .ellipse
        case .line: return .line
        }
    }

    init(_ cover: CoverShapeType) {
        switch cover {
        case .rectangle: self = .rectangle
        case .ellipse: self = .ellipse
        case .line: self = .line
        }
    }
}

/// Generic design element for endsheet (and future shared) canvases.
/// Cover continues to use `CoverDesignElement` with the same conceptual fields
/// plus wrap-panel / finish-channel attachments.
struct DesignElement: Identifiable, Equatable, Codable, Hashable {
    var id: UUID
    var kind: DesignElementKind
    var text: String
    var xMM: Double
    var yMM: Double
    var widthMM: Double
    var heightMM: Double
    var fontSizeMM: Double
    var rotationDegrees: Double
    var fontStyle: CoverFontStyle
    var designLayerID: UUID
    /// Optional group membership for multi-element transforms.
    var groupID: UUID?
    var opacity: Double
    var isVisible: Bool
    var shapeType: DesignShapeType
    var strokeWidthMM: Double
    var strokeStyle: CoverStrokeStyle
    var ornamentPattern: CoverOrnamentPattern
    var dashLengthScale: Double
    var dashGapScale: Double
    var stroke: CoverPaint
    var fill: CoverPaint
    var imageBookmarkData: Data?
    var imagePathHint: String?
    var imageName: String

    init(
        id: UUID = UUID(),
        kind: DesignElementKind = .shape,
        text: String = "",
        xMM: Double = 0,
        yMM: Double = 0,
        widthMM: Double = 20,
        heightMM: Double = 20,
        fontSizeMM: Double = CoverFontStyle.body.defaultSizeMM,
        rotationDegrees: Double = 0,
        fontStyle: CoverFontStyle = .body,
        designLayerID: UUID,
        groupID: UUID? = nil,
        opacity: Double = 1,
        isVisible: Bool = true,
        shapeType: DesignShapeType = .rectangle,
        strokeWidthMM: Double = 0.8,
        strokeStyle: CoverStrokeStyle = .solid,
        ornamentPattern: CoverOrnamentPattern = .dots,
        dashLengthScale: Double = 1,
        dashGapScale: Double = 1,
        stroke: CoverPaint = .solid(.inkBlack),
        fill: CoverPaint = .none,
        imageBookmarkData: Data? = nil,
        imagePathHint: String? = nil,
        imageName: String = ""
    ) {
        self.id = id
        self.kind = kind
        self.text = text
        self.xMM = xMM
        self.yMM = yMM
        self.widthMM = widthMM
        self.heightMM = heightMM
        self.fontSizeMM = fontSizeMM
        self.rotationDegrees = rotationDegrees
        self.fontStyle = fontStyle
        self.designLayerID = designLayerID
        self.groupID = groupID
        self.opacity = opacity
        self.isVisible = isVisible
        self.shapeType = shapeType
        self.strokeWidthMM = strokeWidthMM
        self.strokeStyle = strokeStyle
        self.ornamentPattern = ornamentPattern
        self.dashLengthScale = dashLengthScale
        self.dashGapScale = dashGapScale
        self.stroke = stroke
        self.fill = fill
        self.imageBookmarkData = imageBookmarkData
        self.imagePathHint = imagePathHint
        self.imageName = imageName
    }

    var isFilled: Bool { fill.isFilled }
    var isStroked: Bool { stroke.isFilled }

    func strokeDashPatternMM() -> [Double] {
        guard strokeStyle == .ornament else { return [] }
        return ornamentPattern.dashPatternMM(
            strokeWidthMM: strokeWidthMM,
            lengthScale: dashLengthScale,
            gapScale: dashGapScale
        )
    }

    var displayLabel: String {
        switch kind {
        case .text: return text.isEmpty ? "Text" : text
        case .image: return imageName.isEmpty ? "Image" : imageName
        case .shape: return shapeType.title
        }
    }

    /// Axis-aligned bounds (ignores rotation for layout math).
    var boundsMM: CGRect {
        CGRect(x: xMM, y: yMM, width: max(0.1, widthMM), height: max(0.1, heightMM))
    }

    var centerXMM: Double { xMM + widthMM * 0.5 }
    var centerYMM: Double { yMM + heightMM * 0.5 }
}

/// Layered design document used by the endsheet editor (and as the shared conceptual model).
struct DesignDocument: Equatable, Codable {
    var layers: [DesignLayer]
    var elements: [DesignElement]
    var activeLayerID: UUID?

    init(
        layers: [DesignLayer] = DesignLayer.defaults(),
        elements: [DesignElement] = [],
        activeLayerID: UUID? = nil
    ) {
        self.layers = layers
        self.elements = elements
        self.activeLayerID = activeLayerID ?? layers.first?.id
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        layers = try c.decodeIfPresent([DesignLayer].self, forKey: .layers) ?? DesignLayer.defaults()
        elements = try c.decodeIfPresent([DesignElement].self, forKey: .elements) ?? []
        activeLayerID = try c.decodeIfPresent(UUID.self, forKey: .activeLayerID) ?? layers.first?.id
    }

    mutating func ensureLayers() {
        if layers.isEmpty {
            layers = DesignLayer.defaults()
        }
        if activeLayerID == nil || !layers.contains(where: { $0.id == activeLayerID }) {
            activeLayerID = layers.first?.id
        }
        normalizeZIndexes()
    }

    mutating func normalizeZIndexes() {
        let sorted = layers.sorted { $0.zIndex < $1.zIndex }
        for (i, layer) in sorted.enumerated() {
            if let idx = layers.firstIndex(where: { $0.id == layer.id }) {
                layers[idx].zIndex = i
            }
        }
    }

    func orderedElementsForRendering() -> [DesignElement] {
        let layerOrder = Dictionary(uniqueKeysWithValues: layers.map { ($0.id, $0.zIndex) })
        let layerVisible = Dictionary(uniqueKeysWithValues: layers.map { ($0.id, $0.isVisible) })
        return elements
            .enumerated()
            .filter { _, element in
                element.isVisible && (layerVisible[element.designLayerID] ?? true)
            }
            .sorted { lhs, rhs in
                let lz = layerOrder[lhs.element.designLayerID] ?? 0
                let rz = layerOrder[rhs.element.designLayerID] ?? 0
                if lz != rz { return lz < rz }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    mutating func addLayer(named name: String? = nil) {
        let nextIndex = (layers.map(\.zIndex).max() ?? -1) + 1
        let layer = DesignLayer(name: name ?? "Layer \(layers.count + 1)", zIndex: nextIndex)
        layers.append(layer)
        activeLayerID = layer.id
    }

    /// Build a document seeded from a legacy endpaper face fill mode.
    static func migrating(from face: EndpaperFaceDesign, sheetWidthMM: Double, sheetHeightMM: Double) -> DesignDocument {
        var doc = DesignDocument()
        doc.ensureLayers()
        guard let layerID = doc.activeLayerID else { return doc }

        switch face.mode {
        case .blank:
            break
        case .solidColor:
            guard face.solidColor != .none else { break }
            var element = DesignElement(
                kind: .shape,
                xMM: 0,
                yMM: 0,
                widthMM: sheetWidthMM,
                heightMM: sheetHeightMM,
                designLayerID: layerID,
                shapeType: .rectangle,
                stroke: .none,
                fill: .solid(CodableColor(cgColor: face.solidColor.cgColor))
            )
            element.strokeWidthMM = 0
            doc.elements.append(element)
        case .marbled:
            if let marble = face.marbling {
                doc.elements.append(
                    DesignElement(
                        kind: .shape,
                        xMM: 0,
                        yMM: 0,
                        widthMM: sheetWidthMM,
                        heightMM: sheetHeightMM,
                        designLayerID: layerID,
                        shapeType: .rectangle,
                        stroke: .none,
                        fill: .marbled(marble)
                    )
                )
            }
        case .artwork:
            if let art = face.artwork {
                doc.elements.append(
                    DesignElement(
                        kind: .image,
                        xMM: 0,
                        yMM: 0,
                        widthMM: sheetWidthMM,
                        heightMM: sheetHeightMM,
                        designLayerID: layerID,
                        imageBookmarkData: art.bookmarkData,
                        imagePathHint: art.url.path,
                        imageName: art.name
                    )
                )
            }
        }
        return doc
    }
}
