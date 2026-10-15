import XCTest
@testable import BookBind

final class MarblingEditorTests: XCTestCase {
    func testOperationsRoundTrip() throws {
        var spec = MarbledPaperSpec(style: .stone, seed: 42)
        spec.operations = [
            .inkDrop(position: CGPoint(x: 100, y: 200), radius: 40, color: .inkBlack),
            .lineTine(
                origin: CGPoint(x: 0, y: 500),
                direction: CGVector(dx: 400, dy: 0),
                numTines: 3,
                spacing: 40
            ),
            .vortex(origin: CGPoint(x: 500, y: 500), radius: 120, counterClockwise: true),
            .changeBaseColor(.paperIvory),
            .scatter(drops: [
                MarblingInkDeposit(center: CGPoint(x: 10, y: 10), radius: 5, color: .inkBlack)
            ])
        ]
        let data = try JSONEncoder().encode(spec)
        let restored = try JSONDecoder().decode(MarbledPaperSpec.self, from: data)
        XCTAssertEqual(restored.operations, spec.operations)
        XCTAssertTrue(restored.hasEditableHistory)
    }

    func testLegacySpecWithoutOperationsStillDecodes() throws {
        let json = """
        {
          "style": "peacock",
          "seed": 99,
          "scale": 1.0,
          "flowDegrees": 0,
          "turbulence": 0.3,
          "density": 0.5,
          "colorBalance": 0.5,
          "combSpacing": 1.0,
          "combStrength": 1.0,
          "dropSize": 1.0,
          "palette": [],
          "background": { "red": 0.96, "green": 0.94, "blue": 0.86, "opacity": 1 }
        }
        """.data(using: .utf8)!
        let spec = try JSONDecoder().decode(MarbledPaperSpec.self, from: json)
        XCTAssertNil(spec.operations)
        XCTAssertFalse(spec.hasEditableHistory)
        XCTAssertEqual(spec.style, .peacock)
        XCTAssertEqual(spec.seed, 99)
    }

    func testHistoryRenderIsDeterministic() {
        var spec = MarbledPaperSpec()
        spec.operations = [
            .inkDrop(position: CGPoint(x: 500, y: 500), radius: 80, color: CodableColor(red: 0.5, green: 0.1, blue: 0.1)),
            .vortex(origin: CGPoint(x: 500, y: 500), radius: 200, counterClockwise: false)
        ]
        let a = MarbledPaperGenerator.render(spec: spec, width: 48, height: 48)
        let b = MarbledPaperGenerator.render(spec: spec, width: 48, height: 48)
        XCTAssertNotNil(a)
        XCTAssertNotNil(b)
        XCTAssertEqual(pixelChecksum(a!), pixelChecksum(b!))
    }

    func testVortexDisplacesField() {
        MarbledPaperGenerator.clearCache()
        var spec = MarbledPaperSpec()
        spec.operations = [
            .vortex(origin: CGPoint(x: 500, y: 500), radius: 80, counterClockwise: true)
        ]
        let disp = MarbledPaperGenerator.displacementAt(
            point: CGPoint(x: 650, y: 500),
            spec: spec,
            logicalHeight: 1000
        )
        XCTAssertGreaterThan(hypot(disp.dx, disp.dy), 1.0, "Vortex should displace points away from identity")
    }

    func testChangeBaseColorAffectsEmptyRegions() {
        var white = MarbledPaperSpec()
        white.background = .paperIvory
        white.operations = [.changeBaseColor(CodableColor(red: 0.1, green: 0.2, blue: 0.8))]
        let image = MarbledPaperGenerator.render(spec: white, width: 16, height: 16)!
        // Sample corner — should be blue-ish base, not ivory.
        let color = MarbledPaperGenerator.colorAt(
            point: CGPoint(x: 10, y: 10),
            spec: white,
            logicalHeight: 1000
        )
        XCTAssertGreaterThan(color.blue, 0.5)
        XCTAssertLessThan(color.red, 0.3)
        _ = image
    }

    func testTutorialRecipeProducesOpsAndRenders() {
        let ctx = MarblingRecipeContext(
            canvasWidth: 1000,
            canvasHeight: 800,
            history: [],
            foregroundColor: .inkBlack,
            backgroundColor: .paperIvory,
            colorAt: { _ in nil },
            colorsAt: { $0.map { _ in nil } }
        )
        let ops = MarblingRecipe.tutorial.run(ctx)
        XCTAssertFalse(ops.isEmpty)
        var spec = MarbledPaperSpec()
        spec.operations = ops
        XCTAssertNotNil(MarbledPaperGenerator.render(spec: spec, width: 32, height: 32))
    }

    @MainActor
    func testControllerUndoRedo() {
        let controller = MarblingCompositionController(spec: MarbledPaperSpec())
        XCTAssertFalse(controller.canUndo)
        controller.apply(
            .inkDrop(position: CGPoint(x: 100, y: 100), radius: 20, color: .inkBlack)
        )
        XCTAssertTrue(controller.canUndo)
        XCTAssertEqual(controller.operations.count, 1)
        controller.undo()
        XCTAssertEqual(controller.operations.count, 0)
        XCTAssertTrue(controller.canRedo)
        controller.redo()
        XCTAssertEqual(controller.operations.count, 1)
        controller.reset()
        XCTAssertEqual(controller.operations.count, 0)
        XCTAssertFalse(controller.canUndo)
    }

    func testParametricPathStillDeterministic() {
        let spec = MarbledPaperSpec(style: .nonpareil, seed: 99)
        XCTAssertNil(spec.operations)
        let a = MarbledPaperGenerator.render(spec: spec, width: 48, height: 64)
        let b = MarbledPaperGenerator.render(spec: spec, width: 48, height: 64)
        XCTAssertEqual(pixelChecksum(a!), pixelChecksum(b!))
    }

    func testEnsureEditableHistoryMaterializesOps() {
        var spec = MarbledPaperSpec(style: .combed, seed: 7)
        XCTAssertFalse(spec.hasEditableHistory)
        spec.ensureEditableHistory(logicalHeight: 800)
        XCTAssertTrue(spec.hasEditableHistory)
        XCTAssertGreaterThan(spec.operations?.count ?? 0, 0)
    }

    private func pixelChecksum(_ image: CGImage) -> UInt64 {
        guard let data = image.dataProvider?.data as Data? else { return 0 }
        var hash: UInt64 = 5381
        for byte in data {
            hash = ((hash << 5) &+ hash) &+ UInt64(byte)
        }
        return hash
    }
}
