import Foundation
import SwiftUI

/// The bench calculators available on the Calculators page.
enum CalculatorKind: String, CaseIterable, Identifiable {
    case caseBinding
    case signatures
    case sewing
    case sheetYield
    case paper

    var id: String { rawValue }

    var title: String {
        switch self {
        case .caseBinding: return "Case & Boards"
        case .signatures: return "Signatures"
        case .sewing: return "Sewing"
        case .sheetYield: return "Sheet Yield"
        case .paper: return "Paper"
        }
    }

    var help: String {
        switch self {
        case .caseBinding: return "Board, spine stiffener, and covering material sizes with a cutting layout"
        case .signatures: return "Signature count, blank pages to add, and fore-edge creep"
        case .sewing: return "Sewing station positions, a 1:1 punching template, and thread length"
        case .sheetYield: return "How many grain-correct folios a parent sheet yields"
        case .paper: return "GSM, bond, caliper, and pages-per-inch reference"
        }
    }
}

/// One set of inputs shared by every calculator, so the book you describe once
/// (trim, pages, paper) carries across Case, Signatures, Sewing, and Sheet Yield.
/// Owned by `AppStore` so numbers survive leaving the page.
@MainActor
final class CalculatorSession: ObservableObject {
    // Book
    @Published var pageWidth: Double = 148
    @Published var pageHeight: Double = 210
    @Published var pageCount: Int = 256
    @Published var gsm: Double = 80

    // Case
    @Published var boardThickness: Double = 2.0
    @Published var square: Double = 3
    @Published var jointGap: Double = 7
    @Published var boardSetback: Double = 3
    @Published var turnIn: Double = 15

    // Signatures
    @Published var sheetsPerSignature: Int = 4

    // Sewing
    @Published var stationCount: Int = 6
    @Published var kettleInset: Double = 12

    // Sheet yield
    @Published var parentWidth: Double = 594
    @Published var parentHeight: Double = 841
    @Published var parentGrain: CalculatorMath.GrainDirection = .long
    @Published var trimAllowance: Double = 3

    var casePlan: CalculatorMath.CasePlan {
        CalculatorMath.casePlan(CalculatorMath.CaseInputs(
            blockWidth: pageWidth,
            blockHeight: pageHeight,
            pageCount: pageCount,
            gsm: gsm,
            boardThickness: boardThickness,
            square: square,
            jointGap: jointGap,
            boardSetback: boardSetback,
            turnIn: turnIn
        ))
    }

    var signaturePlan: CalculatorMath.SignaturePlan {
        CalculatorMath.signaturePlan(CalculatorMath.SignatureInputs(
            pageCount: pageCount,
            sheetsPerSignature: sheetsPerSignature,
            gsm: gsm
        ))
    }

    var sewingPlan: CalculatorMath.SewingPlan {
        CalculatorMath.sewingPlan(CalculatorMath.SewingInputs(
            spineHeight: pageHeight,
            stationCount: stationCount,
            kettleInset: kettleInset,
            signatureCount: signaturePlan.signatureCount
        ))
    }

    var yieldPlan: CalculatorMath.YieldPlan {
        CalculatorMath.yieldPlan(CalculatorMath.YieldInputs(
            parentWidth: parentWidth,
            parentHeight: parentHeight,
            parentGrain: parentGrain,
            pageWidth: pageWidth,
            pageHeight: pageHeight,
            trimAllowance: trimAllowance,
            pageCount: pageCount
        ))
    }

    /// Pulls trim, page count, paper, and board settings from a saved project.
    func fill(from project: BinderyProject, assembledPageCount: Int) {
        pageWidth = project.widthMM
        pageHeight = project.heightMM
        let pages = assembledPageCount > 0 ? assembledPageCount : project.estimatedPageCount
        if pages > 0 { pageCount = pages }
        gsm = project.textPaperGSM
        boardThickness = project.boardThicknessMM
        jointGap = project.hingeGapMM
    }

    func applyParentPreset(_ preset: CalculatorMath.ParentSheet) {
        parentWidth = preset.width
        parentHeight = preset.height
    }
}
