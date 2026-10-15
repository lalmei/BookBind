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
        to url: URL,
        mode: SVGDocumentBuilder.ExportMode = .production
    ) throws {
        let margin = mode.includesGuides ? 12.0 : 0.0
        let labelBand = mode.includesGuides ? 28.0 : 0.0
        let canvasW = geometry.totalW + margin * 2
        let canvasH = geometry.leafH + margin * 2 + labelBand
        let leftZone = geometry.zone(forHalfIndex: 0, isFront: isFront)
        let rightZone = geometry.zone(forHalfIndex: 1, isFront: isFront)

        var svg = SVGDocumentBuilder.rootOpen(
            widthMM: canvasW,
            heightMM: canvasH,
            title: "\(projectTitle) — \(isFront ? "Front" : "Back") endsheet \(mode == .clean ? "artwork" : "")"
        )
        svg += "<g transform=\"translate(\(SVGDocumentBuilder.fmt(margin)), \(SVGDocumentBuilder.fmt(margin + (mode.includesGuides ? 16 : 0))))\">\n"
        if mode.includesGuides {
            svg += """
            <text x="0" y="-8" font-family="system-ui, sans-serif" font-size="3.2" fill="#74777f" letter-spacing="0.4">FLAT ENDSHEET \(SVGDocumentBuilder.fmt(geometry.totalW)) × \(SVGDocumentBuilder.fmt(geometry.leafH)) mm — fold at \(SVGDocumentBuilder.fmt(geometry.foldXMM)) mm</text>
            """
        }

        svg += "<g id=\"artwork\">\n"
        svg += endsheetArtworkSVG(face: face, geometry: geometry)
        svg += "</g>\n"

        if mode.includesGuides, face.showFoldGuides {
            var guides = SVGDocumentBuilder.line(
                x1: geometry.foldXMM, y1: 0,
                x2: geometry.foldXMM, y2: geometry.leafH,
                stroke: "#002045", width: 0.35, dash: "2 1.5"
            )
            guides += """
            <text x="\(SVGDocumentBuilder.fmt(geometry.leafW / 2))" y="\(SVGDocumentBuilder.fmt(geometry.leafH + 5))" text-anchor="middle" font-family="system-ui, sans-serif" font-size="2.8" fill="#002045">\(leftZone.title.uppercased())</text>
            <text x="\(SVGDocumentBuilder.fmt(geometry.leafW + geometry.leafW / 2))" y="\(SVGDocumentBuilder.fmt(geometry.leafH + 5))" text-anchor="middle" font-family="system-ui, sans-serif" font-size="2.8" fill="#002045">\(rightZone.title.uppercased())</text>
            """
            svg += SVGDocumentBuilder.guideGroup(id: "guides-fold", content: guides)
        }

        svg += "</g>\n"
        svg += SVGDocumentBuilder.rootClose
        try Data(svg.utf8).write(to: url, options: .atomic)
    }

    /// Artwork only — design document elements, or legacy face fill.
    private static func endsheetArtworkSVG(face: EndpaperFaceDesign, geometry: EndsheetGeometry) -> String {
        let elements = face.document.orderedElementsForRendering()
        if !elements.isEmpty {
            var out = ""
            for element in elements {
                out += designElementSVG(element)
            }
            return out
        }

        switch face.mode {
        case .blank:
            return SVGDocumentBuilder.rect(
                x: 0, y: 0, w: geometry.totalW, h: geometry.leafH,
                fill: "#ffffff", stroke: "#c8c8c8", strokeWidth: 0.25
            )
        case .solidColor:
            return SVGDocumentBuilder.rect(
                x: 0, y: 0, w: geometry.totalW, h: geometry.leafH,
                fill: SVGDocumentBuilder.hex(cgColor: face.solidColor.cgColor),
                stroke: "#002045", strokeWidth: 0.25
            )
        case .marbled:
            if let marble = face.marbling {
                return SVGDocumentBuilder.marbledImageElement(
                    spec: marble, x: 0, y: 0,
                    width: geometry.totalW, height: geometry.leafH
                )
            }
            return SVGDocumentBuilder.rect(
                x: 0, y: 0, w: geometry.totalW, h: geometry.leafH, fill: "#f7f4ec"
            )
        case .artwork:
            return SVGDocumentBuilder.rect(
                x: 0, y: 0, w: geometry.totalW, h: geometry.leafH,
                fill: "#f7f4ec", stroke: "#002045", strokeWidth: 0.25
            )
        }
    }

    private static func designElementSVG(_ element: DesignElement) -> String {
        let opacity = String(format: "%.2f", min(1, max(0, element.opacity)))
        switch element.kind {
        case .shape:
            var body = ""
            if let marble = element.fill.marbling {
                body += SVGDocumentBuilder.marbledImageElement(
                    spec: marble,
                    x: element.xMM, y: element.yMM,
                    width: element.widthMM, height: element.heightMM
                )
            } else if let solid = element.fill.solidColor {
                body += SVGDocumentBuilder.rect(
                    x: element.xMM, y: element.yMM,
                    w: element.widthMM, h: element.heightMM,
                    fill: SVGDocumentBuilder.hex(solid),
                    stroke: element.stroke.solidColor.map { SVGDocumentBuilder.hex($0) },
                    strokeWidth: element.strokeWidthMM
                )
            } else if let stroke = element.stroke.solidColor {
                body += SVGDocumentBuilder.rect(
                    x: element.xMM, y: element.yMM,
                    w: element.widthMM, h: element.heightMM,
                    fill: nil,
                    stroke: SVGDocumentBuilder.hex(stroke),
                    strokeWidth: element.strokeWidthMM
                )
            }
            return "<g opacity=\"\(opacity)\">\(body)</g>\n"
        case .text:
            let fill = element.fill.solidColor.map { SVGDocumentBuilder.hex($0) } ?? "#111111"
            return """
            <text x="\(SVGDocumentBuilder.fmt(element.centerXMM))" y="\(SVGDocumentBuilder.fmt(element.centerYMM))" text-anchor="middle" dominant-baseline="middle" font-size="\(SVGDocumentBuilder.fmt(element.fontSizeMM))" fill="\(fill)" opacity="\(opacity)">\(SVGDocumentBuilder.escape(element.text))</text>
            """
        case .image:
            return ""
        }
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
        // Prefer layered design document when present.
        let elements = face.document.orderedElementsForRendering()
        if !elements.isEmpty {
            return compositeDocument(elements, size: sheetSizePoints, dpi: dpi)
        }

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

    private static func compositeDocument(
        _ elements: [DesignElement],
        size: CGSize,
        dpi: CGFloat
    ) -> NSImage? {
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
        let sx = Double(pxW) / max(1, size.width)
        let sy = Double(pxH) / max(1, size.height)
        // size is in points; element coords are mm — convert via BindingMath points-per-mm.
        let mmToPts = BindingMath.points(fromMillimeters: 1)
        for element in elements {
            let x = element.xMM * mmToPts * sx
            let y = element.yMM * mmToPts * sy
            let w = element.widthMM * mmToPts * sx
            let h = element.heightMM * mmToPts * sy
            let rect = CGRect(x: x, y: Double(pxH) - y - h, width: w, height: h)
            ctx.saveGState()
            ctx.setAlpha(CGFloat(element.opacity))
            if let marble = element.fill.marbling,
               let img = MarbledPaperGenerator.render(
                   spec: marble,
                   width: max(2, Int(w.rounded())),
                   height: max(2, Int(h.rounded()))
               ) {
                ctx.draw(img, in: rect)
            } else if let solid = element.fill.solidColor {
                ctx.setFillColor(solid.cgColor)
                ctx.fill(rect)
            }
            if let stroke = element.stroke.solidColor, element.strokeWidthMM > 0 {
                ctx.setStrokeColor(stroke.cgColor)
                ctx.setLineWidth(CGFloat(element.strokeWidthMM * mmToPts * sx))
                ctx.stroke(rect)
            }
            ctx.restoreGState()
        }
        guard let image = ctx.makeImage() else { return nil }
        return NSImage(cgImage: image, size: size)
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
        isFront: Bool,
        mode: SVGDocumentBuilder.ExportMode = .production
    ) {
        let geometry = EndsheetGeometry.resolving(project: project, trimPoints: workspace.job.resolvedTrimSize)
        var face = isFront ? project.endsheets.front : project.endsheets.back
        face.ensureDesignDocument(geometry: geometry)
        let panel = NSSavePanel()
        if let svgType = UTType(filenameExtension: "svg") {
            panel.allowedContentTypes = [svgType]
        } else {
            panel.allowedContentTypes = [.xml]
        }
        panel.canCreateDirectories = true
        let side = isFront ? "front" : "back"
        let suffix = mode == .clean ? "artwork" : "production"
        panel.nameFieldStringValue = "\(project.title)-endsheet-\(side)-\(suffix).svg"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try EndsheetBlueprintService.writeSVG(
                face: face,
                geometry: geometry,
                isFront: isFront,
                projectTitle: project.title,
                to: url,
                mode: mode
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
