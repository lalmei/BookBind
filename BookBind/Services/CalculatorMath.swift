import Foundation

/// Bench calculators for hand binders. All lengths are millimeters unless a name says otherwise.
///
/// Each plan is a pure value computed from its inputs, so the views only draw — and the
/// same numbers feed the on-screen blueprints, the 1:1 templates, and the unit tests.
enum CalculatorMath {
    static let pointsPerMillimeter = 72.0 / 25.4

    // MARK: - Case binding: boards, spine, covering material

    struct CaseInputs: Equatable {
        var blockWidth: Double = 148
        var blockHeight: Double = 210
        var pageCount: Int = 256
        var gsm: Double = 80
        var boardThickness: Double = 2.0
        /// Board overhang beyond the text block at head, tail, and fore-edge.
        var square: Double = 3
        /// Gap between each board and the spine stiffener (the hinge the cover flexes on).
        var jointGap: Double = 7
        /// How far the board sits back from the spine fold so it clears the shoulder.
        var boardSetback: Double = 3
        /// Covering material folded over the board edges.
        var turnIn: Double = 15
    }

    struct CasePlan: Equatable {
        var blockThickness: Double
        var boardWidth: Double
        var boardHeight: Double
        var spineWidth: Double
        var jointGap: Double
        var turnIn: Double
        var coverWidth: Double
        var coverHeight: Double
        /// Distance from each board corner to the 45° corner cut, so the turn-ins meet neatly.
        var cornerCutOffset: Double

        /// Boards + joints + spine, without turn-ins (the visible case width).
        var caseWidth: Double { 2 * boardWidth + 2 * jointGap + spineWidth }
    }

    static func casePlan(_ input: CaseInputs) -> CasePlan {
        let block = textBlockThickness(pageCount: input.pageCount, gsm: input.gsm)
        let board = max(0, input.boardThickness)
        let square = max(0, input.square)
        let boardWidth = max(0, input.blockWidth - max(0, input.boardSetback) + square)
        let boardHeight = max(0, input.blockHeight + 2 * square)
        // The stiffener spans the block plus both boards' edges so the case closes square.
        let spineWidth = block + 2 * board
        let joint = max(0, input.jointGap)
        let turnIn = max(0, input.turnIn)
        return CasePlan(
            blockThickness: block,
            boardWidth: boardWidth,
            boardHeight: boardHeight,
            spineWidth: spineWidth,
            jointGap: joint,
            turnIn: turnIn,
            coverWidth: 2 * boardWidth + 2 * joint + spineWidth + 2 * turnIn,
            coverHeight: boardHeight + 2 * turnIn,
            // Leave ~1.5 board thicknesses of material at the corner to wrap the board edge.
            cornerCutOffset: board * 1.5
        )
    }

    // MARK: - Signatures & creep

    struct SignatureInputs: Equatable {
        var pageCount: Int = 256
        /// Folded sheets (folios) nested in one signature.
        var sheetsPerSignature: Int = 4
        var gsm: Double = 80
    }

    struct SignaturePlan: Equatable {
        var pagesPerSignature: Int
        var signatureCount: Int
        var blankPages: Int
        var totalSheets: Int
        /// Innermost sheet's fore-edge protrusion past the outermost sheet.
        var creepMM: Double
        var creepPoints: Double { creepMM * CalculatorMath.pointsPerMillimeter }
        var blockThickness: Double
    }

    static func signaturePlan(_ input: SignatureInputs) -> SignaturePlan {
        let sheets = max(1, input.sheetsPerSignature)
        let pps = sheets * 4
        let pages = max(0, input.pageCount)
        let count = pages == 0 ? 0 : Int((Double(pages) / Double(pps)).rounded(.up))
        let padded = count * pps
        return SignaturePlan(
            pagesPerSignature: pps,
            signatureCount: count,
            blankPages: padded - pages,
            totalSheets: count * sheets,
            // Each folded sheet wraps the ones inside it, pushing them out by ~one caliper.
            creepMM: Double(sheets - 1) * sheetCaliper(gsm: input.gsm),
            blockThickness: textBlockThickness(pageCount: padded, gsm: input.gsm)
        )
    }

    // MARK: - Sewing stations

    struct SewingInputs: Equatable {
        var spineHeight: Double = 210
        /// Total holes per signature, including the two kettle stations.
        var stationCount: Int = 6
        /// Kettle stitch distance from head and tail.
        var kettleInset: Double = 12
        var signatureCount: Int = 16
    }

    struct SewingPlan: Equatable {
        /// Hole positions measured from the head, in order.
        var stations: [Double]
        var spacing: Double
        /// Rule of thumb: one spine height per signature plus two for tails and tie-offs.
        var threadLength: Double
    }

    static func sewingPlan(_ input: SewingInputs) -> SewingPlan {
        let height = max(0, input.spineHeight)
        let count = max(2, input.stationCount)
        let inset = min(max(0, input.kettleInset), height / 2)
        let span = height - 2 * inset
        let spacing = span / Double(count - 1)
        let stations = (0..<count).map { inset + Double($0) * spacing }
        return SewingPlan(
            stations: stations,
            spacing: spacing,
            threadLength: height * Double(max(0, input.signatureCount) + 2)
        )
    }

    // MARK: - Sheet yield (folios cut from a parent sheet, grain-aware)

    enum GrainDirection: String, CaseIterable, Identifiable {
        case long = "Long grain"
        case short = "Short grain"
        var id: String { rawValue }
    }

    struct ParentSheet: Identifiable, Hashable {
        var name: String
        var width: Double
        var height: Double
        var id: String { name }

        static let presets: [ParentSheet] = [
            ParentSheet(name: "A1", width: 594, height: 841),
            ParentSheet(name: "A2", width: 420, height: 594),
            ParentSheet(name: "A3", width: 297, height: 420),
            ParentSheet(name: "SRA3", width: 320, height: 450),
            ParentSheet(name: "Letter", width: 215.9, height: 279.4),
            ParentSheet(name: "Tabloid 11×17", width: 279.4, height: 431.8),
            ParentSheet(name: "Text 19×25", width: 482.6, height: 635),
            ParentSheet(name: "Text 25×38", width: 635, height: 965.2)
        ]
    }

    struct YieldInputs: Equatable {
        var parentWidth: Double = 594
        var parentHeight: Double = 841
        var parentGrain: GrainDirection = .long
        var pageWidth: Double = 148
        var pageHeight: Double = 210
        /// Extra trimmed off each folio edge after sewing.
        var trimAllowance: Double = 3
        var pageCount: Int = 256
    }

    struct YieldPlan: Equatable {
        /// Flat folio size before folding (two pages side by side), including trim allowance.
        var folioWidth: Double
        var folioHeight: Double
        /// Folio grid placed with the grain parallel to the fold (correct for binding).
        var columns: Int
        var rows: Int
        /// Whether the folio is turned 90° on the parent sheet to keep grain on the fold.
        var rotated: Bool
        /// Count if grain were ignored — shown so binders see what correct grain costs.
        var crossGrainCount: Int
        var parentSheetsNeeded: Int
        var wastePercent: Double

        var perSheet: Int { columns * rows }
    }

    static func yieldPlan(_ input: YieldInputs) -> YieldPlan {
        let trim = max(0, input.trimAllowance)
        let folioW = 2 * max(0, input.pageWidth) + 2 * trim
        let folioH = max(0, input.pageHeight) + 2 * trim
        let pw = max(0, input.parentWidth)
        let ph = max(0, input.parentHeight)

        // Grain runs parallel to the parent's long side for long grain, short side otherwise.
        let grainAlongHeight = (input.parentGrain == .long) == (ph >= pw)
        // The fold (folio height) must run with the grain.
        let rotated = !grainAlongHeight
        let placedW = rotated ? folioH : folioW
        let placedH = rotated ? folioW : folioH
        let columns = fit(placedW, in: pw)
        let rows = fit(placedH, in: ph)

        let crossColumns = fit(rotated ? folioW : folioH, in: pw)
        let crossRows = fit(rotated ? folioH : folioW, in: ph)

        let perSheet = columns * rows
        let foliosNeeded = Int((Double(max(0, input.pageCount)) / 4).rounded(.up))
        let sheetsNeeded = perSheet > 0 ? Int((Double(foliosNeeded) / Double(perSheet)).rounded(.up)) : 0
        let parentArea = pw * ph
        let used = Double(perSheet) * folioW * folioH
        return YieldPlan(
            folioWidth: folioW,
            folioHeight: folioH,
            columns: columns,
            rows: rows,
            rotated: rotated,
            crossGrainCount: crossColumns * crossRows,
            parentSheetsNeeded: sheetsNeeded,
            wastePercent: parentArea > 0 ? max(0, 1 - used / parentArea) * 100 : 0
        )
    }

    private static func fit(_ item: Double, in space: Double) -> Int {
        guard item > 0 else { return 0 }
        return Int((space / item).rounded(.down))
    }

    // MARK: - Paper

    /// Uncoated book paper caliper estimate (≈ GSM / 800 mm, i.e. ~100 µm at 80 gsm).
    static func sheetCaliper(gsm: Double) -> Double {
        BindingMath.sheetThicknessMM(gsm: gsm)
    }

    static func textBlockThickness(pageCount: Int, gsm: Double) -> Double {
        BindingMath.textBlockThicknessMM(pageCount: pageCount, gsm: gsm)
    }

    /// Pages per inch of block thickness — the figure paper merchants quote.
    static func pagesPerInch(gsm: Double) -> Double {
        let caliper = sheetCaliper(gsm: gsm)
        return caliper > 0 ? 2 * 25.4 / caliper : 0
    }
}
