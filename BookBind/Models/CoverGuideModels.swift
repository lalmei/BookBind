import CoreGraphics
import Foundation

/// How covering material is cut at board corners when folding turn-ins.
///
/// Binding note: there is no single universal convention. Cloth casework commonly
/// uses a 45° miter; leather and thick boards often prefer square butts or rounded
/// corners; some shops add relief slits near the hinge for stiff materials.
enum CoverCornerTreatment: String, CaseIterable, Identifiable, Codable, Hashable {
    case miter
    case square
    case rounded
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .miter: return "Miter (diagonal)"
        case .square: return "Square (butt)"
        case .rounded: return "Rounded"
        case .custom: return "Custom"
        }
    }

    var help: String {
        switch self {
        case .miter: return "45° cut from board corner to material corner — common cloth default"
        case .square: return "Right-angle cut leaving square turn-in tabs"
        case .rounded: return "Arc cut with radius based on turn-in (or override)"
        case .custom: return "Reserved for user-defined corner paths"
        }
    }
}

/// Independent visibility for production guides. Guides are never design elements.
struct CoverGuideVisibility: Equatable, Codable, Hashable {
    var cut: Bool
    var fold: Bool
    var trim: Bool
    var board: Bool
    var spine: Bool
    var hinge: Bool
    var safe: Bool
    var corner: Bool
    var relief: Bool

    static let `default` = CoverGuideVisibility(
        cut: true,
        fold: true,
        trim: true,
        board: true,
        spine: true,
        hinge: true,
        safe: false,
        corner: true,
        relief: true
    )

    static let allHidden = CoverGuideVisibility(
        cut: false,
        fold: false,
        trim: false,
        board: false,
        spine: false,
        hinge: false,
        safe: false,
        corner: false,
        relief: false
    )
}

/// Production allowances and corner/relief configuration for case-bound covers.
struct CoverProductionSpec: Equatable, Codable, Hashable {
    /// Outer allowance beyond the material cut edge (mm). Distinct from turn-in.
    var bleedMM: Double
    /// Reference inset from finished board edges (mm) — not a cut.
    var safeAreaMM: Double
    var cornerTreatment: CoverCornerTreatment
    /// Corner radius when `cornerTreatment == .rounded` (mm). `nil` uses turn-in.
    var cornerRadiusMM: Double?
    /// Short relief cuts near hinge/spine on head/tail turn-ins.
    var reliefCutsEnabled: Bool
    /// Length of each relief cut along the head/tail (mm).
    var reliefCutLengthMM: Double
    /// Inset of relief cuts from the hinge fold toward the fore-edge (mm).
    var reliefCutInsetMM: Double
    var guideVisibility: CoverGuideVisibility

    static let `default` = CoverProductionSpec(
        bleedMM: 0,
        safeAreaMM: 5,
        cornerTreatment: .miter,
        cornerRadiusMM: nil,
        reliefCutsEnabled: false,
        reliefCutLengthMM: 8,
        reliefCutInsetMM: 2,
        guideVisibility: .default
    )

    init(
        bleedMM: Double = 0,
        safeAreaMM: Double = 5,
        cornerTreatment: CoverCornerTreatment = .miter,
        cornerRadiusMM: Double? = nil,
        reliefCutsEnabled: Bool = false,
        reliefCutLengthMM: Double = 8,
        reliefCutInsetMM: Double = 2,
        guideVisibility: CoverGuideVisibility = .default
    ) {
        self.bleedMM = max(0, bleedMM)
        self.safeAreaMM = max(0, safeAreaMM)
        self.cornerTreatment = cornerTreatment
        self.cornerRadiusMM = cornerRadiusMM.map { max(0, $0) }
        self.reliefCutsEnabled = reliefCutsEnabled
        self.reliefCutLengthMM = max(0, reliefCutLengthMM)
        self.reliefCutInsetMM = max(0, reliefCutInsetMM)
        self.guideVisibility = guideVisibility
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bleedMM = max(0, try c.decodeIfPresent(Double.self, forKey: .bleedMM) ?? 0)
        safeAreaMM = max(0, try c.decodeIfPresent(Double.self, forKey: .safeAreaMM) ?? 5)
        cornerTreatment = try c.decodeIfPresent(CoverCornerTreatment.self, forKey: .cornerTreatment) ?? .miter
        cornerRadiusMM = try c.decodeIfPresent(Double.self, forKey: .cornerRadiusMM)
        reliefCutsEnabled = try c.decodeIfPresent(Bool.self, forKey: .reliefCutsEnabled) ?? false
        reliefCutLengthMM = max(0, try c.decodeIfPresent(Double.self, forKey: .reliefCutLengthMM) ?? 8)
        reliefCutInsetMM = max(0, try c.decodeIfPresent(Double.self, forKey: .reliefCutInsetMM) ?? 2)
        guideVisibility = try c.decodeIfPresent(CoverGuideVisibility.self, forKey: .guideVisibility) ?? .default
    }
}

/// Line segment in millimetres (top-left origin).
struct GuideSegment: Equatable, Hashable {
    var a: CGPoint
    var b: CGPoint
}

/// Fully resolved production guide geometry in **material-space**
/// (origin = top-left of covering-material sheet, including turn-in).
///
/// Assumptions documented in README “Cover production geometry”.
struct CoverProductionLayout: Equatable {
    /// Outer cut rectangle including bleed (solid cut).
    var cutRect: CGRect
    /// Material sheet without bleed (turn-in outer edge when bleed is 0).
    var materialRect: CGRect
    /// Finished board wrap fold rectangle.
    var boardRect: CGRect
    /// Safe-area inset of the board wrap.
    var safeRect: CGRect
    /// Spine face rectangle inside the board wrap.
    var spineRect: CGRect
    /// Back / front hinge rectangles.
    var hingeRects: [CGRect]
    /// Vertical fold lines (joint + spine edges) across material height.
    var foldXs: [Double]
    /// Corner cut segments or arc descriptions.
    var cornerCuts: [GuideSegment]
    /// Optional relief cuts near hinge regions.
    var reliefCuts: [GuideSegment]
    var turnInMM: Double
    var bleedMM: Double
    var cornerTreatment: CoverCornerTreatment
}
