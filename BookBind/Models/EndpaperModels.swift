import Foundation

enum EndpaperMode: String, CaseIterable, Identifiable, Codable, Hashable {
    case blank
    case solidColor
    case artwork
    case marbled

    var id: String { rawValue }

    var title: String {
        switch self {
        case .blank: return "Blank"
        case .solidColor: return "Solid color"
        case .artwork: return "Artwork"
        case .marbled: return "Marble paper"
        }
    }

    var systemImage: String {
        switch self {
        case .blank: return "doc"
        case .solidColor: return "paintpalette.fill"
        case .artwork: return "photo"
        case .marbled: return "paintbrush.pointed.fill"
        }
    }

    var help: String {
        switch self {
        case .blank: return "Undecorated endpaper leaves"
        case .solidColor: return "Solid tinted endpaper"
        case .artwork: return "Image or PDF artwork"
        case .marbled: return "Procedural marbled paper generator"
        }
    }
}

enum MarblingStyle: String, CaseIterable, Identifiable, Codable, Hashable {
    case stone
    case nonpareil
    case peacock
    case combed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .stone: return "Traditional Stone"
        case .nonpareil: return "Nonpareil"
        case .peacock: return "Peacock"
        case .combed: return "Combed"
        }
    }

    var help: String {
        switch self {
        case .stone: return "Random ink drops with light turbulence — classic stone marble"
        case .nonpareil: return "Fine parallel combs through layered drops"
        case .peacock: return "Chevron / bouquet comb pattern"
        case .combed: return "Wider rake passes along the flow direction"
        }
    }
}

/// Deterministic procedural marbling parameters (store these, not a bitmap).
struct MarbledPaperSpec: Equatable, Hashable, Codable {
    var style: MarblingStyle
    var seed: UInt64
    var palette: [CodableColor]
    var background: CodableColor
    /// Overall feature size (drops and comb pitch).
    var scale: Double
    /// Comb / rake direction in degrees.
    var flowDegrees: Double
    /// Extra spatters and wavy rake emphasis.
    var turbulence: Double
    /// How many ink drops (and tine count) to place.
    var density: Double
    /// Bias toward later inks vs bath paper.
    var colorBalance: Double
    /// Relative comb/tine spacing (Marblizer `spacing` scale).
    var combSpacing: Double
    /// Relative comb drag strength (Marblizer `alpha` scale).
    var combStrength: Double
    /// Relative ink-drop radius before scale is applied.
    var dropSize: Double

    init(
        style: MarblingStyle = .stone,
        seed: UInt64 = 42,
        palette: [CodableColor] = MarbledPaperPalette.traditionalStone.colors,
        background: CodableColor = .paperIvory,
        scale: Double = 1,
        flowDegrees: Double = 0,
        turbulence: Double = 0.35,
        density: Double = 0.55,
        colorBalance: Double = 0.5,
        combSpacing: Double = 1,
        combStrength: Double = 1,
        dropSize: Double = 1
    ) {
        self.style = style
        self.seed = seed
        self.palette = palette
        self.background = background
        self.scale = scale
        self.flowDegrees = flowDegrees
        self.turbulence = turbulence
        self.density = density
        self.colorBalance = colorBalance
        self.combSpacing = combSpacing
        self.combStrength = combStrength
        self.dropSize = dropSize
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        style = try container.decodeIfPresent(MarblingStyle.self, forKey: .style) ?? .stone
        seed = try container.decodeIfPresent(UInt64.self, forKey: .seed) ?? 42
        palette = try container.decodeIfPresent([CodableColor].self, forKey: .palette)
            ?? MarbledPaperPalette.traditionalStone.colors
        background = try container.decodeIfPresent(CodableColor.self, forKey: .background) ?? .paperIvory
        scale = try container.decodeIfPresent(Double.self, forKey: .scale) ?? 1
        flowDegrees = try container.decodeIfPresent(Double.self, forKey: .flowDegrees) ?? 0
        turbulence = try container.decodeIfPresent(Double.self, forKey: .turbulence) ?? 0.35
        density = try container.decodeIfPresent(Double.self, forKey: .density) ?? 0.55
        colorBalance = try container.decodeIfPresent(Double.self, forKey: .colorBalance) ?? 0.5
        combSpacing = try container.decodeIfPresent(Double.self, forKey: .combSpacing) ?? 1
        combStrength = try container.decodeIfPresent(Double.self, forKey: .combStrength) ?? 1
        dropSize = try container.decodeIfPresent(Double.self, forKey: .dropSize) ?? 1
    }

    /// New random seed; keeps palette and other settings.
    mutating func regenerateVariation() {
        seed = UInt64.random(in: 1...UInt64.max)
    }
}

struct MarbledPaperPalette: Identifiable, Hashable {
    let id: String
    let name: String
    let colors: [CodableColor]
    let background: CodableColor

    static let traditionalStone = MarbledPaperPalette(
        id: "traditional-stone",
        name: "Traditional Stone",
        colors: [
            CodableColor(red: 0.12, green: 0.14, blue: 0.18),
            CodableColor(red: 0.55, green: 0.18, blue: 0.16),
            CodableColor(red: 0.72, green: 0.55, blue: 0.28),
            CodableColor(red: 0.18, green: 0.32, blue: 0.28)
        ],
        background: .paperIvory
    )

    static let indigoOchre = MarbledPaperPalette(
        id: "indigo-ochre",
        name: "Indigo & Ochre",
        colors: [
            CodableColor(red: 0.14, green: 0.22, blue: 0.45),
            CodableColor(red: 0.78, green: 0.52, blue: 0.18),
            CodableColor(red: 0.20, green: 0.18, blue: 0.16),
            CodableColor(red: 0.85, green: 0.78, blue: 0.55)
        ],
        background: CodableColor(red: 0.94, green: 0.91, blue: 0.82)
    )

    static let venetianRed = MarbledPaperPalette(
        id: "venetian-red",
        name: "Venetian Red",
        colors: [
            CodableColor(red: 0.62, green: 0.16, blue: 0.14),
            CodableColor(red: 0.35, green: 0.12, blue: 0.12),
            CodableColor(red: 0.78, green: 0.62, blue: 0.35),
            CodableColor(red: 0.16, green: 0.18, blue: 0.22)
        ],
        background: CodableColor(red: 0.95, green: 0.90, blue: 0.82)
    )

    static let verdeAntico = MarbledPaperPalette(
        id: "verde-antico",
        name: "Verde Antico",
        colors: [
            CodableColor(red: 0.18, green: 0.38, blue: 0.28),
            CodableColor(red: 0.10, green: 0.22, blue: 0.18),
            CodableColor(red: 0.55, green: 0.58, blue: 0.42),
            CodableColor(red: 0.72, green: 0.68, blue: 0.48)
        ],
        background: CodableColor(red: 0.93, green: 0.92, blue: 0.85)
    )

    static let stormGray = MarbledPaperPalette(
        id: "storm-gray",
        name: "Storm Gray",
        colors: [
            CodableColor(red: 0.22, green: 0.24, blue: 0.28),
            CodableColor(red: 0.40, green: 0.42, blue: 0.46),
            CodableColor(red: 0.12, green: 0.13, blue: 0.16),
            CodableColor(red: 0.62, green: 0.58, blue: 0.52)
        ],
        background: CodableColor(red: 0.90, green: 0.89, blue: 0.86)
    )

    static let all: [MarbledPaperPalette] = [
        .traditionalStone, .indigoOchre, .venetianRed, .verdeAntico, .stormGray
    ]
}

struct EndpaperFaceDesign: Equatable, Codable {
    var mode: EndpaperMode
    var solidColor: EndpaperColor
    var artwork: EndpaperArtwork?
    var marbling: MarbledPaperSpec?

    init(
        mode: EndpaperMode = .blank,
        solidColor: EndpaperColor = .none,
        artwork: EndpaperArtwork? = nil,
        marbling: MarbledPaperSpec? = nil
    ) {
        self.mode = mode
        self.solidColor = solidColor
        self.artwork = artwork
        self.marbling = marbling
    }

    mutating func ensureMarbling() {
        if marbling == nil {
            marbling = MarbledPaperSpec()
        }
        mode = .marbled
    }

    /// Normalize mode from stored fields (e.g. after picking artwork).
    mutating func syncModeFromContents() {
        if mode == .marbled, marbling != nil { return }
        if artwork != nil {
            mode = .artwork
        } else if solidColor != .none {
            mode = .solidColor
        } else if mode != .marbled {
            mode = .blank
        }
    }
}

struct EndpaperDesign: Equatable, Codable {
    var front: EndpaperFaceDesign
    var back: EndpaperFaceDesign

    init(front: EndpaperFaceDesign = EndpaperFaceDesign(), back: EndpaperFaceDesign = EndpaperFaceDesign()) {
        self.front = front
        self.back = back
    }
}
