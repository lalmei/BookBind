import AppKit
import CoreGraphics
import CoreText
import Foundation

/// Printer's marks for imposed sheets: crop marks outside the bleed, bleed marks, fold marks at
/// the spine, and a slug line that identifies the sheet. Approach modelled on DesignCraft's
/// `marks.rs` (storytold/designcraft, MIT OR Apache-2.0); independent Swift implementation.
enum PrinterMarks {
    /// Gap between the bleed edge and where marks start, so marks never touch printed artwork.
    static let offset: CGFloat = 3
    static let length: CGFloat = 12
    static let lineWidth: CGFloat = 0.3

    /// Space needed around the trimmed area on every side.
    static func margin(bleed: CGFloat, marks: Bool) -> CGFloat {
        let bleed = max(0, bleed)
        return marks ? bleed + offset + length + 2 : bleed
    }

    /// Distance from the trim to where crop marks start.
    static func markStart(bleed: CGFloat) -> CGFloat {
        max(0, bleed) + offset
    }

    /// Crop + bleed marks around `trim`, and dashed fold marks at each x in `foldXs`.
    static func draw(in context: CGContext, trim: CGRect, bleed: CGFloat, foldXs: [CGFloat] = []) {
        let bleed = max(0, bleed)
        let start = markStart(bleed: bleed)
        context.saveGState()
        context.setStrokeColor(CGColor(gray: 0, alpha: 1))
        context.setLineWidth(lineWidth)
        context.setLineDash(phase: 0, lengths: [])

        // Crop marks: at each trim corner, one horizontal and one vertical, outside the bleed.
        for (x, sx) in [(trim.minX, CGFloat(-1)), (trim.maxX, 1)] {
            for (y, sy) in [(trim.minY, CGFloat(-1)), (trim.maxY, 1)] {
                context.move(to: CGPoint(x: x + sx * start, y: y))
                context.addLine(to: CGPoint(x: x + sx * (start + length), y: y))
                context.move(to: CGPoint(x: x, y: y + sy * start))
                context.addLine(to: CGPoint(x: x, y: y + sy * (start + length)))
            }
        }

        // Bleed marks: shorter ticks on the bleed lines, beside the crop marks.
        if bleed > 0 {
            let half = length / 2
            for (x, sx) in [(trim.minX, CGFloat(-1)), (trim.maxX, 1)] {
                for (y, sy) in [(trim.minY, CGFloat(-1)), (trim.maxY, 1)] {
                    let by = y + sy * bleed
                    let bx = x + sx * bleed
                    context.move(to: CGPoint(x: x + sx * start, y: by))
                    context.addLine(to: CGPoint(x: x + sx * (start + half), y: by))
                    context.move(to: CGPoint(x: bx, y: y + sy * start))
                    context.addLine(to: CGPoint(x: bx, y: y + sy * (start + half)))
                }
            }
        }
        context.strokePath()

        // Fold marks: dashed, above and below the sheet — a fold, never a cut.
        if !foldXs.isEmpty {
            context.setLineDash(phase: 0, lengths: [2, 1.5])
            for x in foldXs {
                context.move(to: CGPoint(x: x, y: trim.minY - start))
                context.addLine(to: CGPoint(x: x, y: trim.minY - start - length))
                context.move(to: CGPoint(x: x, y: trim.maxY + start))
                context.addLine(to: CGPoint(x: x, y: trim.maxY + start + length))
            }
            context.strokePath()
        }
        context.restoreGState()
    }

    /// One-line sheet identity in the bottom margin, clear of the corner marks.
    static func drawSlug(_ text: String, in context: CGContext, trim: CGRect, bleed: CGFloat) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 5.5, weight: .regular),
            .foregroundColor: NSColor.black
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        context.saveGState()
        context.textPosition = CGPoint(
            x: trim.minX + 6,
            y: trim.minY - markStart(bleed: bleed) - 8
        )
        CTLineDraw(line, context)
        context.restoreGState()
    }

    /// "Title · Sig 2 of 8 · Sheet 3 Back · pp 21–28 · 2026-10-12" (empty parts dropped).
    static func slugText(title: String?, parts: [String], date: Date = Date()) -> String {
        let day = date.formatted(.iso8601.year().month().day())
        let trimmedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return ([trimmedTitle] + parts + [day]).filter { !$0.isEmpty }.joined(separator: " · ")
    }

    static func pageRange(_ pages: [Int?]) -> String {
        let numbers = pages.compactMap { $0 }.map { $0 + 1 }
        guard let low = numbers.min(), let high = numbers.max() else { return "" }
        return low == high ? "p \(low)" : "pp \(low)–\(high)"
    }
}
