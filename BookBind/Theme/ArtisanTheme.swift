import AppKit
import SwiftUI

/// Digital paper tokens for BookBind's bindery workbench.
enum ArtisanTheme {
    static let surface = Color(red: 0.976, green: 0.976, blue: 1.0) // #f9f9ff
    static let surfaceBright = Color(hex: 0xf9f9ff)
    static let surfaceContainerLowest = Color(hex: 0xffffff)
    static let surfaceContainerLow = Color(hex: 0xf0f3ff)
    static let surfaceContainer = Color(hex: 0xe7eeff)
    static let surfaceContainerHigh = Color(hex: 0xdee8ff)
    static let surfaceVariant = Color(hex: 0xd8e3fa)
    static let primary = Color(hex: 0x002045)
    static let primaryContainer = Color(hex: 0x1a365d)
    static let primaryFixed = Color(hex: 0xd6e3ff)
    static let secondary = Color(hex: 0x735c00)
    static let secondaryContainer = Color(hex: 0xfed65b)
    static let tertiary = Color(hex: 0x20211c)
    static let tertiaryFixed = Color(hex: 0xe4e3db)
    static let onSurface = Color(hex: 0x111c2c)
    static let onSurfaceVariant = Color(hex: 0x43474e)
    static let outline = Color(hex: 0x74777f)
    static let outlineVariant = Color(hex: 0xc4c6cf)
    static let note = Color(red: 0.55, green: 0.45, blue: 0.28)
    static let rule = Color.primary.opacity(0.08)

    static let gutter: CGFloat = 24
    static let marginDesktop: CGFloat = 48
    static let cardRadius: CGFloat = 26
    static let controlRadius: CGFloat = 10

    static var displayFont: Font {
        serif(size: 48, relativeTo: .largeTitle)
    }

    static var displayFontCompact: Font {
        serif(size: 36, relativeTo: .largeTitle)
    }

    static var sectionFont: Font {
        serif(size: 24, relativeTo: .title2)
    }

    static var cardTitleFont: Font {
        serif(size: 21, relativeTo: .title3)
    }

    static var bodyFont: Font {
        .system(size: 16, weight: .regular, design: .default)
    }

    static var bodyLargeFont: Font {
        .system(size: 18, weight: .regular, design: .default)
    }

    static var buttonFont: Font {
        .system(size: 14, weight: .semibold, design: .default)
    }

    static var labelFont: Font {
        .system(size: 11, weight: .medium, design: .monospaced)
    }

    static var technicalFont: Font {
        .system(.body, design: .monospaced)
    }

    static var technicalCaption: Font {
        .system(.caption, design: .monospaced)
    }

    static func cardShadow(color: Color = primary.opacity(0.08), radius: CGFloat = 26) -> some ViewModifier {
        ShadowModifier(color: color, radius: radius)
    }

    /// Prefer EB Garamond when installed; otherwise macOS New York / serif.
    private static func serif(size: CGFloat, relativeTo textStyle: Font.TextStyle) -> Font {
        let candidates = ["EB Garamond", "EBGaramond-Regular", "Iowan Old Style"]
        for name in candidates {
            if NSFont(name: name, size: size) != nil {
                return .custom(name, size: size, relativeTo: textStyle)
            }
        }
        return .system(textStyle, design: .serif)
    }
}

private struct ShadowModifier: ViewModifier {
    let color: Color
    let radius: CGFloat

    func body(content: Content) -> some View {
        content.shadow(color: color, radius: radius, x: 0, y: 12)
    }
}

extension View {
    /// Keeps `minWidth` layout room and scrolls horizontally when the parent is narrower.
    /// Use around split workbenches so sidebar/inspector columns are not clipped.
    func horizontallyScrollable(minWidth: CGFloat) -> some View {
        HorizontalOverflowScroll(minWidth: minWidth) { self }
    }
}

private struct HorizontalOverflowScroll<Content: View>: View {
    let minWidth: CGFloat
    @ViewBuilder let content: () -> Content

    var body: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, minWidth)
            ScrollView(.horizontal, showsIndicators: geo.size.width + 0.5 < minWidth) {
                content()
                    .frame(width: width, height: geo.size.height, alignment: .topLeading)
            }
        }
    }
}

private extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xff) / 255.0,
            green: Double((hex >> 8) & 0xff) / 255.0,
            blue: Double(hex & 0xff) / 255.0
        )
    }
}
