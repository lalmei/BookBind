import AppKit
import Foundation
import PDFKit

/// Adds page numbers and watermarks to a linear book-block PDF (before imposition).
enum PageDecorationService {
    static func decorate(
        _ document: PDFDocument,
        pageNumbers: PageNumberOptions,
        watermark: WatermarkOptions,
        frontEndpapers: Int,
        backEndpapers: Int
    ) -> PDFDocument {
        guard pageNumbers.enabled || watermark.enabled else { return document }

        let output = PDFDocument()
        let total = document.pageCount
        let contentStart = max(0, frontEndpapers)
        let contentEnd = total - max(0, backEndpapers) - 1

        for index in 0..<total {
            guard let page = document.page(at: index) else { continue }
            let bounds = page.bounds(for: .mediaBox)

            let isEndpaper = index < contentStart || index > contentEnd
            let shouldNumber = pageNumbers.enabled && !(pageNumbers.skipEndpapers && isEndpaper)

            var numberText: String?
            if shouldNumber {
                let number = pageNumbers.startAt + (index - contentStart)
                if number > 0 {
                    numberText = "\(number)"
                }
            }

            let decorated = renderDecoratedPage(
                page: page,
                bounds: bounds,
                numberText: numberText,
                numberOptions: pageNumbers,
                watermark: watermark.enabled ? watermark : nil,
                pageIndex: index,
                totalPages: total
            )
            output.insert(decorated, at: index)
        }

        return output
    }

    private static func renderDecoratedPage(
        page: PDFPage,
        bounds: CGRect,
        numberText: String?,
        numberOptions: PageNumberOptions,
        watermark: WatermarkOptions?,
        pageIndex: Int,
        totalPages: Int
    ) -> PDFPage {
        let mutableData = NSMutableData()
        var mediaBox = bounds
        guard let consumer = CGDataConsumer(data: mutableData as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            return page
        }

        context.beginPage(mediaBox: &mediaBox)
        page.draw(with: .mediaBox, to: context)

        if let watermark {
            drawWatermark(watermark, in: context, bounds: bounds)
        }

        if let numberText {
            drawPageNumber(
                numberText,
                options: numberOptions,
                in: context,
                bounds: bounds,
                pageIndex: pageIndex
            )
        }

        context.endPage()
        context.closePDF()

        if let doc = PDFDocument(data: mutableData as Data), let newPage = doc.page(at: 0) {
            return newPage
        }
        return page
    }

    private static func drawWatermark(_ options: WatermarkOptions, in context: CGContext, bounds: CGRect) {
        context.saveGState()
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: options.fontSize, weight: .bold),
            .foregroundColor: NSColor.black.withAlphaComponent(options.opacity)
        ]
        let str = NSAttributedString(string: options.text, attributes: attrs)
        let line = CTLineCreateWithAttributedString(str)
        let lineBounds = CTLineGetBoundsWithOptions(line, [])

        context.translateBy(x: bounds.midX, y: bounds.midY)
        context.rotate(by: CGFloat(options.angle * .pi / 180))
        context.textPosition = CGPoint(x: -lineBounds.width / 2, y: -lineBounds.height / 2)
        CTLineDraw(line, context)
        context.restoreGState()
    }

    private static func drawPageNumber(
        _ text: String,
        options: PageNumberOptions,
        in context: CGContext,
        bounds: CGRect,
        pageIndex: Int
    ) {
        context.saveGState()
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: options.fontSize),
            .foregroundColor: NSColor.black
        ]
        let str = NSAttributedString(string: text, attributes: attrs)
        let line = CTLineCreateWithAttributedString(str)
        let lineBounds = CTLineGetBoundsWithOptions(line, [])
        let margin: CGFloat = 28

        let x: CGFloat
        let y: CGFloat

        switch options.position {
        case .bottomCenter:
            x = bounds.midX - lineBounds.width / 2
            y = margin
        case .topCenter:
            x = bounds.midX - lineBounds.width / 2
            y = bounds.height - margin - lineBounds.height
        case .bottomOuter:
            // Odd pages (recto, 0-based even index after start) → outer right; verso → outer left.
            // Approximate: even index = verso (left), odd = recto (right) for 0-based content.
            let isRecto = pageIndex % 2 == 1
            x = isRecto ? bounds.width - margin - lineBounds.width : margin
            y = margin
        }

        context.textPosition = CGPoint(x: x, y: y)
        CTLineDraw(line, context)
        context.restoreGState()
    }
}
