import Foundation
import PDFKit

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
    var bindingStyle: BindingStyle = .sectionSewn
    var signatureSize: SignatureSize = .sextodecimo
    var frontEndpapers = 2
    var backEndpapers = 2
    /// Front / back decorative design (blank, solid, artwork, or procedural marbling).
    var endpapers = EndpaperDesign()

    /// Max folded endsheets per side (each sheet = 2 leaves).
    static let maxEndsheetsPerSide = 8

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

    var duplexHint: String { Self.duplexHintText }

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
    var resolvedTrimSize: CGSize? {
        paperSize.size(customWidth: customPageWidth, customHeight: customPageHeight)
    }

    /// Apply a board/cover trim (mm) so imposition paper matches the project.
    mutating func applyProjectTrim(widthMM: Double, heightMM: Double) {
        let width = BindingMath.points(fromMillimeters: max(1, widthMM))
        let height = BindingMath.points(fromMillimeters: max(1, heightMM))
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
    }

    private enum CodingKeys: String, CodingKey {
        case bindingStyle, signatureSize, frontEndpapers, backEndpapers, endpapers
        case frontEndpaperArtwork, backEndpaperArtwork, frontEndpaperColor, backEndpaperColor
        case pageNumbers, watermark, addCropMarks, showGuideMarks, showStitchHoleMarks
        case stitchHoleCount, paperSize, customPageWidth, customPageHeight
        case normalizeOrientation, creepPoints, bleedPoints
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        bindingStyle = try container.decodeIfPresent(BindingStyle.self, forKey: .bindingStyle) ?? .sectionSewn
        signatureSize = try container.decodeIfPresent(SignatureSize.self, forKey: .signatureSize) ?? .sextodecimo
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
        try container.encode(bindingStyle, forKey: .bindingStyle)
        try container.encode(signatureSize, forKey: .signatureSize)
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

    var summary: String {
        var parts: [String] = []
        parts.append("\(contentPageCount) content")
        if frontEndpapers + backEndpapers > 0 {
            parts.append("\(frontEndpapers + backEndpapers) endpapers")
        }
        if padPages > 0 {
            parts.append("\(padPages) blanks to fill")
        }
        parts.append("\(signatureCount) × \(pagesPerSignature)-page signatures")
        return parts.joined(separator: " · ")
    }

    var sheetCount: Int {
        signatureCount * (pagesPerSignature / 4)
    }

    /// Summary card metrics for the sidebar.
    func impositionSummary(sheetSizeLabel: String) -> ImpositionSummary {
        ImpositionSummary(
            totalPDFPages: totalBookPages,
            totalSignatures: signatureCount,
            sheetSizeLabel: sheetSizeLabel,
            printSheetsRequired: sheetCount
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
    var id: String { "\(signatureIndex)-\(sheetIndex)-\(face)" }
    var signatureIndex: Int
    var sheetIndex: Int
    var face: Face
    var leftPage: Int?
    var rightPage: Int?

    enum Face: String, Equatable {
        case front
        case back
    }

    var label: String {
        let left = leftPage.map(String.init) ?? "—"
        let right = rightPage.map(String.init) ?? "—"
        return "\(left) | \(right)"
    }
}

struct SignatureMap: Equatable {
    var sides: [SignatureSheetSide]
    var plan: BindingPlan

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
