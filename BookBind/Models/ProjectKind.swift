import Foundation

/// What the New Masterwork sheet offers: every bound book and every one-sheet fold the
/// app can produce, described in the binder's terms rather than as raw settings.
enum ProjectKind: String, CaseIterable, Identifiable {
    case caseBound
    case sectionSewn
    case perfectBound
    case coptic
    case pamphlet
    case miniZine8
    case miniZine16
    case halfFoldBooklet
    case accordion

    var id: String { rawValue }

    enum Group: String, CaseIterable {
        case books = "Books"
        case folds = "Zines & Folds"
    }

    static func kinds(in group: Group) -> [ProjectKind] {
        allCases.filter { $0.group == group }
    }

    var group: Group {
        switch self {
        case .caseBound, .sectionSewn, .perfectBound, .coptic, .pamphlet: return .books
        case .miniZine8, .miniZine16, .halfFoldBooklet, .accordion: return .folds
        }
    }

    var title: String {
        switch self {
        case .caseBound: return "Case Bound"
        case .sectionSewn: return "Section-sewn"
        case .perfectBound: return "Perfect Bound"
        case .coptic: return "Coptic"
        case .pamphlet: return "Pamphlet"
        case .miniZine8: return "8-Page Mini-Zine"
        case .miniZine16: return "16-Page Mini-Zine"
        case .halfFoldBooklet: return "Half-Fold Booklet"
        case .accordion: return "Accordion"
        }
    }

    var summary: String {
        switch self {
        case .caseBound:
            return "Sewn signatures cased into hard boards with a wrapped spine — the classic cloth or leather hardback."
        case .sectionSewn:
            return "Folded signatures sewn through the fold into a durable block, finished in a soft or limp cover."
        case .perfectBound:
            return "Single leaves glued at the spine into a flexible wrap — paperback style, no folding or sewing."
        case .coptic:
            return "Signatures chain-stitched straight to separate boards. The sewing stays exposed and the book opens flat."
        case .pamphlet:
            return "One nested signature stitched or stapled through the fold. Quick, thin, and elegant."
        case .miniZine8:
            return "One sheet, one cut, a few folds → an 8-page pocket zine. No glue, no staples."
        case .miniZine16:
            return "One sheet folded into a 4×4 grid with slits cut through the middle → a 16-page mini-zine."
        case .halfFoldBooklet:
            return "Printer sheets folded in half and nested, then stapled through the spine. A classic small-press zine."
        case .accordion:
            return "One long strip folded back and forth into panels — reads as a book or stands open as a frieze."
        }
    }

    /// Short "what you're signing up for" facts shown under the preview.
    var facts: [String] {
        switch self {
        case .caseBound:
            return ["Folded signatures", "Sewn", "2 boards + spine", "Turn-ins"]
        case .sectionSewn:
            return ["Folded signatures", "Sewn through folds", "Soft cover"]
        case .perfectBound:
            return ["Single leaves", "Glued spine", "Wrap cover"]
        case .coptic:
            return ["Folded signatures", "Chain stitch", "Exposed spine", "Lays flat"]
        case .pamphlet:
            return ["1 signature", "Stitched or stapled", "Duplex print"]
        case .miniZine8:
            return ["1 sheet", "8 pages", "1 cut", "Single-sided print"]
        case .miniZine16:
            return ["1 sheet", "16 pages", "2 cuts", "Single-sided print"]
        case .halfFoldBooklet:
            return ["Nested sheets", "Fold in half", "Staple spine", "Duplex print"]
        case .accordion:
            return ["1 strip", "6 panels", "Zig-zag folds", "No cuts"]
        }
    }

    var architecture: BindingArchitecture {
        switch self {
        case .caseBound: return .caseBound
        case .sectionSewn: return .sectionSewn
        case .perfectBound: return .perfectBound
        case .coptic: return .coptic
        case .pamphlet, .miniZine8, .miniZine16, .halfFoldBooklet, .accordion: return .saddleStitch
        }
    }

    /// Fold layouts imposed from one stock sheet; `nil` for bound books (folio signatures).
    var scheme: ImpositionScheme? {
        switch self {
        case .miniZine8: return .miniZine8
        case .miniZine16: return .miniZine16
        case .halfFoldBooklet: return .halfFoldBooklet
        case .accordion: return .accordion
        default: return nil
        }
    }

    /// Fold projects size their pages from the stock sheet instead of a typed trim.
    var usesStockSheet: Bool { scheme != nil }

    /// Tools unlocked at creation. Folds don't need cover, endpapers, or a 3D case.
    var enabledTools: Set<ProjectTool> {
        usesStockSheet ? [.imposition, .materials] : Set(ProjectTool.allCases)
    }

    var defaultTrim: (width: Double, height: Double) {
        switch self {
        case .pamphlet: return (140, 216)
        case .coptic: return (148, 210)
        default: return (152, 229)
        }
    }

    /// Page trim produced by folding a landscape stock sheet with this layout.
    func pageSize(fromStock stock: StockSheet) -> (width: Double, height: Double) {
        let w = stock.longMM
        let h = stock.shortMM
        switch self {
        case .miniZine8: return (w / 4, h / 2)
        case .miniZine16: return (w / 4, h / 4)
        case .halfFoldBooklet: return (w / 2, h)
        case .accordion: return (w / 6, h)
        default: return defaultTrim
        }
    }
}

/// Common printer stock for fold projects, always laid out landscape.
enum StockSheet: String, CaseIterable, Identifiable {
    case letter = "US Letter"
    case a4 = "A4"
    case tabloid = "Tabloid 11×17"
    case a3 = "A3"

    var id: String { rawValue }

    var longMM: Double {
        switch self {
        case .letter: return 279.4
        case .a4: return 297
        case .tabloid: return 431.8
        case .a3: return 420
        }
    }

    var shortMM: Double {
        switch self {
        case .letter: return 215.9
        case .a4: return 210
        case .tabloid: return 279.4
        case .a3: return 297
        }
    }
}

/// Everything the New Masterwork sheet hands to `AppStore`.
struct NewProjectRequest {
    var title: String
    var author: String
    var kind: ProjectKind
    var widthMM: Double
    var heightMM: Double
    var stock: StockSheet
}
