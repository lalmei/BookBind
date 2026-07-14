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
    /// Indices are 0-based within the signature.
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

    /// Impose a linear book-block PDF into printer spreads (2-up sheets).
    static func impose(
        bookBlock: PDFDocument,
        plan: BindingPlan,
        style: BindingStyle,
        addCropMarks: Bool
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

        for sig in 0..<signatureCount {
            let start = sig * signatureLength
            let sides = folioSheetSides(pageCount: signatureLength)

            for side in sides {
                let leftGlobal = side.left.map { start + $0 }
                let rightGlobal = side.right.map { start + $0 }

                let leftPage = leftGlobal.flatMap { bookBlock.page(at: $0) }
                let rightPage = rightGlobal.flatMap { bookBlock.page(at: $0) }

                let spread = makeSpread(
                    left: leftPage,
                    right: rightPage,
                    pageSize: pageSize,
                    addCropMarks: addCropMarks,
                    signatureLabel: style == .sectionSewn ? "Sig \(sig + 1)" : nil
                )
                output.insert(spread, at: outIndex)
                outIndex += 1
            }
        }

        return output
    }

    private static func makeSpread(
        left: PDFPage?,
        right: PDFPage?,
        pageSize: CGSize,
        addCropMarks: Bool,
        signatureLabel: String?
    ) -> PDFPage {
        let spreadWidth = pageSize.width * 2
        let spreadHeight = pageSize.height
        let spreadBounds = CGRect(x: 0, y: 0, width: spreadWidth, height: spreadHeight)

        let data = renderSpreadPDF(
            left: left,
            right: right,
            pageSize: pageSize,
            bounds: spreadBounds,
            addCropMarks: addCropMarks,
            signatureLabel: signatureLabel
        )

        if let doc = PDFDocument(data: data), let page = doc.page(at: 0) {
            return page
        }

        // Fallback empty page
        let page = PDFPage()
        page.setBounds(spreadBounds, for: .mediaBox)
        return page
    }

    private static func renderSpreadPDF(
        left: PDFPage?,
        right: PDFPage?,
        pageSize: CGSize,
        bounds: CGRect,
        addCropMarks: Bool,
        signatureLabel: String?
    ) -> Data {
        let mutableData = NSMutableData()
        var mediaBox = bounds
        guard let consumer = CGDataConsumer(data: mutableData as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            return Data()
        }

        context.beginPage(mediaBox: &mediaBox)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(bounds)

        // Draw left page
        if let left {
            context.saveGState()
            let leftBounds = left.bounds(for: .mediaBox)
            let sx = pageSize.width / leftBounds.width
            let sy = pageSize.height / leftBounds.height
            context.translateBy(x: 0, y: 0)
            context.scaleBy(x: sx, y: sy)
            left.draw(with: .mediaBox, to: context)
            context.restoreGState()
        }

        // Draw right page
        if let right {
            context.saveGState()
            let rightBounds = right.bounds(for: .mediaBox)
            let sx = pageSize.width / rightBounds.width
            let sy = pageSize.height / rightBounds.height
            context.translateBy(x: pageSize.width, y: 0)
            context.scaleBy(x: sx, y: sy)
            right.draw(with: .mediaBox, to: context)
            context.restoreGState()
        }

        // Fold line
        context.saveGState()
        context.setStrokeColor(CGColor(gray: 0.75, alpha: 1))
        context.setLineWidth(0.5)
        context.setLineDash(phase: 0, lengths: [3, 3])
        context.move(to: CGPoint(x: pageSize.width, y: 0))
        context.addLine(to: CGPoint(x: pageSize.width, y: pageSize.height))
        context.strokePath()
        context.restoreGState()

        if addCropMarks {
            drawCropMarks(in: context, pageSize: pageSize, spreadBounds: bounds)
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

    private static func drawCropMarks(in context: CGContext, pageSize: CGSize, spreadBounds: CGRect) {
        let mark: CGFloat = 12
        let inset: CGFloat = 0
        context.saveGState()
        context.setStrokeColor(CGColor(gray: 0, alpha: 1))
        context.setLineWidth(0.4)
        context.setLineDash(phase: 0, lengths: [])

        func markCorner(x: CGFloat, y: CGFloat, dx: CGFloat, dy: CGFloat) {
            context.move(to: CGPoint(x: x + dx * inset, y: y))
            context.addLine(to: CGPoint(x: x + dx * mark, y: y))
            context.move(to: CGPoint(x: x, y: y + dy * inset))
            context.addLine(to: CGPoint(x: x, y: y + dy * mark))
        }

        // Outer corners of spread
        markCorner(x: 0, y: 0, dx: 1, dy: 1)
        markCorner(x: spreadBounds.width, y: 0, dx: -1, dy: 1)
        markCorner(x: 0, y: spreadBounds.height, dx: 1, dy: -1)
        markCorner(x: spreadBounds.width, y: spreadBounds.height, dx: -1, dy: -1)

        // Spine corners
        markCorner(x: pageSize.width, y: 0, dx: -1, dy: 1)
        markCorner(x: pageSize.width, y: 0, dx: 1, dy: 1)
        markCorner(x: pageSize.width, y: spreadBounds.height, dx: -1, dy: -1)
        markCorner(x: pageSize.width, y: spreadBounds.height, dx: 1, dy: -1)

        context.strokePath()
        context.restoreGState()
    }
}
