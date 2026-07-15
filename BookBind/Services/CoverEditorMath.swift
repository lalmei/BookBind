import AppKit
import CoreGraphics
import Foundation

enum CoverResizeHandle: String, CaseIterable, Identifiable {
    case topLeft
    case top
    case topRight
    case right
    case bottomRight
    case bottom
    case bottomLeft
    case left

    var id: String { rawValue }
}

struct CoverElementBounds: Equatable {
    var centerX: Double
    var centerY: Double
    var width: Double
    var height: Double
}

enum CoverEditorMath {
    static let minimumElementSizeMM = 4.0
    /// Canvas/export: 1 mm of `fontSizeMM` → 1 pt when scale == 1.
    static let textDisplayFactor = 1.0

    static func nsFont(for style: CoverFontStyle, sizePoints: CGFloat) -> NSFont {
        let size = max(4, sizePoints)
        switch style {
        case .display:
            return NSFont(name: "Georgia-Bold", size: size)
                ?? NSFont(name: "Times New Roman", size: size)
                ?? .systemFont(ofSize: size, weight: .semibold)
        case .subtitle:
            return NSFont(name: "Georgia", size: size)
                ?? NSFont(name: "Times New Roman", size: size)
                ?? .systemFont(ofSize: size, weight: .medium)
        case .body:
            return .systemFont(ofSize: size, weight: .regular)
        }
    }

    /// Glyph-accurate text size in millimeters (1 pt ≡ 1 mm at export scale).
    static func measuredTextSizeMM(text: String, fontSizeMM: Double, fontStyle: CoverFontStyle) -> (width: Double, height: Double) {
        let font = nsFont(for: fontStyle, sizePoints: CGFloat(max(1, fontSizeMM)))
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let size = (text as NSString).size(withAttributes: attributes)
        return (
            width: max(minimumElementSizeMM, Double(size.width)),
            height: max(minimumElementSizeMM, Double(size.height))
        )
    }

    static func displayBounds(for element: CoverDesignElement, geometry: CoverBlueprintService.Geometry) -> CoverElementBounds {
        let width: Double
        let height: Double
        switch element.kind {
        case .image, .shape:
            width = max(minimumElementSizeMM, element.widthMM)
            height = max(minimumElementSizeMM, element.heightMM)
        case .text:
            // Always size the box to glyph metrics so chrome matches rendered text
            // (ignore stale width/height from older placements).
            let measured = measuredTextSizeMM(
                text: element.text.isEmpty ? " " : element.text,
                fontSizeMM: element.fontSizeMM,
                fontStyle: element.fontStyle
            )
            width = measured.width
            height = measured.height
        }
        return CoverElementBounds(
            centerX: element.wrapCenterX(geometry: geometry),
            centerY: element.yMM,
            width: width,
            height: height
        )
    }

    static func resizedBounds(
        from bounds: CoverElementBounds,
        handle: CoverResizeHandle,
        deltaX: Double,
        deltaY: Double,
        locksAspectRatio: Bool,
        minimumSize: Double = minimumElementSizeMM
    ) -> CoverElementBounds {
        var left = bounds.centerX - bounds.width * 0.5
        var right = bounds.centerX + bounds.width * 0.5
        var top = bounds.centerY - bounds.height * 0.5
        var bottom = bounds.centerY + bounds.height * 0.5

        switch handle {
        case .topLeft:
            left += deltaX
            top += deltaY
        case .top:
            top += deltaY
        case .topRight:
            right += deltaX
            top += deltaY
        case .right:
            right += deltaX
        case .bottomRight:
            right += deltaX
            bottom += deltaY
        case .bottom:
            bottom += deltaY
        case .bottomLeft:
            left += deltaX
            bottom += deltaY
        case .left:
            left += deltaX
        }

        if right - left < minimumSize {
            if handle == .left || handle == .topLeft || handle == .bottomLeft {
                left = right - minimumSize
            } else {
                right = left + minimumSize
            }
        }
        if bottom - top < minimumSize {
            if handle == .top || handle == .topLeft || handle == .topRight {
                top = bottom - minimumSize
            } else {
                bottom = top + minimumSize
            }
        }

        if locksAspectRatio, bounds.width > 0, bounds.height > 0 {
            let aspect = bounds.width / bounds.height
            var width = right - left
            var height = bottom - top
            if width / max(height, 0.001) > aspect {
                width = height * aspect
            } else {
                height = width / aspect
            }

            switch handle {
            case .topLeft:
                left = right - width
                top = bottom - height
            case .topRight:
                right = left + width
                top = bottom - height
            case .bottomRight:
                right = left + width
                bottom = top + height
            case .bottomLeft:
                left = right - width
                bottom = top + height
            default:
                let cx = (left + right) * 0.5
                let cy = (top + bottom) * 0.5
                left = cx - width * 0.5
                right = cx + width * 0.5
                top = cy - height * 0.5
                bottom = cy + height * 0.5
            }
        }

        return CoverElementBounds(
            centerX: (left + right) * 0.5,
            centerY: (top + bottom) * 0.5,
            width: max(minimumSize, right - left),
            height: max(minimumSize, bottom - top)
        )
    }

    /// Angle in degrees from bounds center to a point in the unrotated local chrome space.
    static func pointerAngleDegrees(localX: Double, localY: Double, width: Double, height: Double) -> Double {
        let dx = localX - width * 0.5
        let dy = localY - height * 0.5
        return atan2(dy, dx) * 180.0 / .pi
    }

    /// New absolute rotation while dragging the rotation handle.
    static func rotationDegrees(
        pointerAngle: Double,
        gestureStartPointerAngle: Double,
        elementStartRotation: Double
    ) -> Double {
        var delta = pointerAngle - gestureStartPointerAngle
        while delta > 180 { delta -= 360 }
        while delta < -180 { delta += 360 }
        var result = elementStartRotation + delta
        while result > 180 { result -= 360 }
        while result < -180 { result += 360 }
        return result
    }

    static func zoomFactor(afterScrollDelta delta: CGFloat, current: Double) -> Double {
        let multiplier = exp(Double(delta) * 0.01)
        return min(8, max(0.25, current * multiplier))
    }

    /// Physical sanity floor for board edits. The imposition-derived bound is
    /// soft: values below it are allowed but flagged via `measurementWarnings`.
    static let hardMinimumBoardSizeMM = 40.0
    /// Smallest usable spine midsection when overriding manually.
    static let hardMinimumSpineWidthMM = 4.0

    static func boardSize(current: Double, proposed: Double) -> Double {
        guard proposed.isFinite else { return current }
        return max(hardMinimumBoardSizeMM, proposed)
    }

    /// Normalize a manual spine width entry; zero/invalid clears the override.
    static func spineWidthOverride(proposed: Double) -> Double? {
        guard proposed.isFinite, proposed > 0 else { return nil }
        return max(hardMinimumSpineWidthMM, proposed)
    }

    /// Subtle notes for the Measurements panel when a region is set below its
    /// recommended bound (imposition trim for boards, book block for the spine).
    static func measurementWarnings(
        boardWidthMM: Double,
        boardHeightMM: Double,
        minimumBoardWidthMM: Double,
        minimumBoardHeightMM: Double,
        spineWidthMM: Double,
        requiredSpineWidthMM: Double
    ) -> [String] {
        let tolerance = 0.05
        var warnings: [String] = []
        if boardWidthMM + tolerance < minimumBoardWidthMM {
            warnings.append(String(
                format: "Cover width %.1f mm is below the %.1f mm imposition trim — pages will overhang.",
                boardWidthMM, minimumBoardWidthMM
            ))
        }
        if boardHeightMM + tolerance < minimumBoardHeightMM {
            warnings.append(String(
                format: "Cover height %.1f mm is below the %.1f mm imposition trim — pages will overhang.",
                boardHeightMM, minimumBoardHeightMM
            ))
        }
        if spineWidthMM + tolerance < requiredSpineWidthMM {
            warnings.append(String(
                format: "Spine %.1f mm is narrower than the %.1f mm the book block needs.",
                spineWidthMM, requiredSpineWidthMM
            ))
        }
        return warnings
    }
}
