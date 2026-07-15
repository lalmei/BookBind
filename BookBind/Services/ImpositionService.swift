import AppKit
import CoreText
import Foundation
import PDFKit

/// Plans and imposes folio signatures for physical binding.
enum ImpositionService {
    /// Compute padding and signature count for a section-sewn or saddle-stitch job.
    static func plan(
        contentPageCount: Int,
        job: BindingJob
    ) -> BindingPlan {
        let endpapers = max(0, job.frontEndpapers) + max(0, job.backEndpapers)
        let rawTotal = contentPageCount + endpapers

        let pagesPerSignature: Int
        let signatureCount: Int
        let padPages: Int

        switch job.bindingStyle {
        case .saddleStitch:
            // One signature; pad to multiple of 4.
            pagesPerSignature = ((rawTotal + 3) / 4) * 4
            signatureCount = pagesPerSignature == 0 ? 0 : 1
            padPages = max(0, pagesPerSignature - rawTotal)
        case .sectionSewn:
            let size = job.signatureSize.rawValue
            pagesPerSignature = size
            let padded = ((rawTotal + size - 1) / size) * size
            signatureCount = padded == 0 ? 0 : padded / size
            padPages = max(0, padded - rawTotal)
        }

        return BindingPlan(
            contentPageCount: contentPageCount,
            frontEndpapers: max(0, job.frontEndpapers),
            backEndpapers: max(0, job.backEndpapers),
            padPages: padPages,
            signatureCount: signatureCount,
            pagesPerSignature: pagesPerSignature,
            totalBookPages: rawTotal + padPages
        )
    }

    /// Folio sheet order for a signature of `pageCount` pages (multiple of 4).
    /// Returns pairs of (leftPageIndex, rightPageIndex) for each side of each sheet,
    /// in print order: sheet0-front, sheet0-back, sheet1-front, ...
    /// Indices are 0-based within the signature. Sheet 0 is the outermost nest.
    static func folioSheetSides(pageCount: Int) -> [(left: Int?, right: Int?)] {
        precondition(pageCount % 4 == 0 && pageCount > 0)
        let sheets = pageCount / 4
        var sides: [(left: Int?, right: Int?)] = []

        for sheet in 0..<sheets {
            // Outer face (front of sheet when stacked for nesting):
            // left = last - 2*sheet, right = 1 + 2*sheet  (1-based thinking)
            let frontLeft = pageCount - 1 - (sheet * 2)
            let frontRight = sheet * 2
            sides.append((frontLeft, frontRight))

            // Inner face (back of sheet):
            let backLeft = sheet * 2 + 1
            let backRight = pageCount - 2 - (sheet * 2)
            sides.append((backLeft, backRight))
        }

        return sides
    }

    /// Horizontal shift toward the spine for a nested sheet.
    /// Sheet 0 (outer) → 0; innermost → `totalCreep`.
    static func creepOffset(
        sheetIndex: Int,
        sheetCount: Int,
        totalCreep: CGFloat
    ) -> CGFloat {
        guard totalCreep > 0, sheetCount > 1, sheetIndex > 0 else { return 0 }
        let clamped = min(max(sheetIndex, 0), sheetCount - 1)
        return totalCreep * CGFloat(clamped) / CGFloat(sheetCount - 1)
    }

    /// Media size of one printer spread given trim page size, bleed, and crop-mark room.
    static func spreadMediaSize(
        pageSize: CGSize,
        bleed: CGFloat,
        addCropMarks: Bool
    ) -> CGSize {
        let bleed = max(0, bleed)
        let markRoom: CGFloat = addCropMarks ? max(14, bleed > 0 ? 0 : 14) : 0
        // Crop marks sit in the bleed band when bleed is large enough; otherwise add a slim margin.
        let outer = max(bleed, markRoom)
        return CGSize(
            width: pageSize.width * 2 + outer * 2,
            height: pageSize.height + outer * 2
        )
    }

    /// Human-readable label for the 2-up printer sheet (trim size, not including bleed).
    static func printerSheetLabel(pageSize: CGSize) -> String {
        func approx(_ a: CGSize, _ b: CGSize, tolerance: CGFloat = 3) -> Bool {
            abs(a.width - b.width) <= tolerance && abs(a.height - b.height) <= tolerance
        }

        let letter = CGSize(width: 612, height: 792)
        let a4 = CGSize(width: 595.28, height: 841.89)
        let a5 = CGSize(width: 419.53, height: 595.28)
        let landscapeLetter = CGSize(width: 792, height: 612)
        let landscapeA4 = CGSize(width: 841.89, height: 595.28)
        let landscapeA5 = CGSize(width: 595.28, height: 419.53)

        if approx(pageSize, letter) || approx(pageSize, landscapeLetter) {
            return "Tabloid Landscape"
        }
        if approx(pageSize, a4) || approx(pageSize, landscapeA4) {
            return "A3 Landscape"
        }
        if approx(pageSize, a5) || approx(pageSize, landscapeA5) {
            return "A4 Landscape"
        }

        let sheet = CGSize(width: pageSize.width * 2, height: pageSize.height)
        let wIn = sheet.width / 72
        let hIn = sheet.height / 72
        return String(format: "%.1f×%.1f in", wIn, hIn)
    }

    /// Impose a linear book-block PDF into printer spreads (2-up sheets).
    static func impose(
        bookBlock: PDFDocument,
        plan: BindingPlan,
        style: BindingStyle,
        addCropMarks: Bool,
        showGuideMarks: Bool,
        creepPoints: CGFloat = 0,
        bleedPoints: CGFloat = 0
    ) throws -> PDFDocument {
        guard bookBlock.pageCount > 0 else { throw BindingError.emptyDocument }
        guard plan.totalBookPages == bookBlock.pageCount else {
            throw BindingError.invalidConfiguration(
                "Book block page count (\(bookBlock.pageCount)) does not match plan (\(plan.totalBookPages))."
            )
        }

        let pageSize = PDFDocumentService.pageSize(of: bookBlock)
        let output = PDFDocument()
        var outIndex = 0

        let signatureLength = plan.pagesPerSignature
        let signatureCount = plan.signatureCount
        let sheetsPerSignature = max(1, signatureLength / 4)
        let creep = max(0, creepPoints)
        let bleed = max(0, bleedPoints)

        for sig in 0..<signatureCount {
            let start = sig * signatureLength
            let sides = folioSheetSides(pageCount: signatureLength)

            for (sideIndex, side) in sides.enumerated() {
                let sheetIndex = sideIndex / 2
                let offset = creepOffset(
                    sheetIndex: sheetIndex,
                    sheetCount: sheetsPerSignature,
                    totalCreep: creep
                )

                let leftGlobal = side.left.map { start + $0 }
                let rightGlobal = side.right.map { start + $0 }

                let leftPage = leftGlobal.flatMap { bookBlock.page(at: $0) }
                let rightPage = rightGlobal.flatMap { bookBlock.page(at: $0) }

                let signatureLabel: String? = {
                    guard showGuideMarks, style == .sectionSewn else { return nil }
                    return "Sig \(sig + 1)"
                }()

                let mediaSize = spreadMediaSize(
                    pageSize: pageSize,
                    bleed: bleed,
                    addCropMarks: addCropMarks
                )
                let spreadBounds = CGRect(origin: .zero, size: mediaSize)

                let data = renderSpreadPDF(
                    left: leftPage,
                    right: rightPage,
                    pageSize: pageSize,
                    bounds: spreadBounds,
                    addCropMarks: addCropMarks,
                    showFoldLine: showGuideMarks,
                    signatureLabel: signatureLabel,
                    creepOffset: offset,
                    bleed: bleed
                )

                // Insert while the temporary document is still alive — returning a
                // PDFPage from a deallocated PDFDocument yields blank pages in PDFView.
                guard let spreadDoc = PDFDocument(data: data),
                      let spreadPage = spreadDoc.page(at: 0) else {
                    continue
                }
                output.insert(spreadPage, at: outIndex)
                outIndex += 1
            }
        }

        return output
    }

    /// Human-readable signature map with 1-based book page numbers.
    static func signatureMap(for plan: BindingPlan) -> SignatureMap {
        guard plan.signatureCount > 0, plan.pagesPerSignature > 0 else {
            return SignatureMap(sides: [], plan: plan)
        }

        var sides: [SignatureSheetSide] = []
        let length = plan.pagesPerSignature

        for sig in 0..<plan.signatureCount {
            let start = sig * length
            let folio = folioSheetSides(pageCount: length)
            for (index, side) in folio.enumerated() {
                let sheetIndex = index / 2
                let face: SignatureSheetSide.Face = index % 2 == 0 ? .front : .back
                sides.append(
                    SignatureSheetSide(
                        signatureIndex: sig + 1,
                        sheetIndex: sheetIndex + 1,
                        face: face,
                        leftPage: side.left.map { start + $0 + 1 },
                        rightPage: side.right.map { start + $0 + 1 }
                    )
                )
            }
        }

        return SignatureMap(sides: sides, plan: plan)
    }

    private static func renderSpreadPDF(
        left: PDFPage?,
        right: PDFPage?,
        pageSize: CGSize,
        bounds: CGRect,
        addCropMarks: Bool,
        showFoldLine: Bool,
        signatureLabel: String?,
        creepOffset: CGFloat,
        bleed: CGFloat
    ) -> Data {
        let mutableData = NSMutableData()
        var mediaBox = bounds
        guard let consumer = CGDataConsumer(data: mutableData as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            return Data()
        }

        let outer = (bounds.width - pageSize.width * 2) / 2
        let trimOrigin = CGPoint(x: outer, y: (bounds.height - pageSize.height) / 2)
        let spineX = trimOrigin.x + pageSize.width

        context.beginPage(mediaBox: &mediaBox)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(bounds)

        // Left page: shift toward spine (+x) by creep; content may extend into bleed.
        if let left {
            drawPage(
                left,
                in: context,
                trimRect: CGRect(origin: trimOrigin, size: pageSize),
                bleed: bleed,
                contentOffsetX: creepOffset
            )
        }

        // Right page: shift toward spine (−x) by creep.
        if let right {
            drawPage(
                right,
                in: context,
                trimRect: CGRect(
                    x: spineX,
                    y: trimOrigin.y,
                    width: pageSize.width,
                    height: pageSize.height
                ),
                bleed: bleed,
                contentOffsetX: -creepOffset
            )
        }

        if showFoldLine {
            context.saveGState()
            context.setStrokeColor(CGColor(gray: 0.75, alpha: 1))
            context.setLineWidth(0.5)
            context.setLineDash(phase: 0, lengths: [3, 3])
            context.move(to: CGPoint(x: spineX, y: trimOrigin.y))
            context.addLine(to: CGPoint(x: spineX, y: trimOrigin.y + pageSize.height))
            context.strokePath()
            context.restoreGState()
        }

        if addCropMarks {
            drawCropMarks(
                in: context,
                trimOrigin: trimOrigin,
                pageSize: pageSize,
                spreadBounds: bounds
            )
        }

        if let signatureLabel {
            context.saveGState()
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 7),
                .foregroundColor: NSColor.disabledControlTextColor
            ]
            let str = NSAttributedString(string: signatureLabel, attributes: attrs)
            let line = CTLineCreateWithAttributedString(str)
            context.textPosition = CGPoint(x: 6, y: 4)
            CTLineDraw(line, context)
            context.restoreGState()
        }

        context.endPage()
        context.closePDF()
        return mutableData as Data
    }

    /// Draw a page into its trim rect, allowing content to spill into the bleed band.
    private static func drawPage(
        _ page: PDFPage,
        in context: CGContext,
        trimRect: CGRect,
        bleed: CGFloat,
        contentOffsetX: CGFloat
    ) {
        let source = page.bounds(for: .mediaBox)
        guard source.width > 0, source.height > 0 else { return }

        // Clip to trim + bleed so creep/bleed don't paint into the opposite page or marks.
        let clip = trimRect.insetBy(dx: -bleed, dy: -bleed)
        let dest = CGRect(
            x: trimRect.minX + contentOffsetX,
            y: trimRect.minY,
            width: trimRect.width,
            height: trimRect.height
        )

        context.saveGState()
        context.clip(to: clip)
        PDFPageDrawing.draw(page, in: context, dest: dest)
        context.restoreGState()
    }

    private static func drawCropMarks(
        in context: CGContext,
        trimOrigin: CGPoint,
        pageSize: CGSize,
        spreadBounds: CGRect
    ) {
        let mark: CGFloat = 12
        let gap: CGFloat = 2
        context.saveGState()
        context.setStrokeColor(CGColor(gray: 0, alpha: 1))
        context.setLineWidth(0.4)
        context.setLineDash(phase: 0, lengths: [])

        func markCorner(x: CGFloat, y: CGFloat, dx: CGFloat, dy: CGFloat) {
            // Marks sit just outside the trim, leaving a small gap.
            context.move(to: CGPoint(x: x + dx * gap, y: y))
            context.addLine(to: CGPoint(x: x + dx * (gap + mark), y: y))
            context.move(to: CGPoint(x: x, y: y + dy * gap))
            context.addLine(to: CGPoint(x: x, y: y + dy * (gap + mark)))
        }

        let left = trimOrigin.x
        let right = trimOrigin.x + pageSize.width * 2
        let bottom = trimOrigin.y
        let top = trimOrigin.y + pageSize.height
        let spine = trimOrigin.x + pageSize.width

        // Outer corners of the spread trim
        markCorner(x: left, y: bottom, dx: -1, dy: -1)
        markCorner(x: right, y: bottom, dx: 1, dy: -1)
        markCorner(x: left, y: top, dx: -1, dy: 1)
        markCorner(x: right, y: top, dx: 1, dy: 1)

        // Spine / fold corners
        markCorner(x: spine, y: bottom, dx: -1, dy: -1)
        markCorner(x: spine, y: bottom, dx: 1, dy: -1)
        markCorner(x: spine, y: top, dx: -1, dy: 1)
        markCorner(x: spine, y: top, dx: 1, dy: 1)

        // Keep marks inside media when possible
        _ = spreadBounds

        context.strokePath()
        context.restoreGState()
    }
}
