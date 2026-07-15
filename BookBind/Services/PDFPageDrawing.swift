import AppKit
import CoreGraphics
import Foundation
import PDFKit

/// Reliable drawing of `PDFPage` into a `CGPDFContext`.
/// Prefers vector/`CGPDFPage` drawing so text and paths stay selectable;
/// falls back to a high-DPI raster when `pageRef` is unavailable.
enum PDFPageDrawing {
    /// Draw `page` scaled to fill `dest` (PDF coordinates, origin bottom-left).
    static func draw(_ page: PDFPage, in context: CGContext, dest: CGRect) {
        guard dest.width > 0, dest.height > 0 else { return }

        if drawVector(page, in: context, dest: dest) {
            return
        }
        drawRaster(page, in: context, dest: dest)
    }

    /// Vector path via `CGPDFPage` + drawing transform.
    @discardableResult
    private static func drawVector(_ page: PDFPage, in context: CGContext, dest: CGRect) -> Bool {
        guard let pageRef = page.pageRef else { return false }

        let mediaBox = pageRef.getBoxRect(.mediaBox)
        guard mediaBox.width > 0, mediaBox.height > 0 else { return false }

        // `rotate: 0` — the page dictionary’s /Rotate is already applied by
        // getDrawingTransform. Destinations are sized with displaySize (rotation-aware).
        let transform = pageRef.getDrawingTransform(
            .mediaBox,
            rect: dest,
            rotate: 0,
            preserveAspectRatio: false
        )

        context.saveGState()
        context.clip(to: dest)
        context.concatenate(transform)
        context.drawPDFPage(pageRef)
        context.restoreGState()
        return true
    }

    /// High-DPI bitmap (matches what PDFView renders) — last resort.
    private static func drawRaster(_ page: PDFPage, in context: CGContext, dest: CGRect) {
        let dpi: CGFloat = 200
        let pixelSize = CGSize(
            width: max(1, (dest.width * dpi / 72).rounded(.up)),
            height: max(1, (dest.height * dpi / 72).rounded(.up))
        )
        let image = page.thumbnail(of: pixelSize, for: .mediaBox)
        guard let cgImage = cgImage(from: image) else { return }

        context.saveGState()
        context.interpolationQuality = .high
        context.clip(to: dest)
        context.draw(cgImage, in: dest)
        context.restoreGState()
    }

    private static func cgImage(from image: NSImage) -> CGImage? {
        var rect = NSRect(origin: .zero, size: image.size)
        if let direct = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) {
            return direct
        }
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else {
            return nil
        }
        return rep.cgImage
    }
}
