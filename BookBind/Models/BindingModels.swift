import Foundation
import PDFKit

/// How sheets are nested for sewing or stitching.
enum BindingStyle: String, CaseIterable, Identifiable {
    case sectionSewn = "Section-sewn"
    case saddleStitch = "Saddle-stitch"

    var id: String { rawValue }

    var help: String {
        switch self {
        case .sectionSewn:
            return "Multiple signatures of a fixed page count — typical for casebound and sewn books."
        case .saddleStitch:
            return "One nested signature for the whole book — pamphlets and thin booklets."
        }
    }
}

/// Pages per signature (must be a multiple of 4 for folio folds).
enum SignatureSize: Int, CaseIterable, Identifiable {
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

struct PageNumberOptions: Equatable {
    var enabled = true
    var startAt = 1
    var position: PageNumberPosition = .bottomCenter
    var fontSize: CGFloat = 10
    /// Skip numbering on front/back endpapers.
    var skipEndpapers = true
}

enum PageNumberPosition: String, CaseIterable, Identifiable {
    case bottomCenter = "Bottom center"
    case bottomOuter = "Bottom outer"
    case topCenter = "Top center"

    var id: String { rawValue }
}

struct WatermarkOptions: Equatable {
    var enabled = false
    var text = "DRAFT"
    var opacity: Double = 0.12
    var fontSize: CGFloat = 48
    var angle: Double = -32
}

/// One-shot binding job configuration.
struct BindingJob: Equatable {
    var bindingStyle: BindingStyle = .sectionSewn
    var signatureSize: SignatureSize = .sextodecimo
    var frontEndpapers = 2
    var backEndpapers = 2
    var pageNumbers = PageNumberOptions()
    var watermark = WatermarkOptions()
    var addCropMarks = false
    var paperSize: PaperSize = .source
}

enum PaperSize: String, CaseIterable, Identifiable {
    case source = "Keep source size"
    case letter = "US Letter"
    case a4 = "A4"
    case a5 = "A5"

    var id: String { rawValue }

    var size: CGSize? {
        // PDF points (1/72")
        switch self {
        case .source: return nil
        case .letter: return CGSize(width: 612, height: 792)
        case .a4: return CGSize(width: 595.28, height: 841.89)
        case .a5: return CGSize(width: 419.53, height: 595.28)
        }
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
