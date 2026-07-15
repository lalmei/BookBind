import CoreGraphics
import Foundation

/// Standalone binding arithmetic for calculators and cover spine estimates.
enum BindingMath {
    /// PDF points per millimeter (72 pt/in ÷ 25.4 mm/in).
    static let pointsPerMillimeter: CGFloat = 72.0 / 25.4

    static func points(fromMillimeters mm: Double) -> CGFloat {
        CGFloat(mm) * pointsPerMillimeter
    }

    static func millimeters(fromPoints points: CGFloat) -> Double {
        Double(points / pointsPerMillimeter)
    }

    /// Rough sheet caliper (mm) from GSM for uncoated book paper.
    static func sheetThicknessMM(gsm: Double) -> Double {
        max(0.04, gsm / 800.0)
    }

    /// Text-block thickness from leaf count (pages / 2 sheets) and paper GSM.
    static func textBlockThicknessMM(pageCount: Int, gsm: Double) -> Double {
        guard pageCount > 0 else { return 0 }
        let sheets = Double(pageCount) / 2.0
        return sheets * sheetThicknessMM(gsm: gsm)
    }

    /// Case-style spine wrap: text block + boards + hinge gaps on both sides.
    static func caseSpineWidthMM(
        pageCount: Int,
        gsm: Double,
        boardThicknessMM: Double,
        hingeGapMM: Double
    ) -> Double {
        let block = textBlockThicknessMM(pageCount: pageCount, gsm: gsm)
        return block + (boardThicknessMM * 2) + (hingeGapMM * 2)
    }

    /// Suggested creep (PDF points) for a signature from GSM and sheets-per-signature.
    /// Scale is intentionally conservative; binders can refine from a proof.
    static func suggestedCreepPoints(gsm: Double, sheetsPerSignature: Int) -> Double {
        guard sheetsPerSignature > 1 else { return 0 }
        let perSheet = sheetThicknessMM(gsm: gsm) * 2.0 // mm → ~pt (1mm ≈ 2.83pt; use ~2 for modest shift)
        return Double(sheetsPerSignature - 1) * perSheet
    }

    /// Convert GSM area weight to lb bond (approx US text).
    static func gsmToBondLb(_ gsm: Double) -> Double {
        gsm * 0.266
    }

    static func bondLbToGSM(_ lb: Double) -> Double {
        lb / 0.266
    }
}
