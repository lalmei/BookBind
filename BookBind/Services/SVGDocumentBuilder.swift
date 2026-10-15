import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Shared SVG string helpers for cover and endsheet exports.
enum SVGDocumentBuilder {
    enum ExportMode: String, CaseIterable, Identifiable {
        case production
        case clean

        var id: String { rawValue }

        var title: String {
            switch self {
            case .production: return "Production SVG (with guides)"
            case .clean: return "Clean artwork SVG"
            }
        }

        var includesGuides: Bool { self == .production }
    }

    static func fmt(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    static func escape(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    static func hex(_ color: CodableColor) -> String {
        let r = Int((color.red * 255).rounded())
        let g = Int((color.green * 255).rounded())
        let b = Int((color.blue * 255).rounded())
        return String(format: "#%02x%02x%02x", r, g, b)
    }

    static func hex(cgColor: CGColor) -> String {
        hex(CodableColor(cgColor: cgColor))
    }

    static func rootOpen(
        widthMM: Double,
        heightMM: Double,
        title: String,
        desc: String? = nil
    ) -> String {
        var svg = """
        <?xml version="1.0" encoding="UTF-8"?>
        <svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="\(fmt(widthMM))mm" height="\(fmt(heightMM))mm" viewBox="0 0 \(fmt(widthMM)) \(fmt(heightMM))">
          <title>\(escape(title))</title>
        """
        if let desc {
            svg += "\n  <desc>\(escape(desc))</desc>\n"
        }
        return svg
    }

    static let rootClose = "</svg>\n"

    /// Production guide group wrapper — clean export omits these entirely.
    static func guideGroup(id: String, content: String) -> String {
        guard !content.isEmpty else { return "" }
        return """
        <g id="\(escape(id))" data-production-guide="true">
        \(content)</g>
        """
    }

    static func line(
        x1: Double, y1: Double, x2: Double, y2: Double,
        stroke: String,
        width: Double = 0.35,
        dash: String? = nil,
        opacity: Double = 1
    ) -> String {
        var attrs = """
        x1="\(fmt(x1))" y1="\(fmt(y1))" x2="\(fmt(x2))" y2="\(fmt(y2))" stroke="\(stroke)" stroke-width="\(fmt(width))" fill="none" opacity="\(fmt(opacity))"
        """
        if let dash {
            attrs += " stroke-dasharray=\"\(dash)\""
        }
        return "<line \(attrs)/>\n"
    }

    static func rect(
        x: Double, y: Double, w: Double, h: Double,
        fill: String? = nil,
        stroke: String? = nil,
        strokeWidth: Double = 0.35,
        dash: String? = nil,
        opacity: Double = 1
    ) -> String {
        var attrs = "x=\"\(fmt(x))\" y=\"\(fmt(y))\" width=\"\(fmt(w))\" height=\"\(fmt(h))\" opacity=\"\(fmt(opacity))\""
        attrs += " fill=\"\(fill ?? "none")\""
        if let stroke {
            attrs += " stroke=\"\(stroke)\" stroke-width=\"\(fmt(strokeWidth))\""
            if let dash {
                attrs += " stroke-dasharray=\"\(dash)\""
            }
        }
        return "<rect \(attrs)/>\n"
    }

    /// Embed a marbling fill as a regeneratable raster with seed metadata.
    static func marbledImageElement(
        spec: MarbledPaperSpec,
        x: Double,
        y: Double,
        width: Double,
        height: Double,
        dpi: CGFloat = 150
    ) -> String {
        guard let cg = MarbledPaperGenerator.render(
            spec: spec,
            width: max(8, Int(ceil(width * dpi / 25.4))),
            height: max(8, Int(ceil(height * dpi / 25.4)))
        ) else {
            return rect(x: x, y: y, w: width, h: height, fill: "#f7f4ec", stroke: "#c8c8c8")
        }
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            data as CFMutableData,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            return rect(x: x, y: y, w: width, h: height, fill: "#f7f4ec", stroke: "#c8c8c8")
        }
        CGImageDestinationAddImage(dest, cg, nil)
        guard CGImageDestinationFinalize(dest) else {
            return rect(x: x, y: y, w: width, h: height, fill: "#f7f4ec", stroke: "#c8c8c8")
        }
        let b64 = (data as Data).base64EncodedString()
        return """
        <image x="\(fmt(x))" y="\(fmt(y))" width="\(fmt(width))" height="\(fmt(height))" preserveAspectRatio="none" xlink:href="data:image/png;base64,\(b64)" data-marbling-seed="\(spec.seed)" data-marbling-style="\(escape(spec.style.rawValue))" data-regeneratable="true"/>
        """
    }
}
