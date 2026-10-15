import CoreGraphics
import Foundation

/// Single non-displacing ink deposit used inside a scatter session (one undo unit).
struct MarblingInkDeposit: Equatable, Hashable, Codable {
    var x: Double
    var y: Double
    var radius: Double
    var color: CodableColor

    var center: CGPoint { CGPoint(x: x, y: y) }

    init(x: Double, y: Double, radius: Double, color: CodableColor) {
        self.x = x
        self.y = y
        self.radius = radius
        self.color = color
    }

    init(center: CGPoint, radius: Double, color: CodableColor) {
        self.init(x: center.x, y: center.y, radius: radius, color: color)
    }
}

/// Marblizer-compatible marbling operation. Coordinates are in logical canvas
/// space (`MarbledPaperGenerator.logicalWidth` × aspect height).
enum MarblingOperation: Equatable, Hashable, Codable {
    /// Disc of ink; when `displacing` is true, pushes existing field outward.
    case inkDrop(x: Double, y: Double, radius: Double, color: CodableColor, displacing: Bool)
    /// Batch of non-displacing spatters — one history entry for undo.
    case scatter(drops: [MarblingInkDeposit])
    /// Straight comb rake. `dirX/dirY` encode direction and drag strength (length).
    case lineTine(
        originX: Double,
        originY: Double,
        dirX: Double,
        dirY: Double,
        numTines: Double,
        spacing: Double,
        reach: Double
    )
    /// Wavy comb rake.
    case wavyTine(
        originX: Double,
        originY: Double,
        dirX: Double,
        dirY: Double,
        numTines: Double,
        spacing: Double,
        reach: Double
    )
    /// Concentric circular rake.
    case circularTine(
        centerX: Double,
        centerY: Double,
        radius: Double,
        numTines: Double,
        interval: Double,
        counterClockwise: Bool
    )
    /// Spiral swirl around a point.
    case vortex(centerX: Double, centerY: Double, radius: Double, counterClockwise: Bool)
    /// Changes the bath / paper base color.
    case changeBaseColor(CodableColor)

    // MARK: - Convenience constructors (Swift port of Marblizer JS API)

    static func inkDrop(
        position: CGPoint,
        radius: Double,
        color: CodableColor,
        displacing: Bool = true
    ) -> MarblingOperation {
        .inkDrop(x: position.x, y: position.y, radius: radius, color: color, displacing: displacing)
    }

    static func lineTine(
        origin: CGPoint,
        direction: CGVector,
        numTines: Double,
        spacing: Double,
        reach: Double = 4000
    ) -> MarblingOperation {
        .lineTine(
            originX: origin.x,
            originY: origin.y,
            dirX: direction.dx,
            dirY: direction.dy,
            numTines: numTines,
            spacing: spacing,
            reach: reach
        )
    }

    static func wavyTine(
        origin: CGPoint,
        direction: CGVector,
        numTines: Double,
        spacing: Double,
        reach: Double = 4000
    ) -> MarblingOperation {
        .wavyTine(
            originX: origin.x,
            originY: origin.y,
            dirX: direction.dx,
            dirY: direction.dy,
            numTines: numTines,
            spacing: spacing,
            reach: reach
        )
    }

    static func circularTine(
        origin: CGPoint,
        radius: Double,
        numTines: Double,
        interval: Double,
        counterClockwise: Bool = false
    ) -> MarblingOperation {
        .circularTine(
            centerX: origin.x,
            centerY: origin.y,
            radius: radius,
            numTines: numTines,
            interval: interval,
            counterClockwise: counterClockwise
        )
    }

    static func vortex(
        origin: CGPoint,
        radius: Double,
        counterClockwise: Bool = false
    ) -> MarblingOperation {
        .vortex(
            centerX: origin.x,
            centerY: origin.y,
            radius: radius,
            counterClockwise: counterClockwise
        )
    }

    /// Marblizer rule: drag into the upper half (negative Y) spins counterclockwise.
    static func counterclockwiseForDrag(direction: CGVector) -> Bool {
        direction.dy < 0
    }
}

/// Canvas tools matching Marblizer’s palette.
enum MarblingTool: String, CaseIterable, Identifiable, Hashable {
    case drop
    case spatter
    case lineTine
    case wavyTine
    case circularTine
    case vortex

    var id: String { rawValue }

    var title: String {
        switch self {
        case .drop: return "Ink drop"
        case .spatter: return "Spatter"
        case .lineTine: return "Tine line"
        case .wavyTine: return "Wavy tine"
        case .circularTine: return "Circular tine"
        case .vortex: return "Vortex"
        }
    }

    var shortcut: String {
        switch self {
        case .drop: return "D"
        case .spatter: return "X"
        case .lineTine: return "L"
        case .wavyTine: return "W"
        case .circularTine: return "C"
        case .vortex: return "V"
        }
    }

    var systemImage: String {
        switch self {
        case .drop: return "circle.fill"
        case .spatter: return "sparkles"
        case .lineTine: return "line.diagonal"
        case .wavyTine: return "water.waves"
        case .circularTine: return "circle.dashed"
        case .vortex: return "tornado"
        }
    }

    var help: String {
        switch self {
        case .drop:
            return "Click to drop ink. Hold Shift to lay ink without displacing."
        case .spatter:
            return "Press and drag to fling a scatter of small droplets."
        case .lineTine:
            return "Drag to rake a straight comb through the ink."
        case .wavyTine:
            return "Drag to rake a wavy comb for a rippled pattern."
        case .circularTine:
            return "Drag from a center to rake around a circle. Drag above/below for spin direction."
        case .vortex:
            return "Drag to swirl ink into a spiral. Drag above/below for spin direction."
        }
    }
}

/// Adjustable parameters for the active marbling tool (Marblizer defaults).
struct MarblingToolParameters: Equatable {
    var dropRadius: Double = 50
    var scatterRadius: Double = 100
    var spatterDropRadius: Double = 10
    var spatterCount: Int = 100
    var spatterVariability: Double = 20
    var tineSpacing: Double = 200
    var numTines: Double = 1
    var reach: Double = 4000
    var wavySpacing: Double = 200
    var wavyNumTines: Double = 1
    var wavyReach: Double = 4000
    var circularSpacing: Double = 200
    var circularNumTines: Double = 1

    func primaryValue(for tool: MarblingTool) -> Double {
        switch tool {
        case .drop: return dropRadius
        case .spatter: return scatterRadius
        case .lineTine: return tineSpacing
        case .wavyTine: return wavySpacing
        case .circularTine: return circularSpacing
        case .vortex: return 0
        }
    }

    mutating func adjustPrimary(for tool: MarblingTool, delta: Double) {
        switch tool {
        case .drop:
            dropRadius = clamp(dropRadius + delta, 5, 300)
        case .spatter:
            scatterRadius = clamp(scatterRadius + delta, 20, 300)
        case .lineTine:
            tineSpacing = clamp(tineSpacing + delta, 5, 300)
        case .wavyTine:
            wavySpacing = clamp(wavySpacing + delta, 5, 300)
        case .circularTine:
            circularSpacing = clamp(circularSpacing + delta, 5, 300)
        case .vortex:
            break
        }
    }

    mutating func adjustSecondary(for tool: MarblingTool, delta: Double) {
        switch tool {
        case .spatter:
            spatterDropRadius = clamp(spatterDropRadius + delta, 5, 40)
        case .lineTine:
            numTines = clamp(numTines + delta, 0, 20)
        case .wavyTine:
            wavyNumTines = clamp(wavyNumTines + delta, 0, 20)
        case .circularTine:
            circularNumTines = clamp(circularNumTines + delta, 0, 20)
        case .drop, .vortex:
            break
        }
    }

    private func clamp(_ value: Double, _ minV: Double, _ maxV: Double) -> Double {
        min(maxV, max(minV, value))
    }
}
