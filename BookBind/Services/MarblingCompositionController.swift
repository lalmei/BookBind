import Combine
import CoreGraphics
import Foundation
import SwiftUI

/// Session controller for interactive marbling: history, undo/redo, tool gestures.
@MainActor
final class MarblingCompositionController: ObservableObject {
    @Published private(set) var spec: MarbledPaperSpec
    @Published var tool: MarblingTool = .drop
    @Published var toolParameters = MarblingToolParameters()
    @Published var foregroundColor: CodableColor
    @Published var backgroundColor: CodableColor
    @Published var recentColors: [CodableColor] = []
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false

    /// Logical canvas height (width is always `MarbledPaperGenerator.logicalWidth`).
    var logicalHeight: Double

    private var redoStack: [MarblingOperation] = []
    private let maxRecentColors = 8

    init(spec: MarbledPaperSpec, logicalHeight: Double = MarbledPaperGenerator.defaultLogicalHeight) {
        var initial = spec
        if initial.palette.isEmpty {
            initial.palette = MarbledPaperPalette.traditionalStone.colors
        }
        self.spec = initial
        self.logicalHeight = logicalHeight
        self.foregroundColor = initial.palette.first ?? .inkBlack
        self.backgroundColor = initial.background
        syncHistoryFlags()
    }

    var operations: [MarblingOperation] {
        spec.operations ?? []
    }

    var logicalSize: CGSize {
        CGSize(width: MarbledPaperGenerator.logicalWidth, height: logicalHeight)
    }

    // MARK: - History

    func apply(_ operation: MarblingOperation) {
        apply([operation])
    }

    func apply(_ operations: [MarblingOperation]) {
        guard !operations.isEmpty else { return }
        var next = spec
        var history = next.operations ?? []
        history.append(contentsOf: operations)
        next.operations = history
        if case let .changeBaseColor(color) = operations.last {
            next.background = color
            backgroundColor = color
        }
        spec = next
        redoStack.removeAll()
        rememberColors(from: operations)
        syncHistoryFlags()
    }

    func undo() {
        guard var history = spec.operations, let last = history.popLast() else { return }
        redoStack.append(last)
        var next = spec
        next.operations = history
        refreshBackground(from: history, into: &next)
        spec = next
        syncHistoryFlags()
    }

    func redo() {
        guard let op = redoStack.popLast() else { return }
        var next = spec
        var history = next.operations ?? []
        history.append(op)
        next.operations = history
        if case let .changeBaseColor(color) = op {
            next.background = color
            backgroundColor = color
        }
        spec = next
        syncHistoryFlags()
    }

    func reset() {
        var next = spec
        next.operations = []
        next.background = backgroundColor
        spec = next
        redoStack.removeAll()
        syncHistoryFlags()
    }

    /// Replace or append recipe output.
    func applyRecipe(_ ops: [MarblingOperation], replace: Bool) {
        var next = spec
        if replace {
            next.operations = ops
            redoStack.removeAll()
        } else {
            var history = next.operations ?? []
            history.append(contentsOf: ops)
            next.operations = history
            redoStack.removeAll()
        }
        for op in ops {
            if case let .changeBaseColor(color) = op {
                next.background = color
                backgroundColor = color
            }
        }
        spec = next
        rememberColors(from: ops)
        syncHistoryFlags()
    }

    func setBackgroundColor(_ color: CodableColor, asOperation: Bool) {
        backgroundColor = color
        if asOperation, spec.hasEditableHistory {
            apply(.changeBaseColor(color))
        } else {
            var next = spec
            next.background = color
            spec = next
        }
        pushRecent(color)
    }

    func setForegroundColor(_ color: CodableColor) {
        foregroundColor = color
        pushRecent(color)
    }

    /// Updates stored palette / background used by parametric regenerations.
    func updatePalette(_ palette: MarbledPaperPalette) {
        var next = spec
        next.palette = palette.colors
        next.background = palette.background
        spec = next
        setForegroundColor(palette.colors.first ?? .inkBlack)
        backgroundColor = palette.background
        pushRecent(palette.background)
    }

    /// New parametric variation — clears history so style/seed regenerates.
    func regenerateVariation() {
        var next = spec
        next.regenerateVariation()
        spec = next
        redoStack.removeAll()
        syncHistoryFlags()
    }

    func ensureEditableHistory() {
        var next = spec
        next.ensureEditableHistory(logicalHeight: logicalHeight)
        spec = next
        syncHistoryFlags()
    }

    // MARK: - Gesture factories

    func inkDrop(at point: CGPoint, displacing: Bool) -> MarblingOperation {
        .inkDrop(
            position: point,
            radius: toolParameters.dropRadius,
            color: foregroundColor,
            displacing: displacing
        )
    }

    func makeSpatterDrops(around point: CGPoint, rng: inout SeededGenerator) -> [MarblingInkDeposit] {
        let count = max(1, toolParameters.spatterCount)
        let scatterR = toolParameters.scatterRadius
        let dropR = toolParameters.spatterDropRadius
        let variability = toolParameters.spatterVariability
        var drops: [MarblingInkDeposit] = []
        drops.reserveCapacity(count)
        for _ in 0..<count {
            let angle = rng.nextDouble() * .pi * 2
            let dist = rng.nextDouble() * scatterR
            let r = max(2, dropR + (rng.nextDouble() - 0.5) * variability)
            drops.append(
                MarblingInkDeposit(
                    x: point.x + cos(angle) * dist,
                    y: point.y + sin(angle) * dist,
                    radius: r,
                    color: foregroundColor
                )
            )
        }
        return drops
    }

    func lineTine(from origin: CGPoint, to end: CGPoint) -> MarblingOperation {
        .lineTine(
            origin: origin,
            direction: CGVector(dx: end.x - origin.x, dy: end.y - origin.y),
            numTines: toolParameters.numTines,
            spacing: toolParameters.tineSpacing,
            reach: toolParameters.reach
        )
    }

    func wavyTine(from origin: CGPoint, to end: CGPoint) -> MarblingOperation {
        .wavyTine(
            origin: origin,
            direction: CGVector(dx: end.x - origin.x, dy: end.y - origin.y),
            numTines: toolParameters.wavyNumTines,
            spacing: toolParameters.wavySpacing,
            reach: toolParameters.wavyReach
        )
    }

    func circularTine(from origin: CGPoint, to end: CGPoint) -> MarblingOperation {
        let dx = end.x - origin.x
        let dy = end.y - origin.y
        let radius = hypot(dx, dy)
        let ccw = MarblingOperation.counterclockwiseForDrag(direction: CGVector(dx: dx, dy: dy))
        return .circularTine(
            origin: origin,
            radius: max(1, radius),
            numTines: toolParameters.circularNumTines,
            interval: toolParameters.circularSpacing,
            counterClockwise: ccw
        )
    }

    func vortex(from origin: CGPoint, to end: CGPoint) -> MarblingOperation {
        let dx = end.x - origin.x
        let dy = end.y - origin.y
        let radius = hypot(dx, dy)
        let ccw = MarblingOperation.counterclockwiseForDrag(direction: CGVector(dx: dx, dy: dy))
        return .vortex(origin: origin, radius: max(1, radius), counterClockwise: ccw)
    }

    func recipeContext() -> MarblingRecipeContext {
        MarblingRecipeContext(
            canvasWidth: MarbledPaperGenerator.logicalWidth,
            canvasHeight: logicalHeight,
            history: operations,
            foregroundColor: foregroundColor,
            backgroundColor: backgroundColor,
            colorAt: { [weak self] point in
                guard let self else { return nil }
                return MarbledPaperGenerator.colorAt(
                    point: point,
                    spec: self.spec,
                    logicalHeight: self.logicalHeight
                )
            },
            colorsAt: { [weak self] points in
                guard let self else { return points.map { _ in nil } }
                return MarbledPaperGenerator.colorsAt(
                    points: points,
                    spec: self.spec,
                    logicalHeight: self.logicalHeight
                ).map { Optional($0) }
            }
        )
    }

    // MARK: - Private

    private func syncHistoryFlags() {
        canUndo = !(spec.operations ?? []).isEmpty
        canRedo = !redoStack.isEmpty
    }

    private func refreshBackground(from history: [MarblingOperation], into next: inout MarbledPaperSpec) {
        var base = backgroundColor
        for op in history {
            if case let .changeBaseColor(color) = op {
                base = color
            }
        }
        // If no changeBaseColor in history, keep current backgroundColor swatch.
        if history.contains(where: {
            if case .changeBaseColor = $0 { return true }
            return false
        }) {
            next.background = base
            backgroundColor = base
        }
    }

    private func rememberColors(from operations: [MarblingOperation]) {
        for op in operations {
            switch op {
            case let .inkDrop(_, _, _, color, _):
                pushRecent(color)
            case let .scatter(drops):
                if let color = drops.first?.color { pushRecent(color) }
            case let .changeBaseColor(color):
                pushRecent(color)
            default:
                break
            }
        }
    }

    private func pushRecent(_ color: CodableColor) {
        recentColors.removeAll { $0 == color }
        recentColors.insert(color, at: 0)
        if recentColors.count > maxRecentColors {
            recentColors = Array(recentColors.prefix(maxRecentColors))
        }
    }
}
