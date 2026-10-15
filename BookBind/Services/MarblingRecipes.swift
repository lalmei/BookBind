import CoreGraphics
import Foundation

/// Context supplied to Swift marbling recipes (port of Marblizer’s JS `this`).
struct MarblingRecipeContext {
    var canvasWidth: Double
    var canvasHeight: Double
    var history: [MarblingOperation]
    var foregroundColor: CodableColor
    var backgroundColor: CodableColor
    var colorAt: (CGPoint) -> CodableColor?
    var colorsAt: ([CGPoint]) -> [CodableColor?]

    var canvasSize: CGSize {
        CGSize(width: canvasWidth, height: canvasHeight)
    }
}

typealias MarblingRecipeBody = (MarblingRecipeContext) -> [MarblingOperation]

/// Built-in Swift recipes — ports of Marblizer example scripts plus style generators.
struct MarblingRecipe: Identifiable, Hashable {
    let id: String
    let title: String
    let description: String
    let replacesHistory: Bool
    private let body: MarblingRecipeBody

    init(
        id: String,
        title: String,
        description: String,
        replacesHistory: Bool = true,
        body: @escaping MarblingRecipeBody
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.replacesHistory = replacesHistory
        self.body = body
    }

    func run(_ context: MarblingRecipeContext) -> [MarblingOperation] {
        body(context)
    }

    static func == (lhs: MarblingRecipe, rhs: MarblingRecipe) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    // MARK: - Catalog

    static let all: [MarblingRecipe] = [
        .tutorial,
        .concentricCircles,
        .stoneGenerator,
        .nonpareilGenerator,
        .peacockGenerator,
        .combedGenerator
    ]

    /// Layered ink drops with arcs raked from both sides (Marblizer Tutorial).
    static let tutorial = MarblingRecipe(
        id: "tutorial",
        title: "Tutorial",
        description: "Layered ink drops with arcs raked through them from both sides."
    ) { ctx in
        var operations: [MarblingOperation] = []
        let colorSet = MarblingColorSets.sets[0]
        let center = CGPoint(x: ctx.canvasWidth * 0.5, y: ctx.canvasHeight * 0.5)
        for i in 0..<21 {
            let color = colorSet[i % colorSet.count]
            operations.append(
                .inkDrop(position: center, radius: 200 - 2 * Double(i), color: color)
            )
        }
        let halfWidth = ctx.canvasWidth / 2
        let midLeft = CGPoint(x: 0, y: ctx.canvasHeight / 2)
        let midRight = CGPoint(x: ctx.canvasWidth, y: ctx.canvasHeight / 2)
        for i in 0...3 {
            let radius = Double(i) * halfWidth / 3
            operations.append(
                .circularTine(origin: midLeft, radius: radius, numTines: 1, interval: 0)
            )
            operations.append(
                .circularTine(origin: midRight, radius: radius, numTines: 1, interval: 0)
            )
        }
        return operations
    }

    /// Concentric overlapping drops (Marblizer Concentric circles).
    static let concentricCircles = MarblingRecipe(
        id: "concentric-circles",
        title: "Concentric circles",
        description: "A single point of color, deepened by a hundred overlapping drops."
    ) { ctx in
        var operations: [MarblingOperation] = []
        let colorSet = MarblingColorSets.sets[0]
        let center = CGPoint(x: ctx.canvasWidth * 0.5, y: ctx.canvasHeight * 0.5)
        for i in 0..<100 {
            let color = colorSet[i % colorSet.count]
            operations.append(
                .inkDrop(position: center, radius: 200 - 2 * Double(i), color: color)
            )
        }
        return operations
    }

    static let stoneGenerator = styleGenerator(
        id: "gen-stone",
        title: "Generate: Traditional Stone",
        style: .stone
    )

    static let nonpareilGenerator = styleGenerator(
        id: "gen-nonpareil",
        title: "Generate: Nonpareil",
        style: .nonpareil
    )

    static let peacockGenerator = styleGenerator(
        id: "gen-peacock",
        title: "Generate: Peacock",
        style: .peacock
    )

    static let combedGenerator = styleGenerator(
        id: "gen-combed",
        title: "Generate: Combed",
        style: .combed
    )

    private static func styleGenerator(
        id: String,
        title: String,
        style: MarblingStyle
    ) -> MarblingRecipe {
        MarblingRecipe(
            id: id,
            title: title,
            description: style.help
        ) { ctx in
            var spec = MarbledPaperSpec(style: style)
            spec.background = ctx.backgroundColor
            if !ctx.history.isEmpty {
                // Prefer current FG as first palette ink when regenerating into an edit session.
                spec.palette = [ctx.foregroundColor] + MarbledPaperPalette.traditionalStone.colors
            }
            spec.seed = UInt64.random(in: 1...UInt64.max)
            return MarbledPaperGenerator.buildParametricOperations(
                spec: spec,
                logicalHeight: ctx.canvasHeight
            )
        }
    }
}

/// Marblizer-style preset color sets for recipes (`colorSets` in JS).
enum MarblingColorSets {
    static let sets: [[CodableColor]] = [
        [
            CodableColor(red: 0.537, green: 0.098, blue: 0.125), // #891920
            CodableColor(red: 0.863, green: 0.824, blue: 0.824), // #dcd2d2
            CodableColor(red: 0.12, green: 0.14, blue: 0.18),
            CodableColor(red: 0.72, green: 0.55, blue: 0.28),
            CodableColor(red: 0.18, green: 0.32, blue: 0.28)
        ],
        MarbledPaperPalette.indigoOchre.colors + [MarbledPaperPalette.indigoOchre.background],
        MarbledPaperPalette.venetianRed.colors + [MarbledPaperPalette.venetianRed.background],
        MarbledPaperPalette.verdeAntico.colors + [MarbledPaperPalette.verdeAntico.background]
    ]
}

/// In-app documentation for the Swift recipe API.
enum MarblingRecipeAPIDocs {
    struct Entry: Identifiable {
        let id: String
        let signature: String
        let description: String
    }

    struct Section: Identifiable {
        let id: String
        let title: String
        let entries: [Entry]
    }

    static let sections: [Section] = [
        Section(id: "context", title: "Recipe context", entries: [
            Entry(id: "cw", signature: "context.canvasWidth, canvasHeight", description: "Logical canvas size in pixels."),
            Entry(id: "hist", signature: "context.history", description: "Operations already applied, oldest first."),
            Entry(id: "fg", signature: "context.foregroundColor, backgroundColor", description: "Colors from the editor swatches."),
            Entry(id: "colorAt", signature: "context.colorAt(point)", description: "Samples the rendered color at a logical point."),
            Entry(id: "colorsAt", signature: "context.colorsAt(points)", description: "Batch color sampling.")
        ]),
        Section(id: "ops", title: "Operations", entries: [
            Entry(id: "drop", signature: "MarblingOperation.inkDrop(position:radius:color:displacing:)", description: "Deposits a disc of ink."),
            Entry(id: "line", signature: "MarblingOperation.lineTine(origin:direction:numTines:spacing:reach:)", description: "Straight comb rake."),
            Entry(id: "wavy", signature: "MarblingOperation.wavyTine(origin:direction:numTines:spacing:reach:)", description: "Wavy comb rake."),
            Entry(id: "circ", signature: "MarblingOperation.circularTine(origin:radius:numTines:interval:counterClockwise:)", description: "Circular rake."),
            Entry(id: "vortex", signature: "MarblingOperation.vortex(origin:radius:counterClockwise:)", description: "Spiral swirl."),
            Entry(id: "base", signature: "MarblingOperation.changeBaseColor(_:)", description: "Changes the bath base color.")
        ]),
        Section(id: "colors", title: "Colors", entries: [
            Entry(id: "sets", signature: "MarblingColorSets.sets", description: "Preset palettes matching Marblizer colorSets."),
            Entry(id: "codable", signature: "CodableColor(red:green:blue:)", description: "RGBA color with components 0–1.")
        ])
    ]
}
