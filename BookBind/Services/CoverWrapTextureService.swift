import AppKit
import CoreGraphics
import Foundation

/// Face textures for the 3D book preview (outer wrap + endpaper peeks).
struct BookPreviewTextures {
    let frontOuter: NSImage
    let backOuter: NSImage
    let spineOuter: NSImage
    let frontInner: NSImage
    let backInner: NSImage
    let frontFlyleaf: NSImage
    let backFlyleaf: NSImage
}

enum CoverWrapTextureService {
    /// Build sliced wrap + endpaper textures for SceneKit materials.
    static func makeTextures(
        project: BinderyProject,
        dimensions: PhysicalBookDimensions,
        dpi: CGFloat = 150
    ) -> BookPreviewTextures {
        let geo = CoverBlueprintService.Geometry(
            project: project,
            spineWidthMM: dimensions.spineWidthMM
        )
        let wrap = CoverBlueprintService.renderWrapImage(
            for: project,
            spineWidthMM: dimensions.spineWidthMM,
            dpi: dpi
        ) ?? solidImage(
            color: NSColor(white: 0.94, alpha: 1),
            widthMM: geo.totalW,
            heightMM: geo.boardH,
            dpi: dpi
        )

        let frontOuter = cropPanel(.front, from: wrap, geometry: geo) ?? wrap
        let backOuter = cropPanel(.back, from: wrap, geometry: geo) ?? wrap
        let spineOuter = cropSpineBand(from: wrap, geometry: geo) ?? wrap

        let endsheetGeo = EndsheetGeometry.resolving(project: project, trimPoints: nil)
        let (frontFace, backFace) = mirroredEndsheetFaces(project.endsheets)

        // A real endpaper is ONE sheet folded at the spine: the pastedown and the
        // free flyleaf are the two continuous halves of that sheet. Render the full
        // folded sheet once per face, then crop each half onto its own surface — so
        // the pastedown and flyleaf show different (but continuous) parts of the
        // marble instead of the identical bitmap on both.
        let frontSheet = sheetImage(face: frontFace, geometry: endsheetGeo, dpi: dpi)
        let backSheet = sheetImage(face: backFace, geometry: endsheetGeo, dpi: dpi)

        let frontPastedown = leafHalf(frontSheet, zone: .pastedown, isFront: true, geometry: endsheetGeo)
        let frontFly = leafHalf(frontSheet, zone: .flyleaf, isFront: true, geometry: endsheetGeo)
        let backPastedown = leafHalf(backSheet, zone: .pastedown, isFront: false, geometry: endsheetGeo)
        let backFly = leafHalf(backSheet, zone: .flyleaf, isFront: false, geometry: endsheetGeo)

        let boardFallback = solidImage(
            color: NSColor(red: 0.97, green: 0.95, blue: 0.90, alpha: 1),
            widthMM: dimensions.boardWidthMM,
            heightMM: dimensions.boardHeightMM,
            dpi: dpi
        )

        // The pastedown does not reach the board edge — the covering-material
        // turn-in shows as a reveal border on the inside of each board.
        let revealMM = project.architecture.wrapsTurnIn ? max(0, project.pastedownInsetMM) : 0
        let frontInner = insetPastedown(
            frontPastedown,
            boardWidthMM: dimensions.boardWidthMM,
            boardHeightMM: dimensions.boardHeightMM,
            insetMM: revealMM,
            material: project.coverMaterial,
            dpi: dpi
        )
        let backInner = insetPastedown(
            backPastedown,
            boardWidthMM: dimensions.boardWidthMM,
            boardHeightMM: dimensions.boardHeightMM,
            insetMM: revealMM,
            material: project.coverMaterial,
            dpi: dpi
        )

        return BookPreviewTextures(
            frontOuter: frontOuter,
            backOuter: backOuter,
            spineOuter: spineOuter,
            frontInner: frontInner ?? boardFallback,
            backInner: backInner ?? boardFallback,
            frontFlyleaf: frontFly ?? boardFallback,
            backFlyleaf: backFly ?? boardFallback
        )
    }

    /// Compose a board inner-face texture: covering-material turn-in fills the whole
    /// board face, with the pastedown centered and inset by `insetMM` (the reveal).
    static func insetPastedown(
        _ pastedown: NSImage?,
        boardWidthMM: Double,
        boardHeightMM: Double,
        insetMM: Double,
        material: CoverMaterial,
        dpi: CGFloat
    ) -> NSImage? {
        guard let pastedown else { return nil }
        guard insetMM > 0.05, boardWidthMM > 0, boardHeightMM > 0 else { return pastedown }

        let pixelsPerMM = Double(dpi) / 25.4
        let w = max(2, Int(ceil(boardWidthMM * pixelsPerMM)))
        let h = max(2, Int(ceil(boardHeightMM * pixelsPerMM)))
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let leaf = cgImage(from: pastedown) else {
            return pastedown
        }

        // Turn-in reveal border = covering material.
        ctx.setFillColor(CoverBlueprintService.materialBaseFill(material).cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))

        let insetPx = insetMM * pixelsPerMM
        let leafRect = CGRect(x: 0, y: 0, width: Double(w), height: Double(h))
            .insetBy(dx: min(Double(w) / 2 - 1, insetPx), dy: min(Double(h) / 2 - 1, insetPx))
        ctx.draw(leaf, in: leafRect)

        guard let cg = ctx.makeImage() else { return pastedown }
        return NSImage(cgImage: cg, size: NSSize(width: w, height: h))
    }

    /// Prefer a decorated face when the opposite endsheet is still blank.
    static func mirroredEndsheetFaces(_ design: EndpaperDesign) -> (front: EndpaperFaceDesign, back: EndpaperFaceDesign) {
        let frontDecorated = isDecorated(design.front)
        let backDecorated = isDecorated(design.back)
        if frontDecorated && !backDecorated {
            return (design.front, design.front)
        }
        if backDecorated && !frontDecorated {
            return (design.back, design.back)
        }
        return (design.front, design.back)
    }

    private static func isDecorated(_ face: EndpaperFaceDesign) -> Bool {
        switch face.mode {
        case .blank:
            return false
        case .solidColor:
            return face.solidColor != .none
        case .marbled:
            return face.marbling != nil
        case .artwork:
            return face.artwork != nil
        }
    }

    /// Full folded endsheet (two leaves wide) for a single face.
    private static func sheetImage(
        face: EndpaperFaceDesign,
        geometry: EndsheetGeometry,
        dpi: CGFloat
    ) -> NSImage? {
        EndsheetRenderService.nsImage(
            face: face,
            sheetSizePoints: geometry.sheetSizePoints,
            dpi: dpi
        )
    }

    /// Crop the leaf occupied by `zone` out of the folded sheet. The pastedown and
    /// flyleaf are continuous halves of the same sheet, so this yields matching but
    /// distinct textures rather than the same bitmap twice.
    private static func leafHalf(
        _ sheet: NSImage?,
        zone: EndsheetZone,
        isFront: Bool,
        geometry: EndsheetGeometry
    ) -> NSImage? {
        guard let sheet else { return nil }
        let isLeftHalf = geometry.zoneOriginX(zone, isFront: isFront) < geometry.leafW * 0.5
        return cropHalf(sheet, leftHalf: isLeftHalf)
    }

    private static func cropHalf(_ image: NSImage, leftHalf: Bool) -> NSImage? {
        guard let cg = cgImage(from: image) else { return image }
        let fullW = cg.width
        let halfW = max(1, fullW / 2)
        let x = leftHalf ? 0 : halfW
        let w = leftHalf ? halfW : max(1, fullW - halfW)
        guard let cropped = cg.cropping(to: CGRect(x: x, y: 0, width: w, height: cg.height)) else {
            return image
        }
        return NSImage(cgImage: cropped, size: NSSize(width: cropped.width, height: cropped.height))
    }

    // MARK: - Wrap cropping

    private static func cropPanel(
        _ panel: CoverPanel,
        from wrap: NSImage,
        geometry: CoverBlueprintService.Geometry
    ) -> NSImage? {
        guard geometry.panelWidth(panel) > 0.05 else { return nil }
        return crop(
            wrap,
            xMM: geometry.panelOriginX(panel),
            widthMM: geometry.panelWidth(panel),
            totalWidthMM: geometry.totalW
        )
    }

    private static func cropSpineBand(
        from wrap: NSImage,
        geometry: CoverBlueprintService.Geometry
    ) -> NSImage? {
        crop(
            wrap,
            xMM: geometry.boardW,
            widthMM: geometry.midsection,
            totalWidthMM: geometry.totalW
        )
    }

    private static func crop(
        _ image: NSImage,
        xMM: Double,
        widthMM: Double,
        totalWidthMM: Double
    ) -> NSImage? {
        guard let cg = cgImage(from: image),
              totalWidthMM > 0, widthMM > 0 else { return nil }

        let pxPerMMX = Double(cg.width) / totalWidthMM
        let x = Int(floor(xMM * pxPerMMX))
        let w = max(1, Int(ceil(widthMM * pxPerMMX)))
        let clampedW = min(w, cg.width - x)
        guard x >= 0, clampedW > 0 else { return nil }

        let rect = CGRect(x: x, y: 0, width: clampedW, height: cg.height)
        guard let cropped = cg.cropping(to: rect) else { return nil }
        return NSImage(cgImage: cropped, size: NSSize(width: cropped.width, height: cropped.height))
    }

    private static func cgImage(from image: NSImage) -> CGImage? {
        var rect = CGRect(origin: .zero, size: image.size)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
            ?? image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }

    private static func solidImage(
        color: NSColor,
        widthMM: Double,
        heightMM: Double,
        dpi: CGFloat
    ) -> NSImage {
        let pixelsPerMM = dpi / 25.4
        let w = max(2, Int(ceil(widthMM * Double(pixelsPerMM))))
        let h = max(2, Int(ceil(heightMM * Double(pixelsPerMM))))
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return NSImage(size: NSSize(width: w, height: h))
        }
        ctx.setFillColor(color.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        guard let cg = ctx.makeImage() else {
            return NSImage(size: NSSize(width: w, height: h))
        }
        return NSImage(cgImage: cg, size: NSSize(width: w, height: h))
    }
}
