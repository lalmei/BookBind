import AppKit
import SwiftUI

/// Design tokens for InABind.
///
/// Surfaces are **semantic system colors**, so pages, canvases, and inspectors match the
/// sidebar and toolbar macOS draws. The brand lives in two accents (ink blue, foil gold)
/// and the serif display type — never in background fills.
enum ArtisanTheme {
    // MARK: Surfaces (back to front)

    /// Recessed backdrop behind artboards, sheets, and the 3D book.
    static let canvasBackground = Color(nsColor: canvasNSColor)
    /// Page background for Home, Calculators, Guides, Libraries, Materials — matches the inspector.
    static let contentBackground = Color(nsColor: .textBackgroundColor)
    /// Grouped container on a content page (project rows, cards, calculator panels).
    static let cardBackground = Color.primary.opacity(0.045)
    /// Raised control or chip inside a card (segmented pickers, badges).
    static let raisedFill = Color.primary.opacity(0.09)
    /// Hairlines and card borders.
    static let separator = Color(nsColor: .separatorColor)

    /// AppKit form of `canvasBackground` for SceneKit and other NSView hosts.
    static var canvasNSColor: NSColor { .underPageBackgroundColor }

    // MARK: Text

    static let textPrimary = Color(nsColor: .labelColor)
    static let textSecondary = Color(nsColor: .secondaryLabelColor)
    static let textTertiary = Color(nsColor: .tertiaryLabelColor)

    // MARK: Brand accents

    /// Ink blue: titles, selection tint, brand mark.
    static let primary = Color(hex: 0xc5d7f5)
    /// Foil gold: the one call-to-action and stamp/foil highlights.
    static let secondary = Color(hex: 0xf0c94b)
    /// Text drawn on top of `secondary`.
    static let onSecondary = Color(hex: 0x1a1608)
    static let note = Color(red: 0.78, green: 0.68, blue: 0.42)

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

    static func cardShadow(color: Color = Color.black.opacity(0.35), radius: CGFloat = 26) -> some ViewModifier {
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

/// Page-level section label for content pages (Home, Libraries): a short rule and
/// tracked small caps. Inspectors use `WorkbenchInspectorChrome.SectionTitle` instead.
struct ContentSectionTitle: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        HStack(spacing: 14) {
            Rectangle()
                .fill(ArtisanTheme.separator.opacity(0.35))
                .frame(width: 32, height: 1)
            Text(title.uppercased())
                .font(ArtisanTheme.labelFont)
                .tracking(2.2)
                .foregroundStyle(ArtisanTheme.textSecondary.opacity(0.46))
        }
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
