import Foundation

/// Creation / selection tools shared by design canvases.
enum DesignCanvasTool: String, CaseIterable, Identifiable {
    case select
    case text
    case image
    case rectangle
    case ellipse
    case line

    var id: String { rawValue }

    var title: String {
        switch self {
        case .select: return "Select"
        case .text: return "Text"
        case .image: return "Image"
        case .rectangle: return "Rectangle"
        case .ellipse: return "Ellipse"
        case .line: return "Line"
        }
    }

    var systemImage: String {
        switch self {
        case .select: return "cursorarrow"
        case .text: return "character.cursor.ibeam"
        case .image: return "photo.on.rectangle"
        case .rectangle: return CoverShapeType.rectangle.systemImage
        case .ellipse: return CoverShapeType.ellipse.systemImage
        case .line: return CoverShapeType.line.systemImage
        }
    }

    /// Shape that will be created next; `nil` for non-shape tools.
    var shapeType: CoverShapeType? {
        switch self {
        case .rectangle: return .rectangle
        case .ellipse: return .ellipse
        case .line: return .line
        case .select, .text, .image: return nil
        }
    }
}
