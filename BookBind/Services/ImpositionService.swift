import AppKit
import CoreText
import Foundation
import PDFKit

/// Plans and imposes folio signatures and single-sheet zine / fold layouts.
enum ImpositionService {
    /// Page trim derived from stock (zine/accordion) or identity (folio).
    static func pageTrimSize(stockOrTrim: CGSize, job: BindingJob) -> CGSize {
        let w = max(1, stockOrTrim.width)
        let h = max(1, stockOrTrim.height)
        switch job.impositionScheme {
        case .folioSignatures, .halfFoldBooklet:
            return CGSize(width: w, height: h)
        case .miniZine8:
            return CGSize(width: w / 4, height: h / 2)
        case .miniZine16:
            return CGSize(width: w / 4, height: h / 4)
        case .accordion:
            let panels = CGFloat(job.resolvedAccordionPanelCount)
            return CGSize(width: w / panels, height: h)
        }
    }

    /// Compute padding and signature / sheet-unit count for a job.
    static func plan(
        contentPageCount: Int,
        job: BindingJob
    ) -> BindingPlan {
        let endpapers = max(0, job.frontEndpapers) + max(0, job.backEndpapers)
        let rawTotal = contentPageCount + endpapers

        let pagesPerSignature: Int
        let signatureCount: Int
        let padPages: Int
        let printSheets: Int
        let scheme = job.impositionScheme

        switch scheme {
        case .miniZine8:
            let unit = 8
            let padded = rawTotal == 0 ? 0 : ((rawTotal + unit - 1) / unit) * unit
            pagesPerSignature = unit
            signatureCount = padded == 0 ? 0 : padded / unit
            padPages = max(0, padded - rawTotal)
            printSheets = signatureCount
        case .miniZine16:
            let unit = 16
            let padded = rawTotal == 0 ? 0 : ((rawTotal + unit - 1) / unit) * unit
            pagesPerSignature = unit
            signatureCount = padded == 0 ? 0 : padded / unit
            padPages = max(0, padded - rawTotal)
            printSheets = signatureCount
        case .accordion:
            let unit = job.resolvedAccordionPanelCount
            let padded = rawTotal == 0 ? 0 : ((rawTotal + unit - 1) / unit) * unit
            pagesPerSignature = unit
            signatureCount = padded == 0 ? 0 : padded / unit
            padPages = max(0, padded - rawTotal)
            printSheets = signatureCount
        case .halfFoldBooklet:
            pagesPerSignature = ((rawTotal + 3) / 4) * 4
            signatureCount = pagesPerSignature == 0 ? 0 : 1
            padPages = max(0, pagesPerSignature - rawTotal)
            printSheets = pagesPerSignature / 4
        case .folioSignatures:
            switch job.bindingStyle {
            case .saddleStitch:
                pagesPerSignature = ((rawTotal + 3) / 4) * 4
                signatureCount = pagesPerSignature == 0 ? 0 : 1
                padPages = max(0, pagesPerSignature - rawTotal)
                printSheets = pagesPerSignature / 4
            case .caseBound, .sectionSewn, .perfectBound, .coptic:
                let size = job.signatureSize.rawValue
                pagesPerSignature = size
                let padded = ((rawTotal + size - 1) / size) * size
                signatureCount = padded == 0 ? 0 : padded / size
                padPages = max(0, padded - rawTotal)
                printSheets = signatureCount * (size / 4)
            }
        }

        return BindingPlan(
            contentPageCount: contentPageCount,
            frontEndpapers: max(0, job.frontEndpapers),
            backEndpapers: max(0, job.backEndpapers),
            padPages: padPages,
            signatureCount: signatureCount,
            pagesPerSignature: pagesPerSignature,
            totalBookPages: rawTotal + padPages,
            printSheetsRequired: printSheets,
            impositionScheme: scheme
        )
    }

    /// Classic 8-page one-sheet zine (2×4). Top row upside-down; center slit across middle two columns.
    static func miniZine8Layout(template: MiniZine8Template = .classicNested) -> SheetLayout {
        // Columns L→R, rows bottom→top in PDF space (row 0 = bottom).
        var cells: [SheetCellPlacement] = []
        for (col, page) in template.bottomRowPages.enumerated() {
            cells.append(SheetCellPlacement(pageIndex: page, column: col, row: 0, rotationDegrees: 0))
        }
        for (col, page) in template.topRowPages.enumerated() {
            cells.append(SheetCellPlacement(pageIndex: page, column: col, row: 1, rotationDegrees: 180))
        }
        return SheetLayout(columns: 4, rows: 2, cells: cells, guides: [], pagesPerSheet: 8)
    }

    /// 16-page one-sheet mini-zine (4×4). Top two rows rotated 180°.
    static func miniZine16Layout(template: MiniZine16Template = .crossCut) -> SheetLayout {
        // Nested reading order for a 4×4 single-sheet fold (0-based indices).
        // Row indices are PDF bottom→top.
        let upright: [[Int]] = [
            [8, 9, 10, 11],
            [12, 13, 14, 15]
        ]
        let inverted: [[Int]] = [
            [7, 6, 5, 4],
            [3, 2, 1, 0]
        ]

        var cells: [SheetCellPlacement] = []
        for (row, pages) in upright.enumerated() {
            for (col, page) in pages.enumerated() {
                cells.append(SheetCellPlacement(pageIndex: page, column: col, row: row, rotationDegrees: 0))
            }
        }
        for (offset, pages) in inverted.enumerated() {
            let row = offset + 2
            for (col, page) in pages.enumerated() {
                cells.append(SheetCellPlacement(pageIndex: page, column: col, row: row, rotationDegrees: 180))
            }
        }
        // Template only affects cut guides today; page map is shared.
        _ = template
        return SheetLayout(columns: 4, rows: 4, cells: cells, guides: [], pagesPerSheet: 16)
    }

    static func accordionLayout(panelCount: Int) -> SheetLayout {
        let count = min(BindingJob.maxAccordionPanels, max(BindingJob.minAccordionPanels, panelCount))
        let cells = (0..<count).map { index in
            SheetCellPlacement(pageIndex: index, column: index, row: 0, rotationDegrees: 0)
        }
        return SheetLayout(columns: count, rows: 1, cells: cells, guides: [], pagesPerSheet: count)
    }

    /// Unit layout for a single-sheet scheme (guides filled for a given stock size).
    static func sheetLayout(for job: BindingJob, stockSize: CGSize) -> SheetLayout {
        var layout: SheetLayout
        switch job.impositionScheme {
        case .miniZine8:
            layout = miniZine8Layout(template: job.miniZine8Template)
        case .miniZine16:
            layout = miniZine16Layout(template: job.miniZine16Template)
        case .accordion:
            layout = accordionLayout(panelCount: job.resolvedAccordionPanelCount)
        case .folioSignatures, .halfFoldBooklet:
            layout = SheetLayout(columns: 2, rows: 1, cells: [], guides: [], pagesPerSheet: 4)
        }
        layout.guides = guideSegments(for: job, layout: layout, stockSize: stockSize)
        return layout
    }

    static func guideSegments(
        for job: BindingJob,
        layout: SheetLayout,
        stockSize: CGSize
    ) -> [SheetGuideSegment] {
        let w = stockSize.width
        let h = stockSize.height
        guard layout.columns > 0, layout.rows > 0 else { return [] }
        let cellW = w / CGFloat(layout.columns)
        let cellH = h / CGFloat(layout.rows)

        var guides: [SheetGuideSegment] = []

        if layout.columns > 1 {
            for col in 1..<layout.columns {
                let x = cellW * CGFloat(col)
                guides.append(SheetGuideSegment(
                    kind: .fold,
                    start: CGPoint(x: x, y: 0),
                    end: CGPoint(x: x, y: h)
                ))
            }
        }

        if layout.rows > 1 {
            for row in 1..<layout.rows {
                let y = cellH * CGFloat(row)
                guides.append(SheetGuideSegment(
                    kind: .fold,
                    start: CGPoint(x: 0, y: y),
                    end: CGPoint(x: w, y: y)
                ))
            }
        }

        switch job.impositionScheme {
        case .miniZine8:
            // Classic slit: horizontal center, middle two columns only — never to the sheet edges.
            let y = h / 2
            guides.append(SheetGuideSegment(
                kind: .cut,
                start: CGPoint(x: cellW, y: y),
                end: CGPoint(x: cellW * 3, y: y)
            ))
        case .miniZine16:
            switch job.miniZine16Template {
            case .crossCut:
                let midX = w / 2
                let midY = h / 2
                guides.append(SheetGuideSegment(
                    kind: .cut,
                    start: CGPoint(x: cellW, y: midY),
                    end: CGPoint(x: cellW * 3, y: midY)
                ))
                guides.append(SheetGuideSegment(
                    kind: .cut,
                    start: CGPoint(x: midX, y: cellH),
                    end: CGPoint(x: midX, y: cellH * 3)
                ))
            case .horizontalSlits:
                // Horizontal slits on the upper and lower inner midlines,
                // each spanning the middle two columns only (same span as the 8-page slit).
                for rowGap in [1, 3] {
                    let y = cellH * CGFloat(rowGap)
                    guides.append(SheetGuideSegment(
                        kind: .cut,
                        start: CGPoint(x: cellW, y: y),
                        end: CGPoint(x: cellW * 3, y: y)
                    ))
                }
            }
        case .accordion, .folioSignatures, .halfFoldBooklet:
            break
        }

        return guides
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
            let frontLeft = pageCount - 1 - (sheet * 2)
            let frontRight = sheet * 2
            sides.append((frontLeft, frontRight))

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
        let outer = PrinterMarks.margin(bleed: bleed, marks: addCropMarks)
        return CGSize(
            width: pageSize.width * 2 + outer * 2,
            height: pageSize.height + outer * 2
        )
    }

    /// Media size for a single stock sheet layout (+ optional bleed / crop room).
    static func sheetMediaSize(
        stockSize: CGSize,
        bleed: CGFloat,
        addCropMarks: Bool
    ) -> CGSize {
        let outer = PrinterMarks.margin(bleed: bleed, marks: addCropMarks)
        return CGSize(width: stockSize.width + outer * 2, height: stockSize.height + outer * 2)
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

    /// Label for the physical stock sheet (zine / accordion) or folio printer spread.
    static func printerSheetLabel(for job: BindingJob, pageSize: CGSize) -> String {
        if job.impositionScheme.paperSizeIsStockSheet,
           let stock = job.resolvedStockSheetSize {
            return stockSheetLabel(stock)
        }
        return printerSheetLabel(pageSize: pageSize)
    }

    static func stockSheetLabel(_ size: CGSize) -> String {
        func approx(_ a: CGSize, _ b: CGSize, tolerance: CGFloat = 3) -> Bool {
            abs(a.width - b.width) <= tolerance && abs(a.height - b.height) <= tolerance
        }
        let letter = CGSize(width: 612, height: 792)
        let a4 = CGSize(width: 595.28, height: 841.89)
        let a5 = CGSize(width: 419.53, height: 595.28)
        if approx(size, letter) { return "US Letter" }
        if approx(size, a4) { return "A4" }
        if approx(size, a5) { return "A5" }
        if approx(size, CGSize(width: letter.height, height: letter.width)) { return "US Letter Landscape" }
        if approx(size, CGSize(width: a4.height, height: a4.width)) { return "A4 Landscape" }
        return String(format: "%.1f×%.1f in", size.width / 72, size.height / 72)
    }

    /// Impose using the full job (preferred entry point).
    static func impose(
        bookBlock: PDFDocument,
        plan: BindingPlan,
        job: BindingJob,
        slugTitle: String? = nil
    ) throws -> PDFDocument {
        try impose(
            bookBlock: bookBlock,
            plan: plan,
            style: job.bindingStyle,
            scheme: job.impositionScheme,
            accordionPanelCount: job.resolvedAccordionPanelCount,
            stockSheetSize: job.resolvedStockSheetSize,
            addCropMarks: job.addCropMarks,
            showGuideMarks: job.showGuideMarks,
            showStitchHoleMarks: job.showStitchHoleMarks,
            stitchHoleCount: job.stitchHoleCount,
            creepPoints: job.creepPoints,
            bleedPoints: job.bleedPoints,
            slugTitle: slugTitle
        )
    }

    /// Backward-compatible folio impose entry (scheme taken from `plan`).
    static func impose(
        bookBlock: PDFDocument,
        plan: BindingPlan,
        style: BindingStyle,
        addCropMarks: Bool,
        showGuideMarks: Bool,
        showStitchHoleMarks: Bool = false,
        stitchHoleCount: StitchHoleCount = .auto,
        creepPoints: CGFloat = 0,
        bleedPoints: CGFloat = 0
    ) throws -> PDFDocument {
        try impose(
            bookBlock: bookBlock,
            plan: plan,
            style: style,
            scheme: plan.impositionScheme,
            accordionPanelCount: 6,
            stockSheetSize: nil,
            addCropMarks: addCropMarks,
            showGuideMarks: showGuideMarks,
            showStitchHoleMarks: showStitchHoleMarks,
            stitchHoleCount: stitchHoleCount,
            creepPoints: creepPoints,
            bleedPoints: bleedPoints
        )
    }

    static func impose(
        bookBlock: PDFDocument,
        plan: BindingPlan,
        style: BindingStyle,
        scheme: ImpositionScheme,
        accordionPanelCount: Int,
        stockSheetSize: CGSize?,
        addCropMarks: Bool,
        showGuideMarks: Bool,
        showStitchHoleMarks: Bool,
        stitchHoleCount: StitchHoleCount,
        creepPoints: CGFloat,
        bleedPoints: CGFloat,
        slugTitle: String? = nil
    ) throws -> PDFDocument {
        guard bookBlock.pageCount > 0 else { throw BindingError.emptyDocument }
        guard plan.totalBookPages == bookBlock.pageCount else {
            throw BindingError.invalidConfiguration(
                "Book block page count (\(bookBlock.pageCount)) does not match plan (\(plan.totalBookPages))."
            )
        }

        if !scheme.usesFolioImpose {
            return try imposeSheetLayout(
                bookBlock: bookBlock,
                plan: plan,
                scheme: scheme,
                accordionPanelCount: accordionPanelCount,
                stockSheetSize: stockSheetSize,
                addCropMarks: addCropMarks,
                showGuideMarks: showGuideMarks,
                bleedPoints: bleedPoints,
                slugTitle: slugTitle
            )
        }

        return try imposeFolio(
            bookBlock: bookBlock,
            plan: plan,
            style: style,
            addCropMarks: addCropMarks,
            showGuideMarks: showGuideMarks,
            showStitchHoleMarks: showStitchHoleMarks,
            stitchHoleCount: stitchHoleCount,
            creepPoints: creepPoints,
            bleedPoints: bleedPoints,
            slugTitle: slugTitle
        )
    }

    private static func imposeFolio(
        bookBlock: PDFDocument,
        plan: BindingPlan,
        style: BindingStyle,
        addCropMarks: Bool,
        showGuideMarks: Bool,
        showStitchHoleMarks: Bool,
        stitchHoleCount: StitchHoleCount,
        creepPoints: CGFloat,
        bleedPoints: CGFloat,
        slugTitle: String?
    ) throws -> PDFDocument {
        let pageSize = PDFDocumentService.pageSize(of: bookBlock)
        let output = PDFDocument()
        var outIndex = 0

        let signatureLength = plan.pagesPerSignature
        let signatureCount = plan.signatureCount
        let sheetsPerSignature = max(1, signatureLength / 4)
        let creep = max(0, creepPoints)
        let bleed = max(0, bleedPoints)
        let drawStitchMarks = showStitchHoleMarks && style.usesStitchHoleMarks
        let resolvedStitchHoles = drawStitchMarks
            ? resolvedStitchHoleCount(
                setting: stitchHoleCount,
                sheetCount: plan.sheetCount,
                pageHeight: pageSize.height
            )
            : 0

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
                    guard showGuideMarks, style.usesSignatures else { return nil }
                    return "Sig \(sig + 1)"
                }()
                let slug: String? = addCropMarks ? PrinterMarks.slugText(
                    title: slugTitle,
                    parts: [
                        style.usesSignatures ? "Sig \(sig + 1) of \(signatureCount)" : "",
                        "Sheet \(sheetIndex + 1) \(sideIndex.isMultiple(of: 2) ? "Front" : "Back")",
                        PrinterMarks.pageRange([leftGlobal, rightGlobal])
                    ]
                ) : nil

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
                    stitchHoleCount: resolvedStitchHoles,
                    signatureLabel: signatureLabel,
                    slug: slug,
                    creepOffset: offset,
                    bleed: bleed
                )

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

    private static func imposeSheetLayout(
        bookBlock: PDFDocument,
        plan: BindingPlan,
        scheme: ImpositionScheme,
        accordionPanelCount: Int,
        stockSheetSize: CGSize?,
        addCropMarks: Bool,
        showGuideMarks: Bool,
        bleedPoints: CGFloat,
        slugTitle: String?
    ) throws -> PDFDocument {
        let pageSize = PDFDocumentService.pageSize(of: bookBlock)
        let unit = plan.pagesPerSignature
        guard unit > 0, plan.signatureCount > 0 else {
            throw BindingError.invalidConfiguration("Nothing to impose for this sheet layout.")
        }

        let stock: CGSize
        if let stockSheetSize, stockSheetSize.width > 0, stockSheetSize.height > 0 {
            stock = stockSheetSize
        } else {
            switch scheme {
            case .miniZine8:
                stock = CGSize(width: pageSize.width * 4, height: pageSize.height * 2)
            case .miniZine16:
                stock = CGSize(width: pageSize.width * 4, height: pageSize.height * 4)
            case .accordion:
                stock = CGSize(width: pageSize.width * CGFloat(unit), height: pageSize.height)
            default:
                stock = CGSize(width: pageSize.width * 2, height: pageSize.height)
            }
        }

        var job = BindingJob()
        job.impositionScheme = scheme
        job.accordionPanelCount = accordionPanelCount
        let layout = sheetLayout(for: job, stockSize: stock)

        let bleed = max(0, bleedPoints)
        let mediaSize = sheetMediaSize(stockSize: stock, bleed: bleed, addCropMarks: addCropMarks)
        let output = PDFDocument()
        var outIndex = 0

        for unitIndex in 0..<plan.signatureCount {
            let start = unitIndex * unit
            let data = renderSheetLayoutPDF(
                bookBlock: bookBlock,
                pageStart: start,
                layout: layout,
                stockSize: stock,
                mediaSize: mediaSize,
                addCropMarks: addCropMarks,
                showGuides: showGuideMarks,
                bleed: bleed,
                sheetLabel: showGuideMarks ? "Sheet \(unitIndex + 1)" : nil,
                slug: addCropMarks ? PrinterMarks.slugText(
                    title: slugTitle,
                    parts: [
                        "Sheet \(unitIndex + 1) of \(plan.signatureCount)",
                        PrinterMarks.pageRange([start, start + unit - 1])
                    ]
                ) : nil
            )
            guard let sheetDoc = PDFDocument(data: data),
                  let sheetPage = sheetDoc.page(at: 0) else {
                continue
            }
            output.insert(sheetPage, at: outIndex)
            outIndex += 1
        }

        return output
    }

    /// Human-readable signature / sheet map with 1-based book page numbers.
    static func signatureMap(for plan: BindingPlan, job: BindingJob? = nil) -> SignatureMap {
        guard plan.signatureCount > 0, plan.pagesPerSignature > 0 else {
            return SignatureMap(sides: [], plan: plan, sheetLayouts: [])
        }

        if !plan.impositionScheme.usesFolioImpose {
            let stock = job?.resolvedStockSheetSize ?? CGSize(width: 612, height: 792)
            var prototype = job ?? BindingJob()
            prototype.impositionScheme = plan.impositionScheme
            if plan.impositionScheme == .accordion {
                prototype.accordionPanelCount = plan.pagesPerSignature
            }
            let baseLayout = sheetLayout(for: prototype, stockSize: stock)

            var layouts: [SheetLayout] = []
            var sides: [SignatureSheetSide] = []
            for unit in 0..<plan.signatureCount {
                let start = unit * plan.pagesPerSignature
                var layout = baseLayout
                layout.cells = baseLayout.cells.map { cell in
                    var copy = cell
                    if let local = cell.pageIndex {
                        copy.pageIndex = start + local
                    }
                    return copy
                }
                layouts.append(layout)

                for row in (0..<layout.rows).reversed() {
                    let rowCells = layout.cells.filter { $0.row == row }.sorted { $0.column < $1.column }
                    let labels = rowCells.map { cell in
                        let page = cell.pageIndex.map { String($0 + 1) } ?? "—"
                        if cell.rotationDegrees == 0 {
                            return page
                        }
                        return "\(page)↻"
                    }.joined(separator: " · ")
                    sides.append(
                        SignatureSheetSide(
                            signatureIndex: unit + 1,
                            sheetIndex: 1,
                            face: .front,
                            leftPage: nil,
                            rightPage: nil,
                            gridLabel: "R\(layout.rows - row): \(labels)"
                        )
                    )
                }
            }
            return SignatureMap(sides: sides, plan: plan, sheetLayouts: layouts)
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

        return SignatureMap(sides: sides, plan: plan, sheetLayouts: [])
    }

    /// Suggested staple count from nested sheet count and trim height.
    static func recommendedStitchHoleCount(sheetCount: Int, pageHeight: CGFloat) -> Int {
        if pageHeight < 72 { return 1 }
        if sheetCount >= 5 { return 3 }
        return 2
    }

    /// Resolve Auto or an explicit 1/2/3 choice, clamped to what fits the trim height.
    static func resolvedStitchHoleCount(
        setting: StitchHoleCount,
        sheetCount: Int,
        pageHeight: CGFloat
    ) -> Int {
        let requested: Int
        switch setting {
        case .auto:
            requested = recommendedStitchHoleCount(sheetCount: sheetCount, pageHeight: pageHeight)
        case .one:
            requested = 1
        case .two:
            requested = 2
        case .three:
            requested = 3
        }
        return clampedStitchHoleCount(requested, pageHeight: pageHeight)
    }

    private static func clampedStitchHoleCount(_ requested: Int, pageHeight: CGFloat) -> Int {
        let clamped = max(1, min(3, requested))
        var effective = clamped
        while effective > 1, pageHeight < minimumTrimHeight(forStitchHoles: effective) {
            effective -= 1
        }
        return effective
    }

    private static func minimumTrimHeight(forStitchHoles count: Int) -> CGFloat {
        switch count {
        case 1: return 36
        case 2: return 72
        default: return 108
        }
    }

    /// Saddle-stitch punch positions along the fold (PDF coordinates).
    static func stitchHoleCenters(
        spineX: CGFloat,
        trimOrigin: CGPoint,
        pageSize: CGSize,
        holeCount: Int
    ) -> [CGPoint] {
        let count = clampedStitchHoleCount(holeCount, pageHeight: pageSize.height)
        let inset = min(36, pageSize.height * 0.25)
        let bottomY = trimOrigin.y + inset
        let topY = trimOrigin.y + pageSize.height - inset
        let midY = trimOrigin.y + pageSize.height / 2

        switch count {
        case 1:
            return [CGPoint(x: spineX, y: midY)]
        case 2:
            return [
                CGPoint(x: spineX, y: topY),
                CGPoint(x: spineX, y: bottomY)
            ]
        default:
            return [
                CGPoint(x: spineX, y: topY),
                CGPoint(x: spineX, y: midY),
                CGPoint(x: spineX, y: bottomY)
            ]
        }
    }

    private static func renderSheetLayoutPDF(
        bookBlock: PDFDocument,
        pageStart: Int,
        layout: SheetLayout,
        stockSize: CGSize,
        mediaSize: CGSize,
        addCropMarks: Bool,
        showGuides: Bool,
        bleed: CGFloat,
        sheetLabel: String?,
        slug: String?
    ) -> Data {
        let mutableData = NSMutableData()
        var mediaBox = CGRect(origin: .zero, size: mediaSize)
        guard let consumer = CGDataConsumer(data: mutableData as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            return Data()
        }

        let origin = CGPoint(
            x: (mediaSize.width - stockSize.width) / 2,
            y: (mediaSize.height - stockSize.height) / 2
        )
        let cellW = stockSize.width / CGFloat(max(1, layout.columns))
        let cellH = stockSize.height / CGFloat(max(1, layout.rows))

        context.beginPage(mediaBox: &mediaBox)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(mediaBox)

        for cell in layout.cells {
            guard let local = cell.pageIndex,
                  let page = bookBlock.page(at: pageStart + local) else { continue }
            let cellRect = CGRect(
                x: origin.x + CGFloat(cell.column) * cellW,
                y: origin.y + CGFloat(cell.row) * cellH,
                width: cellW,
                height: cellH
            )
            drawRotatedPage(page, in: context, dest: cellRect, rotationDegrees: cell.rotationDegrees, bleed: bleed)
        }

        if showGuides {
            drawSheetGuides(in: context, guides: layout.guides, origin: origin)
        }

        let stockRect = CGRect(origin: origin, size: stockSize)
        if addCropMarks {
            PrinterMarks.draw(in: context, trim: stockRect, bleed: bleed)
        }

        if let slug {
            PrinterMarks.drawSlug(slug, in: context, trim: stockRect, bleed: bleed)
        } else if let sheetLabel {
            context.saveGState()
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 7),
                .foregroundColor: NSColor.disabledControlTextColor
            ]
            let str = NSAttributedString(string: sheetLabel, attributes: attrs)
            let line = CTLineCreateWithAttributedString(str)
            context.textPosition = CGPoint(x: 6, y: 4)
            CTLineDraw(line, context)
            context.restoreGState()
        }

        context.endPage()
        context.closePDF()
        return mutableData as Data
    }

    private static func drawRotatedPage(
        _ page: PDFPage,
        in context: CGContext,
        dest: CGRect,
        rotationDegrees: Int,
        bleed: CGFloat
    ) {
        let rot = ((rotationDegrees % 360) + 360) % 360
        let clip = dest.insetBy(dx: -bleed, dy: -bleed)

        context.saveGState()
        context.clip(to: clip)

        if rot == 0 {
            PDFPageDrawing.draw(page, in: context, dest: dest)
            context.restoreGState()
            return
        }

        let center = CGPoint(x: dest.midX, y: dest.midY)
        context.translateBy(x: center.x, y: center.y)
        context.rotate(by: CGFloat(rot) * .pi / 180)

        let drawRect: CGRect
        if rot == 90 || rot == 270 {
            drawRect = CGRect(
                x: -dest.height / 2,
                y: -dest.width / 2,
                width: dest.height,
                height: dest.width
            )
        } else {
            drawRect = CGRect(
                x: -dest.width / 2,
                y: -dest.height / 2,
                width: dest.width,
                height: dest.height
            )
        }
        PDFPageDrawing.draw(page, in: context, dest: drawRect)
        context.restoreGState()
    }

    private static func drawSheetGuides(
        in context: CGContext,
        guides: [SheetGuideSegment],
        origin: CGPoint
    ) {
        // Print-safe grays only — these marks sit on finished pages. Color (e.g. red)
        // leaves visible residue along the slit after cutting.
        context.saveGState()
        for guide in guides {
            let start = CGPoint(x: origin.x + guide.start.x, y: origin.y + guide.start.y)
            let end = CGPoint(x: origin.x + guide.end.x, y: origin.y + guide.end.y)
            switch guide.kind {
            case .fold:
                context.setStrokeColor(CGColor(gray: 0.72, alpha: 1))
                context.setLineWidth(0.35)
                context.setLineDash(phase: 0, lengths: [3, 2.5])
            case .cut:
                context.setStrokeColor(CGColor(gray: 0.45, alpha: 1))
                context.setLineWidth(0.45)
                context.setLineDash(phase: 0, lengths: [])
            }
            context.move(to: start)
            context.addLine(to: end)
            context.strokePath()
        }
        context.restoreGState()
    }

    private static func renderSpreadPDF(
        left: PDFPage?,
        right: PDFPage?,
        pageSize: CGSize,
        bounds: CGRect,
        addCropMarks: Bool,
        showFoldLine: Bool,
        stitchHoleCount: Int,
        signatureLabel: String?,
        slug: String?,
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

        if let left {
            drawPage(
                left,
                in: context,
                trimRect: CGRect(origin: trimOrigin, size: pageSize),
                bleed: bleed,
                contentOffsetX: creepOffset
            )
        }

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

        let spreadTrim = CGRect(
            origin: trimOrigin,
            size: CGSize(width: pageSize.width * 2, height: pageSize.height)
        )
        if addCropMarks {
            // The spine is folded, never cut: fold marks there, crop marks at the outer corners.
            PrinterMarks.draw(in: context, trim: spreadTrim, bleed: bleed, foldXs: [spineX])
        }

        if stitchHoleCount > 0 {
            drawStitchHoleMarks(
                in: context,
                spineX: spineX,
                trimOrigin: trimOrigin,
                pageSize: pageSize,
                holeCount: stitchHoleCount
            )
        }

        if let slug {
            PrinterMarks.drawSlug(slug, in: context, trim: spreadTrim, bleed: bleed)
        } else if let signatureLabel {
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

    private static func drawPage(
        _ page: PDFPage,
        in context: CGContext,
        trimRect: CGRect,
        bleed: CGFloat,
        contentOffsetX: CGFloat
    ) {
        let source = page.bounds(for: .mediaBox)
        guard source.width > 0, source.height > 0 else { return }

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

    private static func drawStitchHoleMarks(
        in context: CGContext,
        spineX: CGFloat,
        trimOrigin: CGPoint,
        pageSize: CGSize,
        holeCount: Int
    ) {
        let radius: CGFloat = 2.5
        let centers = stitchHoleCenters(
            spineX: spineX,
            trimOrigin: trimOrigin,
            pageSize: pageSize,
            holeCount: holeCount
        )

        context.saveGState()
        context.setStrokeColor(CGColor(gray: 0, alpha: 1))
        context.setLineWidth(0.5)
        context.setLineDash(phase: 0, lengths: [])

        for center in centers {
            let rect = CGRect(
                x: center.x - radius,
                y: center.y - radius,
                width: radius * 2,
                height: radius * 2
            )
            context.strokeEllipse(in: rect)
        }

        context.restoreGState()
    }
}
