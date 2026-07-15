import AppKit
import Foundation
import UniformTypeIdentifiers

enum CoverBlueprintService {
    /// Flat wrap regions: back · back joint · spine · front joint · front.
    /// `midsection` is the BindingMath case-spine wrap (joints + spine face).
    struct Geometry {
        let boardW: Double
        let boardH: Double
        /// Full midsection from BindingMath (joints + spine face).
        let midsection: Double
        /// French groove / hinge band width used in the layout (may be capped).
        let hinge: Double
        /// Designable spine face between the two joints.
        let spineFace: Double
        let totalW: Double

        /// Legacy alias — full midsection width (joints + spine).
        var spine: Double { midsection }

        init(project: BinderyProject, spineWidthMM: Double) {
            boardW = max(40, project.widthMM)
            boardH = max(40, project.heightMM)
            midsection = max(4, spineWidthMM)
            let requestedHinge = max(0, project.hingeGapMM)
            // Keep a usable spine face even when groove requests are large.
            let maxHingeEach = max(0, (midsection - 2) / 2)
            hinge = min(requestedHinge, maxHingeEach)
            spineFace = max(2, midsection - (hinge * 2))
            totalW = boardW * 2 + midsection
        }

        func panelOriginX(_ panel: CoverPanel) -> Double {
            switch panel {
            case .back: return 0
            case .backHinge: return boardW
            case .spine: return boardW + hinge
            case .frontHinge: return boardW + hinge + spineFace
            case .front: return boardW + midsection
            }
        }

        func panelWidth(_ panel: CoverPanel) -> Double {
            switch panel {
            case .back, .front: return boardW
            case .backHinge, .frontHinge: return hinge
            case .spine: return spineFace
            }
        }

        /// Ordered panels present in the wrap (omits zero-width joints).
        var layoutPanels: [CoverPanel] {
            var panels: [CoverPanel] = [.back]
            if hinge > 0.05 { panels.append(.backHinge) }
            panels.append(.spine)
            if hinge > 0.05 { panels.append(.frontHinge) }
            panels.append(.front)
            return panels
        }

        /// Guide lines in wrap-mm for joints / spine edges (visual only).
        var guideXsMM: [Double] {
            var xs: [Double] = [boardW]
            if hinge > 0.05 {
                xs.append(boardW + hinge)
                xs.append(boardW + hinge + spineFace)
            } else {
                xs.append(boardW + midsection)
            }
            xs.append(boardW + midsection)
            // Unique sorted
            return Array(Set(xs.map { ($0 * 100).rounded() / 100 })).sorted()
        }

        func panel(containingWrapX x: Double) -> CoverPanel {
            for panel in layoutPanels.reversed() {
                let origin = panelOriginX(panel)
                if x >= origin { return panel }
            }
            return .back
        }
    }

    static func writeBlueprint(
        for project: BinderyProject,
        pageCount: Int,
        spineWidthMM: Double,
        to url: URL
    ) throws {
        let geo = Geometry(project: project, spineWidthMM: spineWidthMM)
        let page = CGRect(x: 0, y: 0, width: 842, height: 595)
        let data = NSMutableData()
        var mediaBox = page
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw BindingError.exportFailed
        }

        context.beginPDFPage(nil)
        context.setFillColor(CGColor(red: 0.976, green: 0.976, blue: 1, alpha: 1))
        context.fill(page)

        drawText(
            project.title,
            at: CGPoint(x: 40, y: 548),
            size: 20,
            color: NSColor(red: 0.0, green: 0.125, blue: 0.271, alpha: 1),
            bold: true
        )
        drawText(
            "Cover blueprint · \(project.architecture.rawValue) · \(project.coverMaterial.rawValue)",
            at: CGPoint(x: 40, y: 524),
            size: 10,
            color: .secondaryLabelColor
        )

        let scale = min(620 / geo.totalW, 360 / geo.boardH)
        let startX = 40.0
        let startY = 90.0
        let h = geo.boardH * scale

        var cursor = startX
        for panel in geo.layoutPanels {
            let width = geo.panelWidth(panel) * scale
            let fill: NSColor
            switch panel {
            case .back, .front:
                fill = NSColor(red: 0.94, green: 0.95, blue: 0.98, alpha: 1)
            case .spine:
                fill = NSColor(red: 0.84, green: 0.89, blue: 1.0, alpha: 1)
            case .backHinge, .frontHinge:
                fill = NSColor(red: 0.90, green: 0.92, blue: 0.86, alpha: 1)
            }
            let label: String
            switch panel {
            case .back, .front:
                label = String(format: "%@  %.0f×%.0f mm", panel.title.uppercased(), geo.boardW, geo.boardH)
            case .spine:
                label = String(format: "SPINE  %.1f mm", geo.spineFace)
            case .backHinge, .frontHinge:
                label = String(format: "JOINT  %.1f mm", geo.hinge)
            }
            drawWrapPanel(
                context,
                rect: CGRect(x: cursor, y: startY, width: max(1, width), height: h),
                fill: fill,
                label: label
            )
            cursor += width
        }

        for element in project.orderedCoverElementsForRendering() where finishVisible(element.layer, in: project) {
            drawElement(
                element,
                geometry: geo,
                origin: CGPoint(x: startX, y: startY),
                scale: scale,
                heightPts: h
            )
        }

        drawText(
            String(format: "TOTAL WIDTH: %.1f mm", geo.totalW),
            at: CGPoint(x: startX, y: startY + h + 18),
            size: 10,
            color: NSColor(red: 0.0, green: 0.125, blue: 0.271, alpha: 0.7)
        )

        let metrics = [
            String(format: "Spine: %.2f mm", spineWidthMM),
            String(format: "Board: %.2f mm · Groove: %.2f mm", project.boardThicknessMM, project.hingeGapMM),
            "Pages: \(pageCount) · GSM: \(Int(project.textPaperGSM))",
            "Layers: \(layerLabel(project))"
        ]
        for (index, metric) in metrics.enumerated() {
            drawText(metric, at: CGPoint(x: 40, y: 50 - CGFloat(index * 14)), size: 10, color: .labelColor)
        }

        context.endPDFPage()
        context.closePDF()
        try (data as Data).write(to: url, options: [.atomic])
    }

    static func writeSVG(
        for project: BinderyProject,
        pageCount: Int,
        spineWidthMM: Double,
        to url: URL
    ) throws {
        let geo = Geometry(project: project, spineWidthMM: spineWidthMM)
        let margin = 24.0
        let labelH = 28.0
        let canvasW = geo.totalW + margin * 2
        let canvasH = geo.boardH + margin * 2 + labelH

        var svg = """
        <?xml version="1.0" encoding="UTF-8"?>
        <svg xmlns="http://www.w3.org/2000/svg" width="\(fmt(canvasW))mm" height="\(fmt(canvasH))mm" viewBox="0 0 \(fmt(canvasW)) \(fmt(canvasH))">
          <title>\(escape(project.title)) — Cover Blueprint</title>
          <desc>Spine \(fmt(spineWidthMM))mm · \(pageCount) pages · \(escape(project.coverMaterial.rawValue))</desc>
          <defs>
            <pattern id="grid" width="10" height="10" patternUnits="userSpaceOnUse">
              <path d="M 10 0 L 0 0 0 10" fill="none" stroke="#c4c6cf" stroke-width="0.2"/>
            </pattern>
          </defs>
          <rect width="100%" height="100%" fill="#f9f9ff"/>
          <rect x="0" y="0" width="\(fmt(canvasW))" height="\(fmt(canvasH))" fill="url(#grid)"/>
          <g transform="translate(\(fmt(margin)), \(fmt(margin + 12)))">
            <text x="0" y="-4" font-family="system-ui, sans-serif" font-size="3.2" fill="#74777f" letter-spacing="0.4">TOTAL WIDTH: \(fmt(geo.totalW))mm</text>
            <rect x="0" y="0" width="\(fmt(geo.totalW))" height="0.4" fill="#002045" opacity="0.35"/>
        """

        // Panels: back · joint · spine · joint · front
        for panel in geo.layoutPanels {
            let x = geo.panelOriginX(panel)
            let w = geo.panelWidth(panel)
            let fill: String
            switch panel {
            case .back, .front: fill = "#f0f3ff"
            case .spine: fill = "#d6e3ff"
            case .backHinge, .frontHinge: fill = "#e8eadc"
            }
            let label: String
            switch panel {
            case .back, .front:
                label = "\(panel.title.uppercased()): \(fmt(geo.boardW))mm × \(fmt(geo.boardH))mm"
            case .spine:
                label = "SPINE: \(fmt(geo.spineFace))mm"
            case .backHinge, .frontHinge:
                label = "JOINT: \(fmt(geo.hinge))mm"
            }
            svg += panelSVG(x: x, w: w, h: geo.boardH, fill: fill, label: label, spine: panel == .spine)
        }

        for finish in CoverElementLayer.allCases {
            let elements = project.orderedCoverElementsForRendering()
                .filter { finishVisible($0.layer, in: project) && $0.layer == finish }
            guard !elements.isEmpty else { continue }
            svg += """
                <g id="finish-\(finish.rawValue)" data-finish="\(escape(finish.title))">
            """
            for element in elements {
                svg += elementSVG(element, geometry: geo)
            }
            svg += "</g>\n"
        }

        svg += """
          </g>
        </svg>
        """

        try Data(svg.utf8).write(to: url, options: [.atomic])
    }

    // MARK: - PDF helpers

    private static func drawWrapPanel(
        _ context: CGContext,
        rect: CGRect,
        fill: NSColor,
        label: String
    ) {
        context.setFillColor(fill.cgColor)
        context.fill(rect)
        context.setStrokeColor(CGColor(red: 0.0, green: 0.125, blue: 0.271, alpha: 0.55))
        context.stroke(rect, width: 1)
        drawText(
            label,
            at: CGPoint(x: rect.minX + 6, y: rect.minY + 8),
            size: 8,
            color: .secondaryLabelColor
        )
    }

    private static func drawElement(
        _ element: CoverDesignElement,
        geometry: Geometry,
        origin: CGPoint,
        scale: Double,
        heightPts: Double
    ) {
        let panelX = element.wrapCenterX(geometry: geometry)
        let x = origin.x + panelX * scale
        let yFromTop = element.yMM * scale
        let y = origin.y + heightPts - yFromTop

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }

        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.setAlpha(CGFloat(min(1, max(0, element.opacity))))

        switch element.kind {
        case .image:
            drawImageElement(element, at: CGPoint(x: x, y: y), scale: scale, context: ctx)
        case .text:
            drawTextElement(element, at: CGPoint(x: x, y: y), scale: scale)
        case .shape:
            drawShapeElement(element, at: CGPoint(x: x, y: y), scale: scale, context: ctx)
        }
    }

    private static func finishColor(_ layer: CoverElementLayer) -> NSColor {
        switch layer {
        case .foil:
            return NSColor(red: 0.451, green: 0.361, blue: 0.0, alpha: 1)
        case .deboss:
            return NSColor(red: 0.125, green: 0.129, blue: 0.110, alpha: 0.55)
        case .ink:
            return NSColor(red: 0.067, green: 0.110, blue: 0.173, alpha: 1)
        }
    }

    private static func drawShapeElement(
        _ element: CoverDesignElement,
        at point: CGPoint,
        scale: Double,
        context: CGContext
    ) {
        let w = max(1, element.widthMM) * scale
        let h = max(1, element.heightMM) * scale
        let hasStroke = element.isStroked
        let strokeW = hasStroke ? max(0.2, element.strokeWidthMM) * scale : 0
        let color = element.stroke.solidColor?.nsColor ?? finishColor(element.layer)
        let fillNSColor = element.fill.solidColor?.nsColor ?? color
        let dash = element.strokeDashPatternMM().map { CGFloat($0 * scale) }

        context.saveGState()
        context.translateBy(x: point.x, y: point.y)
        if element.rotationDegrees != 0 {
            context.rotate(by: CGFloat(element.rotationDegrees) * .pi / 180)
        }

        context.setStrokeColor(color.cgColor)
        context.setLineWidth(strokeW)
        context.setLineDash(phase: 0, lengths: dash)
        context.setLineCap(element.strokeUsesRoundCap ? .round : .butt)

        // Stroke sits inside the element bounds, matching the canvas.
        let rect = CGRect(x: -w / 2, y: -h / 2, width: w, height: h)
            .insetBy(dx: strokeW / 2, dy: strokeW / 2)
        let innerInset = strokeW * 2.5

        switch element.shapeType {
        case .rectangle:
            if element.isFilled {
                context.setFillColor(fillNSColor.withAlphaComponent(fillNSColor.alphaComponent * 0.9).cgColor)
                context.fill(rect)
            }
            if hasStroke {
                context.stroke(rect, width: strokeW)
                if element.strokeStyle.isDoubleStroke {
                    context.setLineDash(phase: 0, lengths: [])
                    context.stroke(rect.insetBy(dx: innerInset, dy: innerInset), width: strokeW)
                }
                drawOrnamentStamps(element, in: rect, strokeW: strokeW, color: color, context: context)
            }
        case .ellipse:
            if element.isFilled {
                context.setFillColor(fillNSColor.withAlphaComponent(fillNSColor.alphaComponent * 0.9).cgColor)
                context.fillEllipse(in: rect)
            }
            if hasStroke {
                context.strokeEllipse(in: rect)
                if element.strokeStyle.isDoubleStroke {
                    context.setLineDash(phase: 0, lengths: [])
                    context.strokeEllipse(in: rect.insetBy(dx: innerInset, dy: innerInset))
                }
                drawOrnamentStamps(element, in: rect, strokeW: strokeW, color: color, context: context)
            }
        case .line:
            if hasStroke {
                context.move(to: CGPoint(x: rect.minX, y: 0))
                context.addLine(to: CGPoint(x: rect.maxX, y: 0))
                context.strokePath()
                if element.strokeStyle.isDoubleStroke {
                    context.setLineDash(phase: 0, lengths: [])
                    context.move(to: CGPoint(x: rect.minX, y: innerInset))
                    context.addLine(to: CGPoint(x: rect.maxX, y: innerInset))
                    context.strokePath()
                }
                drawOrnamentStamps(element, in: rect, strokeW: strokeW, color: color, context: context)
            }
        }
        context.restoreGState()
    }

    private static func drawOrnamentStamps(
        _ element: CoverDesignElement,
        in rect: CGRect,
        strokeW: CGFloat,
        color: NSColor,
        context: CGContext
    ) {
        guard element.strokeStyle.drawsOrnamentMarks,
              element.ornamentPattern.drawsStamps else { return }
        let spacing = max(8, strokeW * 7)
        let size = strokeW * 1.6
        let points = CoverShapeElementView.samplePoints(
            along: element.shapeType,
            in: rect,
            spacing: spacing
        )
        context.setFillColor(color.cgColor)
        context.setLineDash(phase: 0, lengths: [])
        for point in points {
            fillOrnamentStamp(
                element.ornamentPattern,
                at: point,
                size: size,
                context: context
            )
        }
    }

    private static func fillOrnamentStamp(
        _ pattern: CoverOrnamentPattern,
        at point: CGPoint,
        size: CGFloat,
        context: CGContext
    ) {
        let half = size / 2
        switch pattern {
        case .dots:
            context.fillEllipse(in: CGRect(x: point.x - half, y: point.y - half, width: size, height: size))
        case .diamonds:
            context.beginPath()
            context.move(to: CGPoint(x: point.x, y: point.y - half))
            context.addLine(to: CGPoint(x: point.x + half, y: point.y))
            context.addLine(to: CGPoint(x: point.x, y: point.y + half))
            context.addLine(to: CGPoint(x: point.x - half, y: point.y))
            context.closePath()
            context.fillPath()
        case .squares:
            context.fill(CGRect(x: point.x - half * 0.9, y: point.y - half * 0.9, width: size * 0.9, height: size * 0.9))
        case .crosses:
            let arm = size * 0.28
            context.fill(CGRect(x: point.x - half, y: point.y - arm / 2, width: size, height: arm))
            context.fill(CGRect(x: point.x - arm / 2, y: point.y - half, width: arm, height: size))
        case .dashes, .dashDots:
            break
        }
    }

    private static func drawTextElement(_ element: CoverDesignElement, at point: CGPoint, scale: Double) {
        let color = finishColor(element.layer)
        let fontSize = max(4, CGFloat(element.fontSizeMM * scale))
        let attributes: [NSAttributedString.Key: Any] = [
            .font: CoverEditorMath.nsFont(for: element.fontStyle, sizePoints: fontSize),
            .foregroundColor: color
        ]
        let ns = element.text as NSString
        let size = ns.size(withAttributes: attributes)

        var transform = CGAffineTransform.identity
        transform = transform.translatedBy(x: point.x, y: point.y)
        if element.rotationDegrees != 0 {
            transform = transform.rotated(by: CGFloat(element.rotationDegrees) * .pi / 180)
        }
        transform = transform.translatedBy(x: -size.width / 2, y: -size.height / 2)

        if let ctx = NSGraphicsContext.current?.cgContext {
            ctx.concatenate(transform)
            ns.draw(at: .zero, withAttributes: attributes)
        }
    }

    private static func drawImageElement(
        _ element: CoverDesignElement,
        at point: CGPoint,
        scale: Double,
        context: CGContext
    ) {
        guard let url = element.resolvedImageURL() else { return }
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        guard let image = NSImage(contentsOf: url),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }

        let w = max(4, element.widthMM) * scale
        let h = max(4, element.heightMM) * scale
        context.saveGState()
        context.translateBy(x: point.x, y: point.y)
        if element.rotationDegrees != 0 {
            context.rotate(by: CGFloat(element.rotationDegrees) * .pi / 180)
        }
        context.translateBy(x: -w / 2, y: -h / 2)
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))
        context.restoreGState()
    }

    private static func drawText(
        _ text: String,
        at point: CGPoint,
        size: CGFloat,
        color: NSColor,
        bold: Bool = false
    ) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: bold ? NSFont.boldSystemFont(ofSize: size) : NSFont.systemFont(ofSize: size),
            .foregroundColor: color
        ]
        text.draw(at: point, withAttributes: attributes)
    }

    // MARK: - SVG helpers

    private static func panelSVG(x: Double, w: Double, h: Double, fill: String, label: String, spine: Bool = false) -> String {
        let stroke = spine ? "#002045" : "#74777f"
        let labelY = h + 4.5
        return """
            <rect x="\(fmt(x))" y="0" width="\(fmt(w))" height="\(fmt(h))" fill="\(fill)" stroke="\(stroke)" stroke-width="0.4"/>
            <text x="\(fmt(x + w * 0.5))" y="\(fmt(labelY))" text-anchor="middle" font-family="ui-monospace, monospace" font-size="2.8" fill="#74777f">\(escape(label))</text>
        """
    }

    private static func elementSVG(_ element: CoverDesignElement, geometry: Geometry) -> String {
        let ox = element.wrapCenterX(geometry: geometry)
        let oy = element.yMM
        let opacity = String(format: "%.2f", min(1, max(0, element.opacity)) * (element.layer == .deboss ? 0.55 : 1))
        let transform: String
        if abs(element.rotationDegrees) > 0.01 {
            transform = "transform=\"rotate(\(fmt(element.rotationDegrees)) \(fmt(ox)) \(fmt(oy)))\""
        } else {
            transform = ""
        }

        switch element.kind {
        case .image:
            let w = max(4, element.widthMM)
            let h = max(4, element.heightMM)
            let href: String
            if let url = element.resolvedImageURL() {
                href = escape(url.absoluteString)
            } else {
                href = ""
            }
            return """
                <image href="\(href)" x="\(fmt(ox - w / 2))" y="\(fmt(oy - h / 2))" width="\(fmt(w))" height="\(fmt(h))" opacity="\(opacity)" \(transform) preserveAspectRatio="xMidYMid meet"/>
            """
        case .shape:
            return shapeSVG(element, centerX: ox, centerY: oy, opacity: opacity, transform: transform)
        case .text:
            let fill = finishHex(element.layer)
            let size = element.fontSizeMM
            let family = element.fontStyle == .body ? "system-ui, sans-serif" : "Georgia, 'Times New Roman', serif"
            let weight = element.fontStyle == .display ? "600" : "400"
            return """
                <text x="\(fmt(ox))" y="\(fmt(oy))" text-anchor="middle" dominant-baseline="middle" font-family="\(family)" font-size="\(fmt(size))" font-weight="\(weight)" fill="\(fill)" opacity="\(opacity)" \(transform)>\(escape(element.text))</text>
            """
        }
    }

    private static func finishHex(_ layer: CoverElementLayer) -> String {
        switch layer {
        case .foil: return "#735c00"
        case .deboss: return "#20211c"
        case .ink: return "#111c2c"
        }
    }

    private static func shapeSVG(
        _ element: CoverDesignElement,
        centerX ox: Double,
        centerY oy: Double,
        opacity: String,
        transform: String
    ) -> String {
        let strokeHex: String = {
            guard element.isStroked, let solid = element.stroke.solidColor else { return "none" }
            return hexFromCodable(solid)
        }()
        let strokeW = element.isStroked ? max(0.2, element.strokeWidthMM) : 0
        // Inset so the stroke stays inside the element bounds, matching the canvas.
        let w = max(1, element.widthMM) - strokeW
        let h = max(1, element.heightMM) - strokeW
        let fill: String = {
            guard element.shapeType != .line, let solid = element.fill.solidColor else { return "none" }
            return hexFromCodable(solid)
        }()
        let dashValues = element.strokeDashPatternMM()
        var strokeAttrs = "stroke=\"\(strokeHex)\" stroke-width=\"\(fmt(strokeW))\""
        if !dashValues.isEmpty {
            strokeAttrs += " stroke-dasharray=\"\(dashValues.map(fmt).joined(separator: " "))\""
        }
        if element.strokeUsesRoundCap {
            strokeAttrs += " stroke-linecap=\"round\""
        }
        let plainStroke = "stroke=\"\(strokeHex)\" stroke-width=\"\(fmt(strokeW))\""
        let inner = element.strokeWidthMM * 2.5

        var body = ""
        switch element.shapeType {
        case .rectangle:
            body += "<rect x=\"\(fmt(ox - w / 2))\" y=\"\(fmt(oy - h / 2))\" width=\"\(fmt(w))\" height=\"\(fmt(h))\" fill=\"\(fill)\" \(strokeAttrs)/>"
            if element.isStroked, element.strokeStyle.isDoubleStroke {
                body += "<rect x=\"\(fmt(ox - w / 2 + inner))\" y=\"\(fmt(oy - h / 2 + inner))\" width=\"\(fmt(max(0.5, w - inner * 2)))\" height=\"\(fmt(max(0.5, h - inner * 2)))\" fill=\"none\" \(plainStroke)/>"
            }
        case .ellipse:
            body += "<ellipse cx=\"\(fmt(ox))\" cy=\"\(fmt(oy))\" rx=\"\(fmt(w / 2))\" ry=\"\(fmt(h / 2))\" fill=\"\(fill)\" \(strokeAttrs)/>"
            if element.isStroked, element.strokeStyle.isDoubleStroke {
                body += "<ellipse cx=\"\(fmt(ox))\" cy=\"\(fmt(oy))\" rx=\"\(fmt(max(0.5, w / 2 - inner)))\" ry=\"\(fmt(max(0.5, h / 2 - inner)))\" fill=\"none\" \(plainStroke)/>"
            }
        case .line:
            body += "<line x1=\"\(fmt(ox - w / 2))\" y1=\"\(fmt(oy))\" x2=\"\(fmt(ox + w / 2))\" y2=\"\(fmt(oy))\" \(strokeAttrs)/>"
            if element.isStroked, element.strokeStyle.isDoubleStroke {
                body += "<line x1=\"\(fmt(ox - w / 2))\" y1=\"\(fmt(oy + inner))\" x2=\"\(fmt(ox + w / 2))\" y2=\"\(fmt(oy + inner))\" \(plainStroke)/>"
            }
        }
        body += ornamentStampsSVG(element, centerX: ox, centerY: oy, color: strokeHex)
        return """
            <g opacity="\(opacity)" \(transform)>\(body)</g>
        """
    }

    private static func ornamentStampsSVG(
        _ element: CoverDesignElement,
        centerX ox: Double,
        centerY oy: Double,
        color: String
    ) -> String {
        guard element.isStroked,
              element.strokeStyle.drawsOrnamentMarks,
              element.ornamentPattern.drawsStamps,
              color != "none" else { return "" }

        let strokeW = max(0.2, element.strokeWidthMM)
        let w = max(1, element.widthMM) - strokeW
        let h = max(1, element.heightMM) - strokeW
        let rect = CGRect(x: ox - w / 2, y: oy - h / 2, width: w, height: h)
        let spacing = max(2.0, strokeW * 7)
        let size = strokeW * 1.6
        let points = CoverShapeElementView.samplePoints(
            along: element.shapeType,
            in: rect,
            spacing: CGFloat(spacing)
        )

        var svg = ""
        for point in points {
            switch element.ornamentPattern {
            case .dots:
                svg += "<circle cx=\"\(fmt(Double(point.x)))\" cy=\"\(fmt(Double(point.y)))\" r=\"\(fmt(size / 2))\" fill=\"\(color)\"/>"
            case .diamonds:
                let half = size / 2
                svg += "<polygon points=\"\(fmt(Double(point.x))),\(fmt(Double(point.y) - half)) \(fmt(Double(point.x) + half)),\(fmt(Double(point.y))) \(fmt(Double(point.x))),\(fmt(Double(point.y) + half)) \(fmt(Double(point.x) - half)),\(fmt(Double(point.y)))\" fill=\"\(color)\"/>"
            case .squares:
                let side = size * 0.9
                svg += "<rect x=\"\(fmt(Double(point.x) - side / 2))\" y=\"\(fmt(Double(point.y) - side / 2))\" width=\"\(fmt(side))\" height=\"\(fmt(side))\" fill=\"\(color)\"/>"
            case .crosses:
                let arm = size * 0.28
                svg += "<rect x=\"\(fmt(Double(point.x) - size / 2))\" y=\"\(fmt(Double(point.y) - arm / 2))\" width=\"\(fmt(size))\" height=\"\(fmt(arm))\" fill=\"\(color)\"/>"
                svg += "<rect x=\"\(fmt(Double(point.x) - arm / 2))\" y=\"\(fmt(Double(point.y) - size / 2))\" width=\"\(fmt(arm))\" height=\"\(fmt(size))\" fill=\"\(color)\"/>"
            case .dashes, .dashDots:
                break
            }
        }
        return svg
    }

    private static func finishVisible(_ layer: CoverElementLayer, in project: BinderyProject) -> Bool {
        switch layer {
        case .ink: return true
        case .foil: return project.showFoilLayer
        case .deboss: return project.showDebossLayer
        }
    }

    private static func layerLabel(_ project: BinderyProject) -> String {
        let names = project.coverDesignLayers
            .filter(\.isVisible)
            .sorted { $0.zIndex < $1.zIndex }
            .map(\.name)
        if !names.isEmpty { return names.joined(separator: ", ") }
        var layers: [String] = ["ink"]
        if project.showFoilLayer { layers.append("foil") }
        if project.showDebossLayer { layers.append("deboss") }
        return layers.joined(separator: ", ")
    }

    private static func fmt(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    private static func hexFromCodable(_ color: CodableColor) -> String {
        let r = Int((color.red * 255).rounded())
        let g = Int((color.green * 255).rounded())
        let b = Int((color.blue * 255).rounded())
        return String(format: "#%02x%02x%02x", r, g, b)
    }

    private static func escape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

// MARK: - Workbench export

enum CoverExportService {
    struct LayoutContext {
        let pageCount: Int
        let spineWidthMM: Double

        @MainActor
        init(project: BinderyProject, workspace: BindingWorkspace) {
            let pages = workspace.assembledPageCount > 0
                ? workspace.assembledPageCount
                : max(0, project.estimatedPageCount)
            pageCount = pages
            spineWidthMM = project.effectiveSpineWidthMM(pageCount: pages)
        }
    }

    @MainActor
    static func exportBlueprintPDF(
        project: BinderyProject,
        workspace: BindingWorkspace,
        store: AppStore
    ) {
        let layout = LayoutContext(project: project, workspace: workspace)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "\(project.title)-cover-blueprint.pdf"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try CoverBlueprintService.writeBlueprint(
                for: project,
                pageCount: layout.pageCount,
                spineWidthMM: layout.spineWidthMM,
                to: url
            )
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            store.storeErrorMessage = error.localizedDescription
        }
    }

    @MainActor
    static func exportSVG(
        project: BinderyProject,
        workspace: BindingWorkspace,
        store: AppStore
    ) {
        let layout = LayoutContext(project: project, workspace: workspace)
        let panel = NSSavePanel()
        if let svgType = UTType(filenameExtension: "svg") {
            panel.allowedContentTypes = [svgType]
        } else {
            panel.allowedContentTypes = [.xml]
        }
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "\(project.title)-cover.svg"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try CoverBlueprintService.writeSVG(
                for: project,
                pageCount: layout.pageCount,
                spineWidthMM: layout.spineWidthMM,
                to: url
            )
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            store.storeErrorMessage = error.localizedDescription
        }
    }
}
