import AppKit
import Foundation
import UniformTypeIdentifiers

enum CoverBlueprintService {
    /// Flat wrap regions: back · back joint · spine · front joint · front.
    ///
    /// **Coordinate spaces**
    /// - Board-space: origin at top-left of the back board; panels use `panelOriginX`.
    /// - Material-space: origin at top-left of the covering-material sheet; board-space
    ///   points map via `toMaterialX` / `toMaterialY` (= board + turnIn).
    ///
    /// Artwork element coordinates remain board/wrap-space. Guides and cut marks are
    /// always computed in material-space from `productionLayout(spec:)`.
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
        /// Covering-material turn-in folded around every board edge (mm). Zero when
        /// the architecture does not wrap its boards.
        let turnInMM: Double

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
            turnInMM = project.effectiveTurnInMM
        }

        // MARK: - Turn-in / material layout

        /// True when the layout carries a folded covering-material overhang.
        var hasTurnIn: Bool { turnInMM > 0.05 }

        /// Full sheet of covering material to cut, including turn-ins on all sides.
        var materialW: Double { totalW + turnInMM * 2 }
        var materialH: Double { boardH + turnInMM * 2 }

        /// Sheet size including bleed (outer cut).
        func sheetW(bleedMM: Double) -> Double { materialW + max(0, bleedMM) * 2 }
        func sheetH(bleedMM: Double) -> Double { materialH + max(0, bleedMM) * 2 }

        /// Board-wrap origin inside the material sheet (top-left origin, mm).
        var boardOriginXMM: Double { turnInMM }
        var boardOriginYMM: Double { turnInMM }

        /// Board-space → material-space.
        func toMaterialX(_ boardX: Double) -> Double { boardX + turnInMM }
        func toMaterialY(_ boardY: Double) -> Double { boardY + turnInMM }
        /// Material-space → board-space.
        func toBoardX(_ materialX: Double) -> Double { materialX - turnInMM }
        func toBoardY(_ materialY: Double) -> Double { materialY - turnInMM }

        /// Canvas / export fit size: material sheet when turn-in is present.
        var displaySheetW: Double { hasTurnIn ? materialW : totalW }
        var displaySheetH: Double { hasTurnIn ? materialH : boardH }

        /// Turn-in guide geometry in material-space (legacy helper; prefer `productionLayout`).
        struct TurnInLayout {
            let materialRect: CGRect
            let boardRect: CGRect
            let foldXs: [Double]
            let miterCuts: [(CGPoint, CGPoint)]
        }

        func turnInLayout(foldXsMM: [Double]) -> TurnInLayout {
            let layout = productionLayout(spec: .default)
            let miters = layout.cornerCuts.map { ($0.a, $0.b) }
            return TurnInLayout(
                materialRect: layout.materialRect,
                boardRect: layout.boardRect,
                foldXs: foldXsMM.map(toMaterialX),
                miterCuts: miters
            )
        }

        /// Recalculate all production guides from board + midsection + hinge + turn-in + spec.
        func productionLayout(spec: CoverProductionSpec = .default) -> CoverProductionLayout {
            let t = turnInMM
            let bleed = max(0, spec.bleedMM)
            let material = CGRect(x: bleed, y: bleed, width: materialW, height: materialH)
            let board = CGRect(x: bleed + t, y: bleed + t, width: totalW, height: boardH)
            let cut = CGRect(x: 0, y: 0, width: sheetW(bleedMM: bleed), height: sheetH(bleedMM: bleed))
            let safeInset = min(spec.safeAreaMM, min(boardW, boardH) / 2 - 0.5)
            let safe = board.insetBy(dx: max(0, safeInset), dy: max(0, safeInset))

            let spineX = bleed + toMaterialX(panelOriginX(.spine))
            let spine = CGRect(x: spineX, y: board.minY, width: spineFace, height: boardH)

            var hinges: [CGRect] = []
            if hinge > 0.05 {
                hinges.append(CGRect(
                    x: bleed + toMaterialX(panelOriginX(.backHinge)),
                    y: board.minY,
                    width: hinge,
                    height: boardH
                ))
                hinges.append(CGRect(
                    x: bleed + toMaterialX(panelOriginX(.frontHinge)),
                    y: board.minY,
                    width: hinge,
                    height: boardH
                ))
            }

            let folds = guideXsMM.map { bleed + toMaterialX($0) }
            let corners = cornerCuts(
                treatment: spec.cornerTreatment,
                material: material,
                board: board,
                turnIn: t,
                radius: spec.cornerRadiusMM ?? t
            )
            let relief = reliefCuts(
                enabled: spec.reliefCutsEnabled && t > 0.05,
                board: board,
                length: spec.reliefCutLengthMM,
                inset: spec.reliefCutInsetMM
            )

            return CoverProductionLayout(
                cutRect: cut,
                materialRect: material,
                boardRect: board,
                safeRect: safe,
                spineRect: spine,
                hingeRects: hinges,
                foldXs: folds,
                cornerCuts: corners,
                reliefCuts: relief,
                turnInMM: t,
                bleedMM: bleed,
                cornerTreatment: spec.cornerTreatment
            )
        }

        private func cornerCuts(
            treatment: CoverCornerTreatment,
            material: CGRect,
            board: CGRect,
            turnIn t: Double,
            radius: Double
        ) -> [GuideSegment] {
            guard t > 0.05 else { return [] }
            let ml = material.minX
            let mt = material.minY
            let mr = material.maxX
            let mb = material.maxY
            let bl = board.minX
            let bt = board.minY
            let br = board.maxX
            let bb = board.maxY

            switch treatment {
            case .miter, .custom:
                // Custom falls back to miter until freeform paths exist.
                return [
                    GuideSegment(a: CGPoint(x: ml, y: bt), b: CGPoint(x: bl, y: mt)),
                    GuideSegment(a: CGPoint(x: br, y: mt), b: CGPoint(x: mr, y: bt)),
                    GuideSegment(a: CGPoint(x: ml, y: bb), b: CGPoint(x: bl, y: mb)),
                    GuideSegment(a: CGPoint(x: br, y: mb), b: CGPoint(x: mr, y: bb))
                ]
            case .square:
                // Square butt: cut along board edge then out to material (two segments per corner).
                return [
                    GuideSegment(a: CGPoint(x: ml, y: bt), b: CGPoint(x: bl, y: bt)),
                    GuideSegment(a: CGPoint(x: bl, y: bt), b: CGPoint(x: bl, y: mt)),
                    GuideSegment(a: CGPoint(x: br, y: mt), b: CGPoint(x: br, y: bt)),
                    GuideSegment(a: CGPoint(x: br, y: bt), b: CGPoint(x: mr, y: bt)),
                    GuideSegment(a: CGPoint(x: ml, y: bb), b: CGPoint(x: bl, y: bb)),
                    GuideSegment(a: CGPoint(x: bl, y: bb), b: CGPoint(x: bl, y: mb)),
                    GuideSegment(a: CGPoint(x: br, y: mb), b: CGPoint(x: br, y: bb)),
                    GuideSegment(a: CGPoint(x: br, y: bb), b: CGPoint(x: mr, y: bb))
                ]
            case .rounded:
                // Approximate rounded corner with a chord from board corner toward material corner.
                let r = min(radius, t)
                return [
                    GuideSegment(a: CGPoint(x: ml + (t - r), y: bt), b: CGPoint(x: bl, y: mt + (t - r))),
                    GuideSegment(a: CGPoint(x: br, y: mt + (t - r)), b: CGPoint(x: mr - (t - r), y: bt)),
                    GuideSegment(a: CGPoint(x: ml + (t - r), y: bb), b: CGPoint(x: bl, y: mb - (t - r))),
                    GuideSegment(a: CGPoint(x: br, y: mb - (t - r)), b: CGPoint(x: mr - (t - r), y: bb))
                ]
            }
        }

        private func reliefCuts(
            enabled: Bool,
            board: CGRect,
            length: Double,
            inset: Double
        ) -> [GuideSegment] {
            guard enabled, hinge > 0.05, length > 0.05 else { return [] }
            let backHingeX = board.minX + boardW
            let frontHingeX = board.minX + boardW + midsection
            let len = min(length, turnInMM)
            let insetClamped = min(inset, hinge * 0.5)
            // Head and tail relief near each hinge, cutting into the turn-in.
            return [
                GuideSegment(
                    a: CGPoint(x: backHingeX + insetClamped, y: board.minY),
                    b: CGPoint(x: backHingeX + insetClamped, y: board.minY - len)
                ),
                GuideSegment(
                    a: CGPoint(x: backHingeX + insetClamped, y: board.maxY),
                    b: CGPoint(x: backHingeX + insetClamped, y: board.maxY + len)
                ),
                GuideSegment(
                    a: CGPoint(x: frontHingeX - insetClamped, y: board.minY),
                    b: CGPoint(x: frontHingeX - insetClamped, y: board.minY - len)
                ),
                GuideSegment(
                    a: CGPoint(x: frontHingeX - insetClamped, y: board.maxY),
                    b: CGPoint(x: frontHingeX - insetClamped, y: board.maxY + len)
                )
            ]
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

        /// Guide lines in **board-space** for joints / spine edges.
        var guideXsMM: [Double] {
            var xs: [Double] = [boardW]
            if hinge > 0.05 {
                xs.append(boardW + hinge)
                xs.append(boardW + hinge + spineFace)
            } else {
                xs.append(boardW + midsection)
            }
            xs.append(boardW + midsection)
            return Array(Set(xs.map { ($0 * 100).rounded() / 100 })).sorted()
        }

        /// Joint / spine fold X positions in material-space.
        var materialGuideXsMM: [Double] {
            guideXsMM.map(toMaterialX)
        }

        func panel(containingWrapX x: Double) -> CoverPanel {
            for panel in layoutPanels.reversed() {
                let origin = panelOriginX(panel)
                if x >= origin { return panel }
            }
            return .back
        }
    }

    /// Rasterize the flat cover wrap (material base + design elements, no labels/guides).
    /// Origin is outside-up: back · joints · spine · front, left → right.
    static func renderWrapImage(
        for project: BinderyProject,
        spineWidthMM: Double,
        dpi: CGFloat = 150
    ) -> NSImage? {
        let geo = Geometry(project: project, spineWidthMM: spineWidthMM)
        let pixelsPerMM = dpi / 25.4
        let pixelW = max(2, Int(ceil(geo.totalW * Double(pixelsPerMM))))
        let pixelH = max(2, Int(ceil(geo.boardH * Double(pixelsPerMM))))
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: pixelW,
            height: pixelH,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        // Y-up to match PDF element drawing helpers.
        let nsContext = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsContext
        defer { NSGraphicsContext.restoreGraphicsState() }

        let scale = Double(pixelsPerMM)
        let origin = CGPoint(x: 0, y: 0)
        let h = geo.boardH * scale
        let base = materialBaseFill(project.coverMaterial)

        var cursor = 0.0
        for panel in geo.layoutPanels {
            let width = geo.panelWidth(panel) * scale
            let fill: NSColor
            switch panel {
            case .back, .front:
                fill = base
            case .spine:
                fill = base.blended(withFraction: 0.08, of: .black) ?? base
            case .backHinge, .frontHinge:
                fill = base.blended(withFraction: 0.04, of: .black) ?? base
            }
            ctx.setFillColor(fill.cgColor)
            ctx.fill(CGRect(x: cursor, y: 0, width: max(1, width), height: h))
            cursor += width
        }

        for element in project.orderedCoverElementsForRendering() where finishVisible(element.layer, in: project) {
            drawElement(
                element,
                geometry: geo,
                origin: origin,
                scale: scale,
                heightPts: h
            )
        }

        guard let cgImage = ctx.makeImage() else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: pixelW, height: pixelH))
    }

    static func materialBaseFill(_ material: CoverMaterial) -> NSColor {
        switch material {
        case .moroccanGoat:
            return NSColor(red: 0.92, green: 0.88, blue: 0.82, alpha: 1)
        case .bookram, .buckram:
            return NSColor(white: 0.93, alpha: 1)
        case .bookCloth:
            return .white
        case .paper:
            return NSColor(red: 0.96, green: 0.95, blue: 0.92, alpha: 1)
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

        let fitW = geo.hasTurnIn ? geo.materialW : geo.totalW
        let fitH = geo.hasTurnIn ? geo.materialH : geo.boardH
        let scale = min(620 / fitW, 360 / fitH)
        let startX = 40.0
        let startY = 90.0
        let h = geo.boardH * scale
        let inset = geo.turnInMM * scale
        let boardX = startX + inset
        let boardY = startY + inset

        // Covering-material sheet (cut edge) + turn-in fill, drawn under the panels.
        if geo.hasTurnIn {
            drawTurnInSheet(context, geo: geo, startX: startX, startY: startY, scale: scale)
        }

        var cursor = boardX
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
                rect: CGRect(x: cursor, y: boardY, width: max(1, width), height: h),
                fill: fill,
                label: label
            )
            cursor += width
        }

        for element in project.orderedCoverElementsForRendering() where finishVisible(element.layer, in: project) {
            drawElement(
                element,
                geometry: geo,
                origin: CGPoint(x: boardX, y: boardY),
                scale: scale,
                heightPts: h
            )
        }

        // Fold + miter cut marks over the panels.
        if geo.hasTurnIn {
            drawTurnInMarks(context, geo: geo, startX: startX, startY: startY, scale: scale)
        }

        let widthLabel = geo.hasTurnIn
            ? String(format: "BOARD WRAP: %.1f mm  ·  MATERIAL incl. turn-in: %.1f × %.1f mm", geo.totalW, geo.materialW, geo.materialH)
            : String(format: "TOTAL WIDTH: %.1f mm", geo.totalW)
        drawText(
            widthLabel,
            at: CGPoint(x: startX, y: startY + fitH * scale + 18),
            size: 10,
            color: NSColor(red: 0.0, green: 0.125, blue: 0.271, alpha: 0.7)
        )

        var metrics = [
            String(format: "Spine: %.2f mm", spineWidthMM),
            String(format: "Board: %.2f mm · Groove: %.2f mm", project.boardThicknessMM, project.hingeGapMM),
            "Pages: \(pageCount) · GSM: \(Int(project.textPaperGSM))",
            "Layers: \(layerLabel(project))"
        ]
        if geo.hasTurnIn {
            metrics.append(String(
                format: "Turn-in: %.1f mm (fold to inside) · Pastedown reveal: %.1f mm",
                geo.turnInMM, max(0, project.pastedownInsetMM)
            ))
        }
        let metricsTop = 50.0 + Double(max(0, metrics.count - 4)) * 14.0
        for (index, metric) in metrics.enumerated() {
            drawText(metric, at: CGPoint(x: 40, y: metricsTop - Double(index * 14)), size: 10, color: .labelColor)
        }

        context.endPDFPage()
        context.closePDF()
        try (data as Data).write(to: url, options: [.atomic])
    }

    static func writeSVG(
        for project: BinderyProject,
        pageCount: Int,
        spineWidthMM: Double,
        to url: URL,
        mode: SVGDocumentBuilder.ExportMode = .production
    ) throws {
        let geo = Geometry(project: project, spineWidthMM: spineWidthMM)
        let production = project.coverProduction
        let layout = geo.productionLayout(spec: production)
        let visibility = production.guideVisibility
        let margin = mode.includesGuides ? 24.0 : 0.0
        let labelH = mode.includesGuides ? 28.0 : 0.0
        let t = geo.turnInMM
        let bleed = layout.bleedMM
        let sheetW = layout.cutRect.width
        let sheetH = layout.cutRect.height
        let canvasW = sheetW + margin * 2
        let canvasH = sheetH + margin * 2 + labelH
        let headerLabel = geo.hasTurnIn
            ? "MATERIAL incl. turn-in: \(fmt(geo.materialW))mm × \(fmt(geo.materialH))mm · board wrap \(fmt(geo.totalW))mm"
            : "TOTAL WIDTH: \(fmt(geo.totalW))mm"

        var svg = SVGDocumentBuilder.rootOpen(
            widthMM: canvasW,
            heightMM: canvasH,
            title: "\(project.title) — Cover \(mode == .clean ? "Artwork" : "Blueprint")",
            desc: "Spine \(fmt(spineWidthMM))mm · \(pageCount) pages · \(project.coverMaterial.rawValue)"
        )

        if mode.includesGuides {
            svg += """
              <defs>
                <pattern id="grid" width="10" height="10" patternUnits="userSpaceOnUse">
                  <path d="M 10 0 L 0 0 0 10" fill="none" stroke="#c4c6cf" stroke-width="0.2"/>
                </pattern>
              </defs>
              <rect width="100%" height="100%" fill="#f9f9ff"/>
              <rect x="0" y="0" width="\(fmt(canvasW))" height="\(fmt(canvasH))" fill="url(#grid)"/>
            """
        } else {
            svg += "<rect width=\"100%\" height=\"100%\" fill=\"#ffffff\"/>\n"
        }

        svg += "<g transform=\"translate(\(fmt(margin)), \(fmt(margin + (mode.includesGuides ? 12 : 0))))\">\n"
        if mode.includesGuides {
            svg += """
                <text x="0" y="-4" font-family="system-ui, sans-serif" font-size="3.2" fill="#74777f" letter-spacing="0.4">\(escape(headerLabel))</text>
            """
        }

        // Artwork lives in board-space, nested at the board origin inside the cut sheet.
        let boardOX = bleed + t
        let boardOY = bleed + t
        if mode.includesGuides, geo.hasTurnIn || bleed > 0.05 {
            // Turn-in / material fill (not artwork).
            svg += SVGDocumentBuilder.rect(
                x: layout.materialRect.minX,
                y: layout.materialRect.minY,
                w: layout.materialRect.width,
                h: layout.materialRect.height,
                fill: "#f5eedc",
                stroke: nil
            )
        }

        svg += "<g id=\"artwork\" transform=\"translate(\(fmt(boardOX)), \(fmt(boardOY)))\">\n"

        if mode.includesGuides {
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
        } else {
            // Clean: solid material base only (no panel labels).
            svg += SVGDocumentBuilder.rect(
                x: 0, y: 0, w: geo.totalW, h: geo.boardH,
                fill: "#f7f4ec", stroke: nil
            )
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

        svg += "</g>\n" // artwork

        if mode.includesGuides {
            svg += productionGuidesSVG(layout: layout, geo: geo, visibility: visibility)
        }

        svg += "</g>\n"
        svg += SVGDocumentBuilder.rootClose
        try Data(svg.utf8).write(to: url, options: [.atomic])
    }

    /// Production marks in material/cut space. Never part of the artwork group.
    private static func productionGuidesSVG(
        layout: CoverProductionLayout,
        geo: Geometry,
        visibility: CoverGuideVisibility
    ) -> String {
        var out = ""
        let cutStroke = "#992020"
        let foldStroke = "#002045"

        if visibility.cut {
            var content = SVGDocumentBuilder.rect(
                x: layout.cutRect.minX,
                y: layout.cutRect.minY,
                w: layout.cutRect.width,
                h: layout.cutRect.height,
                fill: nil,
                stroke: cutStroke,
                strokeWidth: 0.5
            )
            if layout.bleedMM > 0.05 {
                content += SVGDocumentBuilder.rect(
                    x: layout.materialRect.minX,
                    y: layout.materialRect.minY,
                    w: layout.materialRect.width,
                    h: layout.materialRect.height,
                    fill: nil,
                    stroke: cutStroke,
                    strokeWidth: 0.35,
                    dash: "1 1",
                    opacity: 0.7
                )
            }
            out += SVGDocumentBuilder.guideGroup(id: "guides-cut", content: content)
        }

        if visibility.fold || visibility.board {
            var content = ""
            if visibility.board || visibility.fold {
                content += SVGDocumentBuilder.rect(
                    x: layout.boardRect.minX,
                    y: layout.boardRect.minY,
                    w: layout.boardRect.width,
                    h: layout.boardRect.height,
                    fill: nil,
                    stroke: foldStroke,
                    strokeWidth: 0.4,
                    dash: "3 2",
                    opacity: 0.85
                )
            }
            if visibility.fold {
                for x in layout.foldXs {
                    content += SVGDocumentBuilder.line(
                        x1: x, y1: layout.materialRect.minY,
                        x2: x, y2: layout.materialRect.maxY,
                        stroke: foldStroke, width: 0.35, dash: "3 2", opacity: 0.7
                    )
                }
            }
            out += SVGDocumentBuilder.guideGroup(id: "guides-fold", content: content)
        }

        if visibility.spine {
            let s = layout.spineRect
            out += SVGDocumentBuilder.guideGroup(
                id: "guides-spine",
                content: SVGDocumentBuilder.rect(
                    x: s.minX, y: s.minY, w: s.width, h: s.height,
                    fill: nil, stroke: "#3355aa", strokeWidth: 0.3, dash: "2 2", opacity: 0.8
                )
            )
        }

        if visibility.hinge {
            var content = ""
            for h in layout.hingeRects {
                content += SVGDocumentBuilder.rect(
                    x: h.minX, y: h.minY, w: h.width, h: h.height,
                    fill: nil, stroke: "#667744", strokeWidth: 0.3, dash: "2 2", opacity: 0.75
                )
            }
            out += SVGDocumentBuilder.guideGroup(id: "guides-hinge", content: content)
        }

        if visibility.safe {
            let s = layout.safeRect
            out += SVGDocumentBuilder.guideGroup(
                id: "guides-safe",
                content: SVGDocumentBuilder.rect(
                    x: s.minX, y: s.minY, w: s.width, h: s.height,
                    fill: nil, stroke: "#228866", strokeWidth: 0.25, dash: "1 2", opacity: 0.65
                )
            )
        }

        if visibility.corner, !layout.cornerCuts.isEmpty {
            var content = ""
            for seg in layout.cornerCuts {
                content += SVGDocumentBuilder.line(
                    x1: Double(seg.a.x), y1: Double(seg.a.y),
                    x2: Double(seg.b.x), y2: Double(seg.b.y),
                    stroke: cutStroke, width: 0.5
                )
            }
            out += SVGDocumentBuilder.guideGroup(id: "guides-corner", content: content)
        }

        if visibility.relief, !layout.reliefCuts.isEmpty {
            var content = ""
            for seg in layout.reliefCuts {
                content += SVGDocumentBuilder.line(
                    x1: Double(seg.a.x), y1: Double(seg.a.y),
                    x2: Double(seg.b.x), y2: Double(seg.b.y),
                    stroke: cutStroke, width: 0.4, dash: "1 1"
                )
            }
            out += SVGDocumentBuilder.guideGroup(id: "guides-relief", content: content)
        }

        if visibility.trim, layout.bleedMM > 0.05 {
            out += SVGDocumentBuilder.guideGroup(
                id: "guides-trim",
                content: SVGDocumentBuilder.rect(
                    x: layout.materialRect.minX,
                    y: layout.materialRect.minY,
                    w: layout.materialRect.width,
                    h: layout.materialRect.height,
                    fill: nil,
                    stroke: "#aa6622",
                    strokeWidth: 0.3,
                    dash: "4 2",
                    opacity: 0.7
                )
            )
        }

        if geo.hasTurnIn {
            out += """
            <text x="\(fmt(layout.cutRect.minX))" y="\(fmt(layout.cutRect.maxY + 4))" font-family="system-ui, sans-serif" font-size="3" fill="#992020">TURN-IN \(fmt(geo.turnInMM))mm · \(escape(layout.cornerTreatment.title)) — solid = cut, dashed = fold · guides are not artwork</text>
            """
        }
        return out
    }

    // MARK: - Turn-in guide drawing (PDF, Y-up device space)

    /// Cut edge + folded overhang fill for the covering material sheet.
    private static func drawTurnInSheet(
        _ context: CGContext,
        geo: Geometry,
        startX: Double,
        startY: Double,
        scale: Double
    ) {
        let materialRect = CGRect(
            x: startX,
            y: startY,
            width: geo.materialW * scale,
            height: geo.materialH * scale
        )
        context.setFillColor(NSColor(red: 0.96, green: 0.93, blue: 0.86, alpha: 1).cgColor)
        context.fill(materialRect)
        // Outer edge is the cut line.
        context.setStrokeColor(NSColor(red: 0.60, green: 0.10, blue: 0.10, alpha: 1).cgColor)
        context.setLineDash(phase: 0, lengths: [])
        context.setLineWidth(1.2)
        context.stroke(materialRect)
    }

    /// Board/spine fold rectangle, joint folds, and 45° corner miter cuts.
    private static func drawTurnInMarks(
        _ context: CGContext,
        geo: Geometry,
        startX: Double,
        startY: Double,
        scale: Double
    ) {
        let layout = geo.turnInLayout(foldXsMM: geo.guideXsMM)
        // Top-left mm → Y-up device.
        func dev(_ p: CGPoint) -> CGPoint {
            CGPoint(x: startX + Double(p.x) * scale, y: startY + (geo.materialH - Double(p.y)) * scale)
        }

        // Board fold rectangle (dashed).
        let foldColor = NSColor(red: 0.0, green: 0.125, blue: 0.271, alpha: 0.85)
        context.setStrokeColor(foldColor.cgColor)
        context.setLineWidth(0.8)
        context.setLineDash(phase: 0, lengths: [5, 4])
        let boardTopLeft = dev(CGPoint(x: layout.boardRect.minX, y: layout.boardRect.minY))
        let boardRectDevice = CGRect(
            x: boardTopLeft.x,
            y: boardTopLeft.y - geo.boardH * scale,
            width: geo.totalW * scale,
            height: geo.boardH * scale
        )
        context.stroke(boardRectDevice)

        // Joint / spine fold lines across the material height.
        for x in layout.foldXs {
            let top = dev(CGPoint(x: x, y: 0))
            let bottom = dev(CGPoint(x: x, y: geo.materialH))
            context.move(to: top)
            context.addLine(to: bottom)
        }
        context.strokePath()

        // Corner miter cuts (solid).
        context.setLineDash(phase: 0, lengths: [])
        context.setStrokeColor(NSColor(red: 0.60, green: 0.10, blue: 0.10, alpha: 1).cgColor)
        context.setLineWidth(1.0)
        for (a, b) in layout.miterCuts {
            context.move(to: dev(a))
            context.addLine(to: dev(b))
        }
        context.strokePath()

        drawText(
            String(format: "TURN-IN %.0f mm — solid = cut, dashed = fold", geo.turnInMM),
            at: CGPoint(x: startX, y: startY + geo.materialH * scale + 4),
            size: 8,
            color: NSColor(red: 0.60, green: 0.10, blue: 0.10, alpha: 1)
        )
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
        // Marbled fill: regeneratable raster under the stroke path.
        if element.shapeType != .line, let marble = element.fill.marbling {
            let fx = ox - w / 2
            let fy = oy - h / 2
            body += SVGDocumentBuilder.marbledImageElement(
                spec: marble, x: fx, y: fy, width: w, height: h
            )
        }
        let fill: String = {
            guard element.shapeType != .line else { return "none" }
            if element.fill.isMarbled { return "none" }
            guard let solid = element.fill.solidColor else { return "none" }
            return hexFromCodable(solid)
        }()
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
        store: AppStore,
        mode: SVGDocumentBuilder.ExportMode = .production
    ) {
        let layout = LayoutContext(project: project, workspace: workspace)
        let panel = NSSavePanel()
        if let svgType = UTType(filenameExtension: "svg") {
            panel.allowedContentTypes = [svgType]
        } else {
            panel.allowedContentTypes = [.xml]
        }
        panel.canCreateDirectories = true
        let suffix = mode == .clean ? "cover-artwork" : "cover"
        panel.nameFieldStringValue = "\(project.title)-\(suffix).svg"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try CoverBlueprintService.writeSVG(
                for: project,
                pageCount: layout.pageCount,
                spineWidthMM: layout.spineWidthMM,
                to: url,
                mode: mode
            )
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            store.storeErrorMessage = error.localizedDescription
        }
    }
}
