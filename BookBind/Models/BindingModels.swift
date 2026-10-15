import CoreGraphics
import Foundation
import PDFKit

/// Page-order maps for the classic single-sided 8-page slit-and-fold zine (4×2).
/// All share the same cut: horizontal center slit across the middle two columns only.
enum MiniZine8Template: String, CaseIterable, Identifiable, Codable {
    case classicNested = "Classic nested"
    case coverCenter = "Cover-center"
    case coverLeft = "Cover-left"
    case sequential = "Sequential"

    var id: String { rawValue }

    var shortLabel: String {
        switch self {
        case .classicNested: return "5·4·3·2 / 6·7·8·1"
        case .coverCenter: return "8·1·2·3 / 7·6·5·4"
        case .coverLeft: return "1·8·7·6 / 2·3·4·5"
        case .sequential: return "3·2·1·8 / 4·5·6·7"
        }
    }

    var help: String {
        switch self {
        case .classicNested:
            return "Widely taught school/DIY map. Top row upside-down 5–4–3–2; bottom 6–7–8–1. Front cover lands at bottom-right."
        case .coverCenter:
            return "PDF Press–style map. Top upside-down 8–1–2–3; bottom 7–6–5–4. Cover pair sits near the center of the top row."
        case .coverLeft:
            return "Mycro-zine–style map. Top upside-down 1–8–7–6; bottom 2–3–4–5. Front cover at top-left."
        case .sequential:
            return "Softglitch-style map. Top upside-down 3–2–1–8; bottom 4–5–6–7. Cover and back sit in the top-right pair."
        }
    }

    /// Top row, left→right, 0-based page indices (drawn at 180°).
    var topRowPages: [Int] {
        switch self {
        case .classicNested: return [4, 3, 2, 1]
        case .coverCenter: return [7, 0, 1, 2]
        case .coverLeft: return [0, 7, 6, 5]
        case .sequential: return [2, 1, 0, 7]
        }
    }

    /// Bottom row, left→right, 0-based page indices (drawn upright).
    var bottomRowPages: [Int] {
        switch self {
        case .classicNested: return [5, 6, 7, 0]
        case .coverCenter: return [6, 5, 4, 3]
        case .coverLeft: return [1, 2, 3, 4]
        case .sequential: return [3, 4, 5, 6]
        }
    }
}

/// Cut / fold pattern for 16-page one-sheet layouts.
enum MiniZine16Template: String, CaseIterable, Identifiable, Codable {
    case crossCut = "Cross-cut 4×4"
    case horizontalSlits = "Horizontal slits"

    var id: String { rawValue }

    var help: String {
        switch self {
        case .crossCut:
            return "4×4 grid. Top two rows upside-down. Cut a cross through the center four panels (horizontal + vertical slits)."
        case .horizontalSlits:
            return "4×4 grid. Top two rows upside-down. Two horizontal slits on the midlines of the middle two column-pairs (no vertical cut)."
        }
    }
}

/// One numbered step in a fold / cut instruction sheet.
struct FoldCutStep: Equatable, Identifiable {
    var id: Int
    var title: String
    var detail: String
}

/// Human instructions for assembling the current imposition layout.
struct FoldCutGuide: Equatable {
    var title: String
    var subtitle: String
    var overview: String
    var steps: [FoldCutStep]
    var tips: [String]
    /// Optional page-map caption (zine templates).
    var pageMapCaption: String?
    /// Diagram kind for the sheet preview in the guide UI.
    var diagram: Diagram

    enum Diagram: Equatable {
        case none
        case miniZine8(MiniZine8Template)
        case miniZine16(MiniZine16Template)
        case accordion(panelCount: Int)
        case halfFold
        case folio
    }

    static func making(for job: BindingJob) -> FoldCutGuide {
        switch job.impositionScheme {
        case .folioSignatures:
            return folioGuide(style: job.bindingStyle)
        case .halfFoldBooklet:
            return halfFoldGuide()
        case .miniZine8:
            return miniZine8Guide(template: job.miniZine8Template)
        case .miniZine16:
            return miniZine16Guide(template: job.miniZine16Template)
        case .accordion:
            return accordionGuide(panelCount: job.resolvedAccordionPanelCount)
        }
    }

    private static func folioGuide(style: BindingStyle) -> FoldCutGuide {
        FoldCutGuide(
            title: "Fold & print guide",
            subtitle: "Signatures (folio) · \(style.rawValue)",
            overview: "Pages print as 2-up landscape spreads. Nest sheets into signatures, then sew or stitch through the fold.",
            steps: [
                FoldCutStep(id: 1, title: "Print duplex", detail: BindingJob.duplexHintText),
                FoldCutStep(id: 2, title: "Keep sheet order", detail: "Do not reshuffle printer sheets. Sheet 1 is the outermost nest of each signature."),
                FoldCutStep(id: 3, title: "Fold each sheet", detail: "Fold each sheet in half along the center guide (short-edge tumble matches the spine)."),
                FoldCutStep(
                    id: 4,
                    title: style == .saddleStitch ? "Nest & stitch" : "Nest into signatures",
                    detail: style == .saddleStitch
                        ? "Nest all folded sheets into one pamphlet and staple or sew through the fold."
                        : "Gather folded sheets into signatures of the chosen size, then sew or bind per your architecture."
                )
            ],
            tips: [
                "Turn on Guide marks to see the fold line on proofs.",
                "Use the Signature map to check which book pages land on each sheet face."
            ],
            pageMapCaption: nil,
            diagram: .folio
        )
    }

    private static func halfFoldGuide() -> FoldCutGuide {
        FoldCutGuide(
            title: "Fold & print guide",
            subtitle: "Half-fold booklet",
            overview: "A single nested pamphlet: each printer sheet is one folio (4 pages). Fold in half and stitch through the spine.",
            steps: [
                FoldCutStep(id: 1, title: "Print duplex", detail: BindingJob.duplexHintText),
                FoldCutStep(id: 2, title: "Fold in half", detail: "Fold each sheet along the long center so left and right pages meet as a spread."),
                FoldCutStep(id: 3, title: "Nest sheets", detail: "Stack folded sheets inside each other — outermost sheet has the cover pages."),
                FoldCutStep(id: 4, title: "Stitch the fold", detail: "Staple or sew through the spine. Optional stitch-hole marks show punch positions.")
            ],
            tips: [
                "No cut is required — only folds and stitching.",
                "Pad content to a multiple of 4 so every sheet is full."
            ],
            pageMapCaption: nil,
            diagram: .halfFold
        )
    }

    private static func miniZine8Guide(template: MiniZine8Template) -> FoldCutGuide {
        FoldCutGuide(
            title: "Fold & cut guide",
            subtitle: "8-page mini-zine · \(template.rawValue)",
            overview: "One sheet becomes an 8-page booklet. Print single-sided, fold to crease, cut only the center slit, then collapse.",
            steps: [
                FoldCutStep(
                    id: 1,
                    title: "Print single-sided",
                    detail: "Print the imposed sheet at 100% scale (no “fit to page”). Guides: light gray dashed = fold, darker solid gray = cut."
                ),
                FoldCutStep(
                    id: 2,
                    title: "Fold lengthwise",
                    detail: "Fold the long edges together (hotdog). Crease firmly, then unfold flat."
                ),
                FoldCutStep(
                    id: 3,
                    title: "Fold widthwise twice",
                    detail: "Fold short edge to short edge, crease, unfold; fold again into quarters, crease, then unfold completely so you see eight panels."
                ),
                FoldCutStep(
                    id: 4,
                    title: "Cut the center slit only",
                    detail: "Fold short-edge to short-edge once. Cut along the solid gray line from the folded edge — only through the middle two panels. Do not cut to the outer edges of the sheet."
                ),
                FoldCutStep(
                    id: 5,
                    title: "Collapse into a booklet",
                    detail: "Open flat, refold lengthwise along the slit, and gently push the short ends toward each other so the cut opens into a plus. Flatten so page 1 is the front cover."
                )
            ],
            tips: [
                "If pages read out of order, try another Page map template — the cut is the same for all.",
                "Turn Guide marks off for a clean final print once you know the folds.",
                "Score fold lines with a bone folder for sharper creases."
            ],
            pageMapCaption: "Page map (\(template.rawValue)): top \(template.shortLabel.components(separatedBy: " / ").first ?? "") (upside-down); bottom \(template.shortLabel.components(separatedBy: " / ").last ?? "") (upright).",
            diagram: .miniZine8(template)
        )
    }

    private static func miniZine16Guide(template: MiniZine16Template) -> FoldCutGuide {
        let cutStep: FoldCutStep
        switch template {
        case .crossCut:
            cutStep = FoldCutStep(
                id: 4,
                title: "Cut the center cross",
                detail: "Cut only the solid gray slits: one horizontal and one vertical through the center four panels. Do not extend cuts to the sheet outer edges."
            )
        case .horizontalSlits:
            cutStep = FoldCutStep(
                id: 4,
                title: "Cut the horizontal slits",
                detail: "Cut only the two solid gray horizontal slits (middle two columns on the upper and lower inner midlines). Leave outer panels uncut."
            )
        }

        return FoldCutGuide(
            title: "Fold & cut guide",
            subtitle: "16-page mini-zine · \(template.rawValue)",
            overview: "One sheet folded into a 4×4 panel grid. Top two rows print upside-down. Cut the marked slits, then collapse into a 16-page booklet.",
            steps: [
                FoldCutStep(
                    id: 1,
                    title: "Print single-sided",
                    detail: "Print at 100% scale. Light gray dashed lines are folds; darker solid gray lines are cuts."
                ),
                FoldCutStep(
                    id: 2,
                    title: "Crease the grid",
                    detail: "Fold the sheet into halves and quarters both ways so all dashed fold lines are creased, then unfold flat."
                ),
                FoldCutStep(
                    id: 3,
                    title: "Check the panel map",
                    detail: "Confirm upside-down pages sit in the top two rows before cutting."
                ),
                cutStep,
                FoldCutStep(
                    id: 5,
                    title: "Collapse into a booklet",
                    detail: "Refold along the main spine folds and push sections together so the slits open into nested signatures. Flatten with page 1 as the cover."
                )
            ],
            tips: [
                "16-page one-sheet zines are fiddly — practice on scrap paper first.",
                "Switch Cut pattern if your fold habit uses horizontal slits instead of a cross."
            ],
            pageMapCaption: template.help,
            diagram: .miniZine16(template)
        )
    }

    private static func accordionGuide(panelCount: Int) -> FoldCutGuide {
        FoldCutGuide(
            title: "Fold guide",
            subtitle: "Accordion · \(panelCount) panels",
            overview: "One strip of panels. No cut — only alternating mountain and valley folds.",
            steps: [
                FoldCutStep(
                    id: 1,
                    title: "Print single-sided",
                    detail: "Print the strip at 100% scale. Dashed gray lines mark panel folds."
                ),
                FoldCutStep(
                    id: 2,
                    title: "Accordion-fold",
                    detail: "Fold along each dashed line, alternating direction (mountain / valley) so the strip zig-zags into a stack of \(panelCount) panels."
                ),
                FoldCutStep(
                    id: 3,
                    title: "Press flat",
                    detail: "Bone-folder each crease. Optionally bind or case the closed accordion as a flap book."
                )
            ],
            tips: [
                "No cutting step for accordion layouts.",
                "Panel width is stock width ÷ \(panelCount)."
            ],
            pageMapCaption: "Panels read left → right as pages 1…\(panelCount).",
            diagram: .accordion(panelCount: panelCount)
        )
    }
}

/// How pages land on the printer sheet (folio signatures vs single-sheet zines / folds).
enum ImpositionScheme: String, CaseIterable, Identifiable, Codable {
    case folioSignatures = "Signatures (folio)"
    case halfFoldBooklet = "Half-fold booklet"
    case miniZine8 = "8-page mini-zine"
    case miniZine16 = "16-page mini-zine"
    case accordion = "Accordion fold"

    var id: String { rawValue }

    var help: String {
        switch self {
        case .folioSignatures:
            return "Classic nested folio sheets — 2-up landscape printer spreads for section-sewn or saddle-stitch books."
        case .halfFoldBooklet:
            return "One nested half-fold pamphlet (saddle-stitch). Trim is your page size; printer sheet is 2-up landscape."
        case .miniZine8:
            return "One sheet → 8-page zine (4×2). Fold on dashes; cut only the solid center slit (middle two columns); collapse into a booklet. Pick a page-map template if your fold habit differs."
        case .miniZine16:
            return "One sheet → 16-page mini-zine (4×4). Fold on dashes; cut the marked slits; collapse. Choose cross-cut or horizontal slits."
        case .accordion:
            return "Linear accordion panels on one strip. Paper height is panel height; width is split across the panel count."
        }
    }

    /// Folio 2-up nesting (including the half-fold booklet preset).
    var usesFolioImpose: Bool {
        switch self {
        case .folioSignatures, .halfFoldBooklet: return true
        case .miniZine8, .miniZine16, .accordion: return false
        }
    }

    /// Single-sheet layouts where `paperSize` is the stock sheet, not page trim.
    var paperSizeIsStockSheet: Bool {
        switch self {
        case .miniZine8, .miniZine16, .accordion: return true
        case .folioSignatures, .halfFoldBooklet: return false
        }
    }

    /// Hide nested-signature picker for pamphlets and single-sheet layouts.
    var showsSignatureSize: Bool {
        self == .folioSignatures
    }

    var showsAccordionPanelCount: Bool {
        self == .accordion
    }

    var showsMiniZine8Template: Bool {
        self == .miniZine8
    }

    var showsMiniZine16Template: Bool {
        self == .miniZine16
    }

    /// Prefer no endpapers for DIY zine / fold layouts.
    var prefersZeroEndpapers: Bool {
        switch self {
        case .halfFoldBooklet, .miniZine8, .miniZine16, .accordion: return true
        case .folioSignatures: return false
        }
    }

    var printInstruction: String {
        switch self {
        case .folioSignatures, .halfFoldBooklet:
            return BindingJob.duplexHintText
        case .miniZine8:
            return "Print single-sided. Fold on dashed lines; cut only the solid center slit (middle two columns — do not cut to the sheet edges); push ends together into a booklet."
        case .miniZine16:
            return "Print single-sided. Fold on dashed lines; cut only the solid slits; collapse into a 16-page mini-zine."
        case .accordion:
            return "Print single-sided. Accordion-fold on the dashed lines (mountain / valley alternating)."
        }
    }
}

/// How sheets are nested for sewing or stitching.
enum BindingStyle: String, CaseIterable, Identifiable, Codable {
    case caseBound = "Case-bound"
    case sectionSewn = "Section-sewn"
    case perfectBound = "Perfect-bound"
    case coptic = "Coptic"
    case saddleStitch = "Saddle-stitch"

    var id: String { rawValue }

    var help: String {
        switch self {
        case .caseBound:
            return "Sewn signatures in a hard case — Auto cover uses 2 mm boards and 8 mm French grooves."
        case .sectionSewn:
            return "Sewn softcover — thinner boards and smaller grooves than a case binding."
        case .perfectBound:
            return "Trimmed block with a square-back cover wrap — no hinge gap; spine follows the glued block."
        case .coptic:
            return "Exposed chain-stitch spine — no case boards; spine adds sewing ridges only."
        case .saddleStitch:
            return "One nested signature — pamphlet cover wrap with minimal spine bulge."
        }
    }

    /// Canonical masterwork architecture for this imposition style.
    var architecture: BindingArchitecture {
        switch self {
        case .caseBound: return .caseBound
        case .sectionSewn: return .sectionSewn
        case .perfectBound: return .perfectBound
        case .coptic: return .coptic
        case .saddleStitch: return .saddleStitch
        }
    }

    /// Signature size applies to every style except saddle-stitch pamphlets.
    var usesSignatures: Bool {
        self != .saddleStitch
    }

    /// Saddle-stitch pamphlets can show staple/punch marks on the fold.
    var usesStitchHoleMarks: Bool {
        self == .saddleStitch
    }
}

/// One panel on a single-sheet layout (0-based page index within the unit).
struct SheetCellPlacement: Equatable, Codable {
    var pageIndex: Int?
    var column: Int
    var row: Int
    /// Clockwise degrees when drawing the upright page into the cell (0 / 180 for zines).
    var rotationDegrees: Int

    var label: String {
        pageIndex.map { String($0 + 1) } ?? "—"
    }
}

/// Cut or fold mark in sheet coordinates (origin bottom-left, points).
struct SheetGuideSegment: Equatable, Codable {
    enum Kind: String, Codable {
        case fold
        case cut
    }

    var kind: Kind
    var startX: CGFloat
    var startY: CGFloat
    var endX: CGFloat
    var endY: CGFloat

    var start: CGPoint {
        get { CGPoint(x: startX, y: startY) }
        set {
            startX = newValue.x
            startY = newValue.y
        }
    }

    var end: CGPoint {
        get { CGPoint(x: endX, y: endY) }
        set {
            endX = newValue.x
            endY = newValue.y
        }
    }

    init(kind: Kind, start: CGPoint, end: CGPoint) {
        self.kind = kind
        self.startX = start.x
        self.startY = start.y
        self.endX = end.x
        self.endY = end.y
    }
}

/// Flat description of one printer sheet for zine / accordion layouts.
struct SheetLayout: Equatable {
    var columns: Int
    var rows: Int
    var cells: [SheetCellPlacement]
    var guides: [SheetGuideSegment]
    /// Book pages in this unit (multiple of cells for padding).
    var pagesPerSheet: Int
}

/// Staple/punch count along the saddle-stitch fold.
enum StitchHoleCount: String, CaseIterable, Identifiable, Codable {
    case auto = "Auto"
    case one = "1"
    case two = "2"
    case three = "3"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .auto: return "Auto"
        case .one: return "1 hole"
        case .two: return "2 holes"
        case .three: return "3 holes"
        }
    }
}

/// Pages per signature (must be a multiple of 4 for folio folds).
enum SignatureSize: Int, CaseIterable, Identifiable, Codable {
    case quarto = 4
    case octavo = 8
    case duodecimo = 12
    case sextodecimo = 16
    case twentyFour = 24
    case thirtyTwo = 32

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .quarto: return "4 pages (1 sheet)"
        case .octavo: return "8 pages (2 sheets)"
        case .duodecimo: return "12 pages (3 sheets)"
        case .sextodecimo: return "16 pages (4 sheets)"
        case .twentyFour: return "24 pages (6 sheets)"
        case .thirtyTwo: return "32 pages (8 sheets)"
        }
    }

    var sheetCount: Int { rawValue / 4 }
}

struct PageNumberOptions: Equatable, Codable {
    var enabled = true
    var startAt = 1
    var position: PageNumberPosition = .bottomCenter
    var fontSize: CGFloat = 10
    /// Skip numbering on front/back endpapers.
    var skipEndpapers = true
}

enum PageNumberPosition: String, CaseIterable, Identifiable, Codable {
    case bottomCenter = "Bottom center"
    case bottomOuter = "Bottom outer"
    case topCenter = "Top center"

    var id: String { rawValue }
}

struct WatermarkOptions: Equatable, Codable {
    var enabled = false
    var text = "DRAFT"
    var opacity: Double = 0.12
    var fontSize: CGFloat = 48
    var angle: Double = -32
}

/// Optional decorative artwork for blank endpaper slots (image or PDF pages).
struct EndpaperArtwork: Equatable, Identifiable, Codable {
    let id: UUID
    var url: URL
    var name: String
    var bookmarkData: Data?
    var isPDF: Bool

    init(url: URL, isPDF: Bool) {
        self.id = UUID()
        self.url = url
        self.name = url.lastPathComponent
        self.bookmarkData = try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        self.isPDF = isPDF
    }

    func resolvedURL() -> URL {
        guard let bookmarkData else { return url }
        var isStale = false
        guard let resolved = try? URL(
            resolvingBookmarkData: bookmarkData,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            return url
        }
        return resolved
    }

    static func == (lhs: EndpaperArtwork, rhs: EndpaperArtwork) -> Bool {
        lhs.id == rhs.id
    }
}

enum EndpaperColor: String, CaseIterable, Identifiable, Codable {
    case none = "Blank"
    case archivalIvory = "Archival Ivory"
    case mistBlue = "Mist Blue"
    case sage = "Sage"
    case charcoal = "Charcoal"

    var id: String { rawValue }

    var cgColor: CGColor {
        switch self {
        case .none:
            return CGColor(gray: 1, alpha: 1)
        case .archivalIvory:
            return CGColor(red: 0.96, green: 0.94, blue: 0.86, alpha: 1)
        case .mistBlue:
            return CGColor(red: 0.86, green: 0.90, blue: 0.94, alpha: 1)
        case .sage:
            return CGColor(red: 0.82, green: 0.87, blue: 0.78, alpha: 1)
        case .charcoal:
            return CGColor(red: 0.16, green: 0.17, blue: 0.18, alpha: 1)
        }
    }
}

/// Live numbers shown in the imposition summary panel.
struct ImpositionSummary: Equatable {
    var totalPDFPages: Int
    var totalSignatures: Int
    var sheetSizeLabel: String
    var printSheetsRequired: Int
}

/// One-shot binding job configuration.
struct BindingJob: Equatable, Codable {
    var impositionScheme: ImpositionScheme = .folioSignatures
    var bindingStyle: BindingStyle = .sectionSewn
    var signatureSize: SignatureSize = .sextodecimo
    /// Page-order map for `.miniZine8` (cut geometry is shared).
    var miniZine8Template: MiniZine8Template = .classicNested
    /// Cut pattern for `.miniZine16`.
    var miniZine16Template: MiniZine16Template = .crossCut
    /// Panel count for `.accordion` (clamped 3…12).
    var accordionPanelCount = 6
    var frontEndpapers = 2
    var backEndpapers = 2
    /// Front / back decorative design (blank, solid, artwork, or procedural marbling).
    var endpapers = EndpaperDesign()

    /// Max folded endsheets per side (each sheet = 2 leaves).
    static let maxEndsheetsPerSide = 8
    static let minAccordionPanels = 3
    static let maxAccordionPanels = 12

    /// Folded endsheet count for the front (derived from leaf count; always even leaves).
    var frontEndsheets: Int {
        get { Self.endsheetCount(fromLeaves: frontEndpapers) }
        set { frontEndpapers = Self.leafCount(fromEndsheets: newValue) }
    }

    /// Folded endsheet count for the back (derived from leaf count; always even leaves).
    var backEndsheets: Int {
        get { Self.endsheetCount(fromLeaves: backEndpapers) }
        set { backEndpapers = Self.leafCount(fromEndsheets: newValue) }
    }

    /// Snap leaf counts to even pairs (one endsheet = pastedown + flyleaf).
    mutating func normalizeEndpaperLeafCounts() {
        frontEndpapers = Self.leafCount(fromEndsheets: Self.endsheetCount(fromLeaves: frontEndpapers))
        backEndpapers = Self.leafCount(fromEndsheets: Self.endsheetCount(fromLeaves: backEndpapers))
    }

    static func endsheetCount(fromLeaves leaves: Int) -> Int {
        let even = max(0, leaves) / 2 * 2
        return min(maxEndsheetsPerSide, even / 2)
    }

    static func leafCount(fromEndsheets sheets: Int) -> Int {
        min(maxEndsheetsPerSide, max(0, sheets)) * 2
    }
    var pageNumbers = PageNumberOptions()
    var watermark = WatermarkOptions()
    var addCropMarks = false
    /// Fold line + signature labels on printer spreads (handy for proofs; off for final print).
    var showGuideMarks = false
    /// Punch/staple positions on the fold for saddle-stitch spreads.
    var showStitchHoleMarks = false
    /// Staple count when stitch marks are enabled (Auto follows nested sheet count).
    var stitchHoleCount: StitchHoleCount = .auto
    var paperSize: PaperSize = .source
    /// Used when `paperSize == .custom` (PDF points, 1/72").
    var customPageWidth: CGFloat = 612
    var customPageHeight: CGFloat = 792
    /// Rotate mixed landscape/portrait pages to a common orientation before impose.
    var normalizeOrientation = true
    /// Total fore-edge shift for the innermost sheet (PDF points). 0 disables.
    /// Outer sheet stays put; inner sheets shift toward the spine proportionally.
    var creepPoints: CGFloat = 0
    /// Extra margin outside the trim box on printer spreads (PDF points). 0 = flush.
    var bleedPoints: CGFloat = 0

    /// Duplex instruction for the imposed output.
    static let duplexHintText = "Print duplex, flip on short edge (tumble). Keep sheet order."

    var duplexHint: String { impositionScheme.printInstruction }

    /// Clamped accordion panel count.
    var resolvedAccordionPanelCount: Int {
        min(Self.maxAccordionPanels, max(Self.minAccordionPanels, accordionPanelCount))
    }

    // MARK: Convenience accessors (Imposition UI / assembly)

    var frontEndpaperArtwork: EndpaperArtwork? {
        get { endpapers.front.artwork }
        set {
            endpapers.front.artwork = newValue
            if newValue != nil { endpapers.front.mode = .artwork }
            else if endpapers.front.mode == .artwork { endpapers.front.syncModeFromContents() }
        }
    }

    var backEndpaperArtwork: EndpaperArtwork? {
        get { endpapers.back.artwork }
        set {
            endpapers.back.artwork = newValue
            if newValue != nil { endpapers.back.mode = .artwork }
            else if endpapers.back.mode == .artwork { endpapers.back.syncModeFromContents() }
        }
    }

    var frontEndpaperColor: EndpaperColor {
        get { endpapers.front.solidColor }
        set {
            endpapers.front.solidColor = newValue
            if newValue != .none, endpapers.front.mode != .marbled, endpapers.front.artwork == nil {
                endpapers.front.mode = .solidColor
            } else if newValue == .none, endpapers.front.mode == .solidColor {
                endpapers.front.mode = .blank
            }
        }
    }

    var backEndpaperColor: EndpaperColor {
        get { endpapers.back.solidColor }
        set {
            endpapers.back.solidColor = newValue
            if newValue != .none, endpapers.back.mode != .marbled, endpapers.back.artwork == nil {
                endpapers.back.mode = .solidColor
            } else if newValue == .none, endpapers.back.mode == .solidColor {
                endpapers.back.mode = .blank
            }
        }
    }

    /// Resolved single-page trim size, or `nil` to keep each source page’s size.
    /// For mini-zine / accordion schemes, `paperSize` is the stock sheet and trim is derived.
    var resolvedTrimSize: CGSize? {
        guard let base = paperSize.size(customWidth: customPageWidth, customHeight: customPageHeight) else {
            return nil
        }
        return ImpositionService.pageTrimSize(stockOrTrim: base, job: self)
    }

    /// Stock sheet size for single-sheet layouts, or `nil` when using source-sized folio pages.
    var resolvedStockSheetSize: CGSize? {
        paperSize.size(customWidth: customPageWidth, customHeight: customPageHeight)
    }

    /// Apply a board/cover trim (mm) so imposition paper matches the project.
    mutating func applyProjectTrim(widthMM: Double, heightMM: Double) {
        let width = BindingMath.points(fromMillimeters: max(1, widthMM))
        let height = BindingMath.points(fromMillimeters: max(1, heightMM))

        if impositionScheme.paperSizeIsStockSheet {
            // Project trim is the panel size — recover a stock sheet that yields that panel.
            let stock: CGSize
            switch impositionScheme {
            case .miniZine8:
                stock = CGSize(width: width * 4, height: height * 2)
            case .miniZine16:
                stock = CGSize(width: width * 4, height: height * 4)
            case .accordion:
                let panels = CGFloat(resolvedAccordionPanelCount)
                stock = CGSize(width: width * panels, height: height)
            case .folioSignatures, .halfFoldBooklet:
                stock = CGSize(width: width, height: height)
            }
            let matched = PaperSize.matching(widthPoints: stock.width, heightPoints: stock.height)
            paperSize = matched
            if matched == .custom {
                customPageWidth = stock.width
                customPageHeight = stock.height
            } else if let preset = matched.size {
                customPageWidth = preset.width
                customPageHeight = preset.height
            }
            return
        }

        let matched = PaperSize.matching(widthPoints: width, heightPoints: height)
        paperSize = matched
        if matched == .custom {
            customPageWidth = width
            customPageHeight = height
        } else if let preset = matched.size {
            customPageWidth = preset.width
            customPageHeight = preset.height
        }
    }

    /// Apply a known binding architecture when it maps onto an impose style.
    mutating func applyArchitecture(_ architecture: BindingArchitecture) {
        switch architecture {
        case .caseBound: bindingStyle = .caseBound
        case .sectionSewn: bindingStyle = .sectionSewn
        case .perfectBound: bindingStyle = .perfectBound
        case .coptic: bindingStyle = .coptic
        case .saddleStitch: bindingStyle = .saddleStitch
        }
        if architecture == .saddleStitch, impositionScheme == .folioSignatures {
            // Keep folio unless the user already chose a zine layout.
        }
    }

    /// Switch layout scheme and apply sensible pamphlet / zine defaults.
    mutating func applyImpositionScheme(_ scheme: ImpositionScheme) {
        impositionScheme = scheme
        switch scheme {
        case .folioSignatures:
            break
        case .halfFoldBooklet:
            bindingStyle = .saddleStitch
            frontEndpapers = 0
            backEndpapers = 0
            showGuideMarks = true
            showStitchHoleMarks = true
            creepPoints = 0
        case .miniZine8, .miniZine16:
            bindingStyle = .saddleStitch
            frontEndpapers = 0
            backEndpapers = 0
            showGuideMarks = true
            showStitchHoleMarks = false
            creepPoints = 0
            if paperSize == .source {
                // Landscape Letter → classic ~2.75×4.25" panels on a 4×2 grid.
                paperSize = .custom
                customPageWidth = 792
                customPageHeight = 612
            }
        case .accordion:
            bindingStyle = .saddleStitch
            frontEndpapers = 0
            backEndpapers = 0
            showGuideMarks = true
            showStitchHoleMarks = false
            creepPoints = 0
            accordionPanelCount = resolvedAccordionPanelCount
            if paperSize == .source {
                paperSize = .letter
                customPageWidth = 612
                customPageHeight = 792
            }
        }
    }

    private enum CodingKeys: String, CodingKey {
        case impositionScheme, bindingStyle, signatureSize
        case miniZine8Template, miniZine16Template, accordionPanelCount
        case frontEndpapers, backEndpapers, endpapers
        case frontEndpaperArtwork, backEndpaperArtwork, frontEndpaperColor, backEndpaperColor
        case pageNumbers, watermark, addCropMarks, showGuideMarks, showStitchHoleMarks
        case stitchHoleCount, paperSize, customPageWidth, customPageHeight
        case normalizeOrientation, creepPoints, bleedPoints
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        impositionScheme = try container.decodeIfPresent(ImpositionScheme.self, forKey: .impositionScheme) ?? .folioSignatures
        bindingStyle = try container.decodeIfPresent(BindingStyle.self, forKey: .bindingStyle) ?? .sectionSewn
        signatureSize = try container.decodeIfPresent(SignatureSize.self, forKey: .signatureSize) ?? .sextodecimo
        miniZine8Template = try container.decodeIfPresent(MiniZine8Template.self, forKey: .miniZine8Template) ?? .classicNested
        miniZine16Template = try container.decodeIfPresent(MiniZine16Template.self, forKey: .miniZine16Template) ?? .crossCut
        accordionPanelCount = try container.decodeIfPresent(Int.self, forKey: .accordionPanelCount) ?? 6
        frontEndpapers = try container.decodeIfPresent(Int.self, forKey: .frontEndpapers) ?? 2
        backEndpapers = try container.decodeIfPresent(Int.self, forKey: .backEndpapers) ?? 2
        normalizeEndpaperLeafCounts()
        if let design = try container.decodeIfPresent(EndpaperDesign.self, forKey: .endpapers) {
            endpapers = design
        } else {
            var front = EndpaperFaceDesign()
            var back = EndpaperFaceDesign()
            front.artwork = try container.decodeIfPresent(EndpaperArtwork.self, forKey: .frontEndpaperArtwork)
            back.artwork = try container.decodeIfPresent(EndpaperArtwork.self, forKey: .backEndpaperArtwork)
            front.solidColor = try container.decodeIfPresent(EndpaperColor.self, forKey: .frontEndpaperColor) ?? .none
            back.solidColor = try container.decodeIfPresent(EndpaperColor.self, forKey: .backEndpaperColor) ?? .none
            front.syncModeFromContents()
            back.syncModeFromContents()
            endpapers = EndpaperDesign(front: front, back: back)
        }
        pageNumbers = try container.decodeIfPresent(PageNumberOptions.self, forKey: .pageNumbers) ?? PageNumberOptions()
        watermark = try container.decodeIfPresent(WatermarkOptions.self, forKey: .watermark) ?? WatermarkOptions()
        addCropMarks = try container.decodeIfPresent(Bool.self, forKey: .addCropMarks) ?? false
        showGuideMarks = try container.decodeIfPresent(Bool.self, forKey: .showGuideMarks) ?? false
        showStitchHoleMarks = try container.decodeIfPresent(Bool.self, forKey: .showStitchHoleMarks) ?? false
        stitchHoleCount = try container.decodeIfPresent(StitchHoleCount.self, forKey: .stitchHoleCount) ?? .auto
        paperSize = try container.decodeIfPresent(PaperSize.self, forKey: .paperSize) ?? .source
        customPageWidth = try container.decodeIfPresent(CGFloat.self, forKey: .customPageWidth) ?? 612
        customPageHeight = try container.decodeIfPresent(CGFloat.self, forKey: .customPageHeight) ?? 792
        normalizeOrientation = try container.decodeIfPresent(Bool.self, forKey: .normalizeOrientation) ?? true
        creepPoints = try container.decodeIfPresent(CGFloat.self, forKey: .creepPoints) ?? 0
        bleedPoints = try container.decodeIfPresent(CGFloat.self, forKey: .bleedPoints) ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(impositionScheme, forKey: .impositionScheme)
        try container.encode(bindingStyle, forKey: .bindingStyle)
        try container.encode(signatureSize, forKey: .signatureSize)
        try container.encode(miniZine8Template, forKey: .miniZine8Template)
        try container.encode(miniZine16Template, forKey: .miniZine16Template)
        try container.encode(accordionPanelCount, forKey: .accordionPanelCount)
        try container.encode(frontEndpapers, forKey: .frontEndpapers)
        try container.encode(backEndpapers, forKey: .backEndpapers)
        try container.encode(endpapers, forKey: .endpapers)
        try container.encode(pageNumbers, forKey: .pageNumbers)
        try container.encode(watermark, forKey: .watermark)
        try container.encode(addCropMarks, forKey: .addCropMarks)
        try container.encode(showGuideMarks, forKey: .showGuideMarks)
        try container.encode(showStitchHoleMarks, forKey: .showStitchHoleMarks)
        try container.encode(stitchHoleCount, forKey: .stitchHoleCount)
        try container.encode(paperSize, forKey: .paperSize)
        try container.encode(customPageWidth, forKey: .customPageWidth)
        try container.encode(customPageHeight, forKey: .customPageHeight)
        try container.encode(normalizeOrientation, forKey: .normalizeOrientation)
        try container.encode(creepPoints, forKey: .creepPoints)
        try container.encode(bleedPoints, forKey: .bleedPoints)
    }
}

enum PaperSize: String, CaseIterable, Identifiable, Codable {
    case source = "Keep source size"
    case letter = "US Letter"
    case a4 = "A4"
    case a5 = "A5"
    case custom = "Custom…"

    var id: String { rawValue }

    var size: CGSize? {
        size(customWidth: 612, customHeight: 792)
    }

    func size(customWidth: CGFloat, customHeight: CGFloat) -> CGSize? {
        // PDF points (1/72")
        switch self {
        case .source: return nil
        case .letter: return CGSize(width: 612, height: 792)
        case .a4: return CGSize(width: 595.28, height: 841.89)
        case .a5: return CGSize(width: 419.53, height: 595.28)
        case .custom:
            return CGSize(
                width: max(72, customWidth),
                height: max(72, customHeight)
            )
        }
    }

    /// Presets that resolve to a fixed trim (excludes `.source` / `.custom`).
    static var measurableCases: [PaperSize] { [.letter, .a4, .a5] }

    /// Pick a named paper size when dimensions match a preset; otherwise `.custom`.
    static func matching(
        widthPoints: CGFloat,
        heightPoints: CGFloat,
        tolerancePoints: CGFloat = 1.5
    ) -> PaperSize {
        let w = max(72, widthPoints)
        let h = max(72, heightPoints)
        for preset in measurableCases {
            guard let size = preset.size else { continue }
            let upright =
                abs(size.width - w) <= tolerancePoints && abs(size.height - h) <= tolerancePoints
            let rotated =
                abs(size.width - h) <= tolerancePoints && abs(size.height - w) <= tolerancePoints
            if upright || rotated {
                return preset
            }
        }
        return .custom
    }
}

struct BindingPlan: Equatable {
    var contentPageCount: Int
    var frontEndpapers: Int
    var backEndpapers: Int
    var padPages: Int
    var signatureCount: Int
    var pagesPerSignature: Int
    var totalBookPages: Int
    /// Physical sheets to print (folio: nested sheets; zine/accordion: one per unit).
    var printSheetsRequired: Int
    var impositionScheme: ImpositionScheme

    var summary: String {
        var parts: [String] = []
        parts.append("\(contentPageCount) content")
        if frontEndpapers + backEndpapers > 0 {
            parts.append("\(frontEndpapers + backEndpapers) endpapers")
        }
        if padPages > 0 {
            parts.append("\(padPages) blanks to fill")
        }
        switch impositionScheme {
        case .folioSignatures, .halfFoldBooklet:
            parts.append("\(signatureCount) × \(pagesPerSignature)-page signatures")
        case .miniZine8:
            parts.append("\(printSheetsRequired) × 8-page mini-zine sheet\(printSheetsRequired == 1 ? "" : "s")")
        case .miniZine16:
            parts.append("\(printSheetsRequired) × 16-page mini-zine sheet\(printSheetsRequired == 1 ? "" : "s")")
        case .accordion:
            parts.append("\(printSheetsRequired) × \(pagesPerSignature)-panel accordion")
        }
        return parts.joined(separator: " · ")
    }

    var sheetCount: Int { printSheetsRequired }

    /// Summary card metrics for the sidebar.
    func impositionSummary(sheetSizeLabel: String) -> ImpositionSummary {
        ImpositionSummary(
            totalPDFPages: totalBookPages,
            totalSignatures: signatureCount,
            sheetSizeLabel: sheetSizeLabel,
            printSheetsRequired: printSheetsRequired
        )
    }
}

/// Ordered pre-imposition book-block input. Source ranges keep assembly separate
/// from the raw source list; blanks and covers are project-specific pages.
struct BookBlockItem: Identifiable, Equatable, Codable {
    enum Kind: String, Codable {
        case sourceRange
        case blank
        case frontCover
        case backCover
    }

    var id: UUID
    var kind: Kind
    var sourceID: UUID?
    /// Zero-based inclusive page range within the source document.
    var pageRange: ClosedRange<Int>?
    var rotationDegrees: Int
    var label: String

    init(
        id: UUID = UUID(),
        kind: Kind,
        sourceID: UUID? = nil,
        pageRange: ClosedRange<Int>? = nil,
        rotationDegrees: Int = 0,
        label: String
    ) {
        self.id = id
        self.kind = kind
        self.sourceID = sourceID
        self.pageRange = pageRange
        self.rotationDegrees = rotationDegrees
        self.label = label
    }

    var pageCount: Int {
        switch kind {
        case .blank, .frontCover, .backCover:
            return 1
        case .sourceRange:
            guard let pageRange else { return 0 }
            return max(0, pageRange.upperBound - pageRange.lowerBound + 1)
        }
    }

    static func sourceRange(source: SourceDocument) -> BookBlockItem {
        BookBlockItem(
            kind: .sourceRange,
            sourceID: source.id,
            pageRange: 0...max(0, source.pageCount - 1),
            label: source.name
        )
    }

    static func blank(label: String = "Blank page") -> BookBlockItem {
        BookBlockItem(kind: .blank, label: label)
    }

    static func cover(_ kind: Kind) -> BookBlockItem {
        BookBlockItem(kind: kind, label: kind == .frontCover ? "Front cover slot" : "Back cover slot")
    }
}

/// One side of a printer sheet in the signature map (1-based book page numbers).
struct SignatureSheetSide: Equatable, Identifiable {
    var id: String { "\(signatureIndex)-\(sheetIndex)-\(face)-\(gridLabel ?? label)" }
    var signatureIndex: Int
    var sheetIndex: Int
    var face: Face
    var leftPage: Int?
    var rightPage: Int?
    /// Optional row label for multi-cell sheet layouts (zines / accordion).
    var gridLabel: String?

    enum Face: String, Equatable {
        case front
        case back
    }

    var label: String {
        if let gridLabel { return gridLabel }
        let left = leftPage.map(String.init) ?? "—"
        let right = rightPage.map(String.init) ?? "—"
        return "\(left) | \(right)"
    }
}

struct SignatureMap: Equatable {
    var sides: [SignatureSheetSide]
    var plan: BindingPlan
    var sheetLayouts: [SheetLayout] = []

    func sides(forSignature signatureIndex: Int) -> [SignatureSheetSide] {
        sides.filter { $0.signatureIndex == signatureIndex }
    }
}

enum BindingError: LocalizedError {
    case noDocuments
    case emptyDocument
    case exportFailed
    case invalidConfiguration(String)

    var errorDescription: String? {
        switch self {
        case .noDocuments: return "Add at least one PDF to bind."
        case .emptyDocument: return "The selected PDF has no pages."
        case .exportFailed: return "Could not write the bound PDF."
        case .invalidConfiguration(let message): return message
        }
    }
}
