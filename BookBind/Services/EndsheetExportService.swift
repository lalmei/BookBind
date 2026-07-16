import AppKit
import CoreGraphics
import Foundation
import PDFKit
import UniformTypeIdentifiers

/// Flat folded endsheet export (SVG + blueprint PDF) and shared sheet rendering.
enum EndsheetBlueprintService {
    static func writeSVG(
        face: EndpaperFaceDesign,
        geometry: EndsheetGeometry,
        isFront: Bool,
        projectTitle: String,
        to url: URL
    ) throws {
        let margin = 12.0
        let canvasW = geometry.totalW + margin * 2
        let canvasH = geometry.leafH + margin * 2 + 28
        let fmt: (Double) -> String = { String(format: "%.3f", $0) }

        let leftZone = geometry.zone(forHalfIndex: 0, isFront: isFront)
        let rightZone = geometry.zone(forHalfIndex: 1, isFront: isFront)

        var fillSVG = ""
        switch face.mode {
        case .blank:
            fillSVG = """
            <rect x="0" y="0" width="\(fmt(geometry.totalW))" height="\(fmt(geometry.leafH))" fill="#ffffff" stroke="#c8c8c8" stroke-width="0.25"/>
            """
        case .solidColor:
            let hex = svgHex(face.solidColor.cgColor)
            fillSVG = """
            <rect x="0" y="0" width="\(fmt(geometry.totalW))" height="\(fmt(geometry.leafH))" fill="\(hex)" stroke="#002045" stroke-width="0.25"/>
            """
        case .marbled, .artwork:
            // Vector export of bitmap fills: paper plate + note for production bitmap/PDF.
            fillSVG = """
            <rect x="0" y="0" width="\(fmt(geometry.totalW))" height="\(fmt(geometry.leafH))" fill="#f7f4ec" stroke="#002045" stroke-width="0.25"/>
            <text x="\(fmt(geometry.totalW / 2))" y="\(fmt(geometry.leafH / 2))" text-anchor="middle" font-family="system-ui, sans-serif" font-size="4" fill="#74777f">\(face.mode.title) — export blueprint PDF for preview</text>
            """
        }

        let guideOpacity = face.showFoldGuides ? "1" : "0"
        let svg = """
        <?xml version="1.0" encoding="UTF-8"?>
        <svg xmlns="http://www.w3.org/2000/svg" width="\(fmt(canvasW))mm" height="\(fmt(canvasH))mm" viewBox="0 0 \(fmt(canvasW)) \(fmt(canvasH))">
          <title>\(escapeXML(projectTitle)) — \(isFront ? "Front" : "Back") endsheet</title>
          <g transform="translate(\(fmt(margin)), \(fmt(margin + 16)))">
            <text x="0" y="-8" font-family="system-ui, sans-serif" font-size="3.2" fill="#74777f" letter-spacing="0.4">FLAT ENDSHEET \(fmt(geometry.totalW)) × \(fmt(geometry.leafH)) mm — fold at \(fmt(geometry.foldXMM)) mm</text>
            \(fillSVG)
            <g opacity="\(guideOpacity)">
              <line x1="\(fmt(geometry.foldXMM))" y1="0" x2="\(fmt(geometry.foldXMM))" y2="\(fmt(geometry.leafH))" stroke="#002045" stroke-width="0.35" stroke-dasharray="2 1.5"/>
              <text x="\(fmt(geometry.leafW / 2))" y="\(fmt(geometry.leafH + 5))" text-anchor="middle" font-family="system-ui, sans-serif" font-size="2.8" fill="#002045">\(leftZone.title.uppercased())</text>
              <text x="\(fmt(geometry.leafW + geometry.leafW / 2))" y="\(fmt(geometry.leafH + 5))" text-anchor="middle" font-family="system-ui, sans-serif" font-size="2.8" fill="#002045">\(rightZone.title.uppercased())</text>
            </g>
          </g>
        </svg>
        """
        try svg.data(using: .utf8)?.write(to: url, options: .atomic)
    }

    static func writeBlueprint(
        face: EndpaperFaceDesign,
        geometry: EndsheetGeometry,
        isFront: Bool,
        projectTitle: String,
        to url: URL
    ) throws {
        let page = CGRect(x: 0, y: 0, width: 842, height: 595)
        let mutableData = NSMutableData()
        var mediaBox = page
        guard let consumer = CGDataConsumer(data: mutableData as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw EndsheetExportError.cannotCreatePDF
        }

        context.beginPage(mediaBox: &mediaBox)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(page)

        let title = "\(projectTitle) — \(isFront ? "Front" : "Back") endsheet"
        drawText(title, at: CGPoint(x: 40, y: 555), size: 16, bold: true, in: context)
        drawText(
            String(format: "Flat sheet %.1f × %.1f mm  ·  leaf %.1f × %.1f mm  ·  fold at %.1f mm",
                   geometry.totalW, geometry.leafH, geometry.leafW, geometry.leafH, geometry.foldXMM),
            at: CGPoint(x: 40, y: 532),
            size: 10,
            bold: false,
            in: context
        )
        drawText(
            "Mode: \(face.mode.title)  ·  Guides are print marks, not barriers.",
            at: CGPoint(x: 40, y: 516),
            size: 10,
            bold: false,
            in: context
        )

        let maxW: CGFloat = 720
        let maxH: CGFloat = 360
        let scale = min(maxW / CGFloat(geometry.totalW), maxH / CGFloat(geometry.leafH), 4)
        let drawW = CGFloat(geometry.totalW) * scale
        let drawH = CGFloat(geometry.leafH) * scale
        let origin = CGPoint(x: 40, y: 120)

        if let sheetImage = EndsheetRenderService.nsImage(face: face, sheetSizePoints: geometry.sheetSizePoints, dpi: 150),
           let cg = sheetImage.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            context.draw(cg, in: CGRect(origin: origin, size: CGSize(width: drawW, height: drawH)))
        } else {
            context.setFillColor(CGColor(gray: 0.97, alpha: 1))
            context.fill(CGRect(origin: origin, size: CGSize(width: drawW, height: drawH)))
        }

        context.setStrokeColor(CGColor(red: 0, green: 0.125, blue: 0.27, alpha: 1))
        context.setLineWidth(1)
        context.stroke(CGRect(origin: origin, size: CGSize(width: drawW, height: drawH)))

        if face.showFoldGuides {
            let foldX = origin.x + CGFloat(geometry.foldXMM) * scale
            context.setLineDash(phase: 0, lengths: [5, 4])
            context.move(to: CGPoint(x: foldX, y: origin.y))
            context.addLine(to: CGPoint(x: foldX, y: origin.y + drawH))
            context.strokePath()
            context.setLineDash(phase: 0, lengths: [])

            let left = geometry.zone(forHalfIndex: 0, isFront: isFront).title
            let right = geometry.zone(forHalfIndex: 1, isFront: isFront).title
            drawText(left, at: CGPoint(x: origin.x + drawW * 0.25 - 20, y: origin.y - 18), size: 11, bold: true, in: context)
            drawText(right, at: CGPoint(x: origin.x + drawW * 0.75 - 20, y: origin.y - 18), size: 11, bold: true, in: context)
        }

        context.endPage()
        context.closePDF()
        try (mutableData as Data).write(to: url, options: .atomic)
    }

    private static func drawText(
        _ string: String,
        at point: CGPoint,
        size: CGFloat,
        bold: Bool,
        in context: CGContext
    ) {
        let font = bold
            ? NSFont.boldSystemFont(ofSize: size)
            : NSFont.systemFont(ofSize: size)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.black
        ]
        let ns = NSAttributedString(string: string, attributes: attrs)
        let line = CTLineCreateWithAttributedString(ns)
        context.textPosition = point
        CTLineDraw(line, context)
    }

    private static func svgHex(_ color: CGColor) -> String {
        guard let comps = color.components, comps.count >= 3 else { return "#ffffff" }
        let r = Int((comps[0] * 255).rounded())
        let g = Int((comps[1] * 255).rounded())
        let b = Int((comps[2] * 255).rounded())
        return String(format: "#%02x%02x%02x", r, g, b)
    }

    private static func escapeXML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

enum EndsheetExportError: LocalizedError {
    case cannotCreatePDF

    var errorDescription: String? {
        switch self {
        case .cannotCreatePDF: return "Could not create endsheet PDF."
        }
    }
}

/// Raster helpers for preview, blueprint, and book-block leaf crops.
enum EndsheetRenderService {
    static func nsImage(
        face: EndpaperFaceDesign,
        sheetSizePoints: CGSize,
        dpi: CGFloat = 150
    ) -> NSImage? {
        switch face.mode {
        case .blank:
            return solidImage(color: CGColor(gray: 1, alpha: 1), size: sheetSizePoints, dpi: dpi)
        case .solidColor:
            return solidImage(color: face.solidColor.cgColor, size: sheetSizePoints, dpi: dpi)
        case .marbled:
            guard let spec = face.marbling else {
                return solidImage(color: CGColor(gray: 1, alpha: 1), size: sheetSizePoints, dpi: dpi)
            }
            return MarbledPaperGenerator.nsImage(spec: spec, sizePoints: sheetSizePoints, dpi: dpi)
        case .artwork:
            return artworkImage(face.artwork, size: sheetSizePoints, dpi: dpi)
        }
    }

    /// Crop left (0) or right (1) half of a sheet image into leaf-sized PDF data.
    static func leafPDFData(
        fromSheet sheet: NSImage,
        leafSize: CGSize,
        halfIndex: Int
    ) -> Data {
        let half = max(0, min(1, halfIndex))
        guard let cg = sheet.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return PDFDocumentService.renderBlankPDF(bounds: CGRect(origin: .zero, size: leafSize))
        }
        let fullW = cg.width
        let fullH = cg.height
        let halfW = max(1, fullW / 2)
        let x = half * halfW
        let cropW = half == 0 ? halfW : max(1, fullW - halfW)
        guard let cropped = cg.cropping(to: CGRect(x: x, y: 0, width: cropW, height: fullH)) else {
            return PDFDocumentService.renderBlankPDF(bounds: CGRect(origin: .zero, size: leafSize))
        }
        let leafImage = NSImage(cgImage: cropped, size: leafSize)
        return PDFDocumentService.fitImageData(leafImage, to: leafSize)
    }

    private static func solidImage(color: CGColor, size: CGSize, dpi: CGFloat) -> NSImage? {
        let pxW = max(2, Int((size.width * dpi / 72).rounded()))
        let pxH = max(2, Int((size.height * dpi / 72).rounded()))
        guard let ctx = CGContext(
            data: nil,
            width: pxW,
            height: pxH,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.setFillColor(color)
        ctx.fill(CGRect(x: 0, y: 0, width: pxW, height: pxH))
        guard let image = ctx.makeImage() else { return nil }
        return NSImage(cgImage: image, size: size)
    }

    private static func artworkImage(_ artwork: EndpaperArtwork?, size: CGSize, dpi: CGFloat) -> NSImage? {
        guard let artwork else {
            return solidImage(color: CGColor(gray: 1, alpha: 1), size: size, dpi: dpi)
        }
        let url = artwork.resolvedURL()
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing { url.stopAccessingSecurityScopedResource() }
        }

        if artwork.isPDF, let pdf = PDFDocument(url: url), let page = pdf.page(at: 0) {
            let pxW = max(2, Int((size.width * dpi / 72).rounded()))
            let pxH = max(2, Int((size.height * dpi / 72).rounded()))
            guard let ctx = CGContext(
                data: nil,
                width: pxW,
                height: pxH,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return nil }
            ctx.setFillColor(CGColor(gray: 1, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: pxW, height: pxH))
            let media = page.bounds(for: .mediaBox)
            let sx = CGFloat(pxW) / media.width
            let sy = CGFloat(pxH) / media.height
            let scale = max(sx, sy)
            let drawW = media.width * scale
            let drawH = media.height * scale
            let ox = (CGFloat(pxW) - drawW) / 2
            let oy = (CGFloat(pxH) - drawH) / 2
            ctx.saveGState()
            ctx.translateBy(x: ox, y: oy)
            ctx.scaleBy(x: scale, y: scale)
            page.draw(with: .mediaBox, to: ctx)
            ctx.restoreGState()
            guard let image = ctx.makeImage() else { return nil }
            return NSImage(cgImage: image, size: size)
        }

        guard let image = NSImage(contentsOf: url) else {
            return solidImage(color: CGColor(gray: 1, alpha: 1), size: size, dpi: dpi)
        }
        // Aspect-fill into sheet bitmap
        let pxW = max(2, Int((size.width * dpi / 72).rounded()))
        let pxH = max(2, Int((size.height * dpi / 72).rounded()))
        guard let ctx = CGContext(
            data: nil,
            width: pxW,
            height: pxH,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: pxW, height: pxH))
        var proposed = NSRect(origin: .zero, size: image.size)
        if let cg = image.cgImage(forProposedRect: &proposed, context: nil, hints: nil) {
            let iw = CGFloat(cg.width)
            let ih = CGFloat(cg.height)
            let scale = max(CGFloat(pxW) / iw, CGFloat(pxH) / ih)
            let drawSize = CGSize(width: iw * scale, height: ih * scale)
            let origin = CGPoint(
                x: (CGFloat(pxW) - drawSize.width) / 2,
                y: (CGFloat(pxH) - drawSize.height) / 2
            )
            ctx.interpolationQuality = .high
            ctx.draw(cg, in: CGRect(origin: origin, size: drawSize))
        }
        guard let out = ctx.makeImage() else { return nil }
        return NSImage(cgImage: out, size: size)
    }
}

enum EndsheetExportService {
    @MainActor
    static func exportSVG(
        project: BinderyProject,
        workspace: BindingWorkspace,
        store: AppStore,
        isFront: Bool
    ) {
        let geometry = EndsheetGeometry.resolving(project: project, trimPoints: workspace.job.resolvedTrimSize)
        let face = isFront ? workspace.job.endpapers.front : workspace.job.endpapers.back
        let panel = NSSavePanel()
        if let svgType = UTType(filenameExtension: "svg") {
            panel.allowedContentTypes = [svgType]
        } else {
            panel.allowedContentTypes = [.xml]
        }
        panel.canCreateDirectories = true
        let side = isFront ? "front" : "back"
        panel.nameFieldStringValue = "\(project.title)-endsheet-\(side).svg"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try EndsheetBlueprintService.writeSVG(
                face: face,
                geometry: geometry,
                isFront: isFront,
                projectTitle: project.title,
                to: url
            )
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            store.storeErrorMessage = error.localizedDescription
        }
    }

    @MainActor
    static func exportBlueprintPDF(
        project: BinderyProject,
        workspace: BindingWorkspace,
        store: AppStore,
        isFront: Bool
    ) {
        let geometry = EndsheetGeometry.resolving(project: project, trimPoints: workspace.job.resolvedTrimSize)
        let face = isFront ? workspace.job.endpapers.front : workspace.job.endpapers.back
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.canCreateDirectories = true
        let side = isFront ? "front" : "back"
        panel.nameFieldStringValue = "\(project.title)-endsheet-\(side)-blueprint.pdf"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try EndsheetBlueprintService.writeBlueprint(
                face: face,
                geometry: geometry,
                isFront: isFront,
                projectTitle: project.title,
                to: url
            )
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            store.storeErrorMessage = error.localizedDescription
        }
    }
}
