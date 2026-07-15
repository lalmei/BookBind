import AppKit
import CoreGraphics
import Foundation
import SwiftUI

/// RGBA color persisted with cover / endpaper designs.
struct CodableColor: Equatable, Hashable, Codable {
    var red: Double
    var green: Double
    var blue: Double
    var opacity: Double

    init(red: Double, green: Double, blue: Double, opacity: Double = 1) {
        self.red = min(1, max(0, red))
        self.green = min(1, max(0, green))
        self.blue = min(1, max(0, blue))
        self.opacity = min(1, max(0, opacity))
    }

    init(nsColor: NSColor) {
        let rgb = nsColor.usingColorSpace(.sRGB) ?? nsColor
        self.init(
            red: Double(rgb.redComponent),
            green: Double(rgb.greenComponent),
            blue: Double(rgb.blueComponent),
            opacity: Double(rgb.alphaComponent)
        )
    }

    init(color: Color) {
        self.init(nsColor: NSColor(color))
    }

    init(cgColor: CGColor) {
        let comps = cgColor.components ?? [0, 0, 0, 1]
        if comps.count >= 4 {
            self.init(red: Double(comps[0]), green: Double(comps[1]), blue: Double(comps[2]), opacity: Double(comps[3]))
        } else if comps.count >= 2 {
            self.init(red: Double(comps[0]), green: Double(comps[0]), blue: Double(comps[0]), opacity: Double(comps[1]))
        } else {
            self.init(red: 0, green: 0, blue: 0, opacity: 1)
        }
    }

    var color: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: opacity)
    }

    var cgColor: CGColor {
        CGColor(srgbRed: red, green: green, blue: blue, alpha: opacity)
    }

    var nsColor: NSColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: opacity)
    }

    static let paperIvory = CodableColor(red: 0.96, green: 0.94, blue: 0.86)
    static let inkBlack = CodableColor(red: 0.12, green: 0.12, blue: 0.14)
    static let foilGold = CodableColor(red: 0.45, green: 0.36, blue: 0.0)
    static let debossGray = CodableColor(red: 0.35, green: 0.35, blue: 0.38)

    /// Default solid fill / stroke tint for a cover finish channel.
    static func finishDefault(for layer: CoverElementLayer) -> CodableColor {
        switch layer {
        case .ink: return .inkBlack
        case .foil: return .foilGold
        case .deboss: return .debossGray
        }
    }
}

/// Extensible paint for shape fills (and future gradients / patterns).
enum CoverPaint: Equatable, Hashable, Codable {
    case none
    case solid(CodableColor)

    var isFilled: Bool {
        if case .none = self { return false }
        return true
    }

    var solidColor: CodableColor? {
        if case let .solid(color) = self { return color }
        return nil
    }
}
