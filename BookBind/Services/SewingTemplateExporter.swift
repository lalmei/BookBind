import AppKit
import CoreGraphics
import Foundation

/// Writes a 1:1 PDF punching guide: lay the strip in a signature's fold and pierce at each mark.
enum SewingTemplateExporter {
    private static let margin = 15.0
    private static let stripDepth = 30.0

    /// PDF data for the template; page size fits the strip plus margins and a scale check bar.
    static func pdfData(plan: CalculatorMath.SewingPlan, spineHeight: Double) -> Data {
        let pt = CalculatorMath.pointsPerMillimeter
        let pageW = (spineHeight + 2 * margin) * pt
        let pageH = (stripDepth + 2 * margin + 30) * pt
        var mediaBox = CGRect(x: 0, y: 0, width: pageW, height: pageH)
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let pdf = CGContext(consumer: consumer, mediaBox: &mediaBox, [
                  kCGPDFContextTitle as String: "Sewing station template"
              ] as CFDictionary)
        else { return Data() }

        pdf.beginPDFPage(nil)
        // Work in millimeters from the top-left.
        pdf.translateBy(x: 0, y: pageH)
        pdf.scaleBy(x: pt, y: -pt)

        let strip = CGRect(x: margin, y: margin, width: spineHeight, height: stripDepth)
        pdf.setStrokeColor(NSColor.black.cgColor)
        pdf.setLineWidth(0.25)
        pdf.stroke(strip)

        let foldY = strip.midY
        pdf.setLineDash(phase: 0, lengths: [2, 1])
        pdf.move(to: CGPoint(x: strip.minX, y: foldY))
        pdf.addLine(to: CGPoint(x: strip.maxX, y: foldY))
        pdf.strokePath()
        pdf.setLineDash(phase: 0, lengths: [])

        for (index, offset) in plan.stations.enumerated() {
            let x = margin + offset
            // Crosshair plus a 1 mm ring — pierce at the center.
            pdf.move(to: CGPoint(x: x, y: strip.minY))
            pdf.addLine(to: CGPoint(x: x, y: strip.maxY))
            pdf.strokePath()
            pdf.strokeEllipse(in: CGRect(x: x - 1, y: foldY - 1, width: 2, height: 2))
            let isKettle = index == 0 || index == plan.stations.count - 1
            drawText(isKettle ? "K" : "\(index)", at: CGPoint(x: x + 1, y: strip.minY + 1), in: pdf)
            drawText(String(format: "%.1f", offset), at: CGPoint(x: x + 1, y: strip.maxY - 4), in: pdf)
        }
        drawText("HEAD", at: CGPoint(x: strip.minX, y: strip.minY - 5), in: pdf)
        drawText("TAIL", at: CGPoint(x: strip.maxX - 9, y: strip.minY - 5), in: pdf)

        // Scale check: print at 100% / "Actual Size" and this bar must measure 50 mm.
        let barY = strip.maxY + 12
        pdf.setLineWidth(0.5)
        pdf.move(to: CGPoint(x: margin, y: barY))
        pdf.addLine(to: CGPoint(x: margin + 50, y: barY))
        for tick in stride(from: 0.0, through: 50, by: 10) {
            pdf.move(to: CGPoint(x: margin + tick, y: barY - 1.5))
            pdf.addLine(to: CGPoint(x: margin + tick, y: barY + 1.5))
        }
        pdf.strokePath()
        drawText("50 mm — print at Actual Size and check this bar", at: CGPoint(x: margin + 54, y: barY - 1.5), in: pdf)

        pdf.endPDFPage()
        pdf.closePDF()
        return data as Data
    }

    @MainActor
    static func export(plan: CalculatorMath.SewingPlan, spineHeight: Double) {
        let panel = NSSavePanel()
        panel.title = "Export Punching Template"
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = String(format: "Sewing template %.0f mm.pdf", spineHeight)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try pdfData(plan: plan, spineHeight: spineHeight).write(to: url, options: .atomic)
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    /// Draws a small label in millimeter space (the context is y-flipped, so flip text back).
    private static func drawText(_ string: String, at point: CGPoint, in context: CGContext) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 2.6, weight: .regular),
            .foregroundColor: NSColor.black
        ]
        context.saveGState()
        context.translateBy(x: point.x, y: point.y + 2.6)
        context.scaleBy(x: 1, y: -1)
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: attributes))
        context.textPosition = .zero
        CTLineDraw(line, context)
        context.restoreGState()
    }
}
