import AppKit
import CoreGraphics
import Foundation
import simd

/// Procedural marbled paper via mathematical marbling (Lu et al.).
/// Operation inverse back-mapping follows the approach used by
/// [Marblizer](https://github.com/nickswalker/marblizer) (MIT) —
/// ink drops with area-preserving radial spread, then line / circular tines / vortex.
enum MarbledPaperGenerator {
    private static let cacheLock = NSLock()
    private static var imageCache: [CacheKey: CGImage] = [:]
    /// Most-recently-used key order (oldest first). Used for LRU eviction so a
    /// full cache never discards *everything* — generated marbles stay cached.
    private static var lruOrder: [CacheKey] = []
    private static let maxCacheEntries = 48

    /// Logical composition width (Marblizer-style CSS pixels). Math is authored
    /// in this space, then sampled for any output resolution.
    static let logicalWidth: Double = 1000
    /// Default logical height for square-ish previews when aspect is unknown.
    static let defaultLogicalHeight: Double = 1000

    private struct CacheKey: Hashable {
        let specHash: Int
        let width: Int
        let height: Int
    }

    /// Expanded render op after expanding scatter and resolving tine alphas.
    private enum RenderOp {
        case inkDrop(center: SIMD2<Double>, radius: Double, color: CodableColor, displacing: Bool)
        case lineTine(
            origin: SIMD2<Double>,
            line: SIMD2<Double>,
            numTines: Double,
            spacing: Double,
            alpha: Double,
            lambda: Double,
            reach: Double,
            dragLength: Double
        )
        case wavyTine(
            origin: SIMD2<Double>,
            normal: SIMD2<Double>,
            angle: Double,
            amplitude: Double,
            wavelength: Double,
            phase: Double,
            reach: Double,
            dragLength: Double
        )
        case circularTine(
            center: SIMD2<Double>,
            radius: Double,
            numTines: Double,
            interval: Double,
            alpha: Double,
            lambda: Double,
            counterClockwise: Bool
        )
        case vortex(
            center: SIMD2<Double>,
            radius: Double,
            alpha: Double,
            lambda: Double,
            counterClockwise: Bool
        )
    }

    static func render(spec: MarbledPaperSpec, width: Int, height: Int) -> CGImage? {
        let w = max(8, width)
        let h = max(8, height)
        let key = CacheKey(specHash: spec.stableHash, width: w, height: h)
        cacheLock.lock()
        if let cached = imageCache[key] {
            markRecentlyUsed(key)
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()

        guard let image = renderUncached(spec: spec, width: w, height: h) else { return nil }

        cacheLock.lock()
        imageCache[key] = image
        markRecentlyUsed(key)
        while lruOrder.count > maxCacheEntries {
            let evicted = lruOrder.removeFirst()
            imageCache.removeValue(forKey: evicted)
        }
        cacheLock.unlock()
        return image
    }

    /// Move `key` to the most-recently-used end. Caller must hold `cacheLock`.
    private static func markRecentlyUsed(_ key: CacheKey) {
        if let index = lruOrder.firstIndex(of: key) {
            lruOrder.remove(at: index)
        }
        lruOrder.append(key)
    }

    static func clearCache() {
        cacheLock.lock()
        imageCache.removeAll()
        lruOrder.removeAll()
        cacheLock.unlock()
    }

    static func nsImage(spec: MarbledPaperSpec, sizePoints: CGSize, dpi: CGFloat = 300) -> NSImage? {
        let scale = dpi / 72
        let w = max(8, Int(ceil(sizePoints.width * scale)))
        let h = max(8, Int(ceil(sizePoints.height * scale)))
        guard let cg = render(spec: spec, width: w, height: h) else { return nil }
        return NSImage(cgImage: cg, size: sizePoints)
    }

    /// Logical canvas size for a given pixel aspect (or default square).
    static func logicalSize(width: Int, height: Int) -> (width: Double, height: Double) {
        let logicalH = logicalWidth * Double(max(1, height)) / Double(max(1, width))
        return (logicalWidth, logicalH)
    }

    /// Resolve authoritative operations: history when present, else parametric build.
    static func resolveOperations(
        spec: MarbledPaperSpec,
        logicalHeight: Double? = nil
    ) -> [MarblingOperation] {
        if let ops = spec.operations, !ops.isEmpty {
            return ops
        }
        let h = logicalHeight ?? defaultLogicalHeight
        return buildParametricOperations(spec: spec, logicalHeight: h)
    }

    /// Public parametric generator used by recipes and `ensureEditableHistory`.
    static func buildParametricOperations(
        spec: MarbledPaperSpec,
        logicalHeight: Double
    ) -> [MarblingOperation] {
        var rng = SeededGenerator(seed: spec.seed)
        return buildParametricOperations(
            spec: spec,
            canvas: SIMD2(logicalWidth, logicalHeight),
            rng: &rng
        )
    }

    /// Sample color at a logical-space point (for recipes / force-field).
    static func colorAt(
        point: CGPoint,
        spec: MarbledPaperSpec,
        logicalHeight: Double
    ) -> CodableColor {
        let ops = expandForRender(resolveOperations(spec: spec, logicalHeight: logicalHeight))
        let base = resolvedBaseColor(spec: spec, operations: spec.operations)
        return sampleColor(SIMD2(Double(point.x), Double(point.y)), ops: ops, base: base)
    }

    static func colorsAt(
        points: [CGPoint],
        spec: MarbledPaperSpec,
        logicalHeight: Double
    ) -> [CodableColor] {
        let ops = expandForRender(resolveOperations(spec: spec, logicalHeight: logicalHeight))
        let base = resolvedBaseColor(spec: spec, operations: spec.operations)
        return points.map { sampleColor(SIMD2(Double($0.x), Double($0.y)), ops: ops, base: base) }
    }

    /// Displacement vector at a point for force-field overlay (forward estimate).
    static func displacementAt(
        point: CGPoint,
        spec: MarbledPaperSpec,
        logicalHeight: Double
    ) -> CGVector {
        let ops = expandForRender(resolveOperations(spec: spec, logicalHeight: logicalHeight))
        // Back-map a nearby sample to estimate local field motion.
        let p = SIMD2(Double(point.x), Double(point.y))
        let mapped = backmap(p, ops: ops)
        return CGVector(dx: mapped.x - p.x, dy: mapped.y - p.y)
    }

    // MARK: - Render

    private static func renderUncached(spec: MarbledPaperSpec, width: Int, height: Int) -> CGImage? {
        let logicalH = logicalWidth * Double(height) / Double(width)
        let sourceOps = resolveOperations(spec: spec, logicalHeight: logicalH)
        let ops = expandForRender(sourceOps)
        let base = resolvedBaseColor(spec: spec, operations: sourceOps)

        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)

        pixels.withUnsafeMutableBytes { rawBuffer in
            let baseAddress = rawBuffer.bindMemory(to: UInt8.self).baseAddress!
            DispatchQueue.concurrentPerform(iterations: height) { y in
                let row = baseAddress + y * bytesPerRow
                let py = (Double(y) + 0.5) / Double(height) * logicalH
                for x in 0..<width {
                    let px = (Double(x) + 0.5) / Double(width) * logicalWidth
                    let color = sampleColor(SIMD2(px, py), ops: ops, base: base)
                    let o = x * 4
                    row[o] = UInt8(min(255, max(0, Int((color.red * 255).rounded()))))
                    row[o + 1] = UInt8(min(255, max(0, Int((color.green * 255).rounded()))))
                    row[o + 2] = UInt8(min(255, max(0, Int((color.blue * 255).rounded()))))
                    row[o + 3] = 255
                }
            }
        }

        let data = CFDataCreate(nil, pixels, pixels.count)!
        let provider = CGDataProvider(data: data)!
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    }

    private static func resolvedBaseColor(
        spec: MarbledPaperSpec,
        operations: [MarblingOperation]?
    ) -> CodableColor {
        var base = spec.background
        guard let operations else { return base }
        for op in operations {
            if case let .changeBaseColor(color) = op {
                base = color
            }
        }
        return base
    }

    private static func expandForRender(_ operations: [MarblingOperation]) -> [RenderOp] {
        var result: [RenderOp] = []
        for op in operations {
            switch op {
            case let .inkDrop(x, y, radius, color, displacing):
                result.append(.inkDrop(center: SIMD2(x, y), radius: radius, color: color, displacing: displacing))
            case let .scatter(drops):
                for drop in drops {
                    result.append(
                        .inkDrop(
                            center: SIMD2(drop.x, drop.y),
                            radius: drop.radius,
                            color: drop.color,
                            displacing: false
                        )
                    )
                }
            case let .lineTine(ox, oy, dirX, dirY, numTines, spacing, reach):
                let direction = SIMD2(dirX, dirY)
                let strength = simd_length(direction)
                guard strength > 1e-6 else { continue }
                let line = direction / strength
                result.append(
                    .lineTine(
                        origin: SIMD2(ox, oy),
                        line: line,
                        numTines: numTines,
                        spacing: max(4, spacing),
                        alpha: 30 + strength / 10,
                        lambda: 32,
                        reach: reach,
                        dragLength: strength
                    )
                )
            case let .wavyTine(ox, oy, dirX, dirY, _, _, reach):
                let direction = SIMD2(dirX, dirY)
                let strength = simd_length(direction)
                guard strength > 1e-6 else { continue }
                let normal = direction / strength
                let line = SIMD2(-normal.y, normal.x)
                let angle = atan2(line.y, line.x)
                result.append(
                    .wavyTine(
                        origin: SIMD2(ox, oy),
                        normal: normal,
                        angle: angle,
                        amplitude: 10 + strength / 10,
                        wavelength: 400,
                        phase: 0,
                        reach: reach,
                        dragLength: strength
                    )
                )
            case let .circularTine(cx, cy, radius, numTines, interval, ccw):
                result.append(
                    .circularTine(
                        center: SIMD2(cx, cy),
                        radius: max(1, radius),
                        numTines: numTines,
                        interval: max(1, interval),
                        alpha: 80,
                        lambda: 32,
                        counterClockwise: ccw
                    )
                )
            case let .vortex(cx, cy, radius, ccw):
                result.append(
                    .vortex(
                        center: SIMD2(cx, cy),
                        radius: max(1, radius),
                        alpha: 80,
                        lambda: 32,
                        counterClockwise: ccw
                    )
                )
            case .changeBaseColor:
                break
            }
        }
        return result
    }

    /// Newest-first inverse walk (Marblizer `colorAt` / backmap).
    private static func sampleColor(
        _ sample: SIMD2<Double>,
        ops: [RenderOp],
        base: CodableColor
    ) -> CodableColor {
        var p = sample
        for i in stride(from: ops.count - 1, through: 0, by: -1) {
            switch ops[i] {
            case let .inkDrop(center, radius, color, displacing):
                let d = p - center
                let dist2 = simd_length_squared(d)
                if dist2 <= radius * radius {
                    return color
                }
                if displacing {
                    let rPrime = sqrt(dist2)
                    guard rPrime > 1e-9 else { continue }
                    let r = sqrt(max(0, dist2 - radius * radius))
                    p = center + d * (r / rPrime)
                }
            case let .lineTine(origin, line, numTines, spacing, alpha, lambda, reach, dragLength):
                p = p - lineTineOffset(
                    p,
                    origin: origin,
                    line: line,
                    numTines: numTines,
                    spacing: spacing,
                    alpha: alpha,
                    lambda: lambda,
                    reach: reach,
                    dragLength: dragLength
                )
            case let .wavyTine(origin, normal, angle, amplitude, wavelength, phase, reach, dragLength):
                p = p - wavyOffset(
                    p,
                    origin: origin,
                    normal: normal,
                    angle: angle,
                    amplitude: amplitude,
                    wavelength: wavelength,
                    phase: phase,
                    reach: reach,
                    dragLength: dragLength
                )
            case let .circularTine(center, radius, numTines, interval, alpha, lambda, ccw):
                p = circularTineInverse(
                    p,
                    center: center,
                    radius: radius,
                    numTines: numTines,
                    interval: interval,
                    alpha: alpha,
                    lambda: lambda,
                    counterClockwise: ccw
                )
            case let .vortex(center, radius, alpha, lambda, ccw):
                p = vortexInverse(
                    p,
                    center: center,
                    radius: radius,
                    alpha: alpha,
                    lambda: lambda,
                    counterClockwise: ccw
                )
            }
        }
        return base
    }

    private static func backmap(_ sample: SIMD2<Double>, ops: [RenderOp]) -> SIMD2<Double> {
        var p = sample
        for i in stride(from: ops.count - 1, through: 0, by: -1) {
            switch ops[i] {
            case let .inkDrop(center, radius, _, displacing):
                let d = p - center
                let dist2 = simd_length_squared(d)
                if dist2 <= radius * radius { continue }
                if displacing {
                    let rPrime = sqrt(dist2)
                    guard rPrime > 1e-9 else { continue }
                    let r = sqrt(max(0, dist2 - radius * radius))
                    p = center + d * (r / rPrime)
                }
            case let .lineTine(origin, line, numTines, spacing, alpha, lambda, reach, dragLength):
                p = p - lineTineOffset(
                    p, origin: origin, line: line, numTines: numTines, spacing: spacing,
                    alpha: alpha, lambda: lambda, reach: reach, dragLength: dragLength
                )
            case let .wavyTine(origin, normal, angle, amplitude, wavelength, phase, reach, dragLength):
                p = p - wavyOffset(
                    p, origin: origin, normal: normal, angle: angle, amplitude: amplitude,
                    wavelength: wavelength, phase: phase, reach: reach, dragLength: dragLength
                )
            case let .circularTine(center, radius, numTines, interval, alpha, lambda, ccw):
                p = circularTineInverse(
                    p, center: center, radius: radius, numTines: numTines, interval: interval,
                    alpha: alpha, lambda: lambda, counterClockwise: ccw
                )
            case let .vortex(center, radius, alpha, lambda, ccw):
                p = vortexInverse(
                    p, center: center, radius: radius, alpha: alpha, lambda: lambda,
                    counterClockwise: ccw
                )
            }
        }
        return p
    }

    // MARK: - Parametric build → MarblingOperation

    private static func buildParametricOperations(
        spec: MarbledPaperSpec,
        canvas: SIMD2<Double>,
        rng: inout SeededGenerator
    ) -> [MarblingOperation] {
        let scale = max(0.35, min(2.5, spec.scale))
        let density = min(1, max(0.1, spec.density))
        let turbulence = min(1, max(0, spec.turbulence))
        let balance = min(1, max(0, spec.colorBalance))
        let combSpacingScale = max(0.35, min(2.5, spec.combSpacing))
        let combStrengthScale = max(0.35, min(2.5, spec.combStrength))
        let dropSizeScale = max(0.35, min(2.5, spec.dropSize))
        let flow = spec.flowDegrees * .pi / 180
        let palette = spec.palette.isEmpty ? MarbledPaperPalette.traditionalStone.colors : spec.palette
        let reach = max(canvas.x, canvas.y) * 4

        var ops: [MarblingOperation] = []

        let dropCount = Int((28 + density * 70) / scale)
        let maxRadius = min(canvas.x, canvas.y) * (0.12 + density * 0.08) * scale * dropSizeScale
        for i in 0..<dropCount {
            let t = Double(i) / Double(max(1, dropCount - 1))
            let radius = maxRadius * (1.0 - t * 0.75) * (0.55 + rng.nextDouble() * 0.55)
            let center = CGPoint(x: rng.nextDouble() * canvas.x, y: rng.nextDouble() * canvas.y)
            let colorIndex = Int(rng.nextDouble() * Double(palette.count) * (0.55 + balance * 0.45))
                % palette.count
            ops.append(.inkDrop(position: center, radius: radius, color: palette[colorIndex], displacing: true))
        }

        if turbulence > 0.05 {
            let spatters = Int(8 + turbulence * 40)
            var drops: [MarblingInkDeposit] = []
            for _ in 0..<spatters {
                let r = (4 + rng.nextDouble() * 18) * scale * dropSizeScale
                drops.append(
                    MarblingInkDeposit(
                        center: CGPoint(x: rng.nextDouble() * canvas.x, y: rng.nextDouble() * canvas.y),
                        radius: r,
                        color: palette[Int(rng.nextDouble() * Double(palette.count)) % palette.count]
                    )
                )
            }
            if turbulence > 0.35 {
                for drop in drops {
                    ops.append(.inkDrop(position: drop.center, radius: drop.radius, color: drop.color, displacing: true))
                }
            } else {
                ops.append(.scatter(drops: drops))
            }
        }

        let dir = SIMD2(cos(flow), sin(flow))
        let strength = min(canvas.x, canvas.y) * (0.35 + density * 0.25) * combStrengthScale

        switch spec.style {
        case .stone:
            if turbulence > 0.45 {
                let direction = CGVector(dx: dir.x * strength * 0.55, dy: dir.y * strength * 0.55)
                ops.append(
                    .lineTine(
                        origin: CGPoint(x: 0, y: canvas.y * 0.5),
                        direction: direction,
                        numTines: 6 + density * 8,
                        spacing: 28 * scale * combSpacingScale,
                        reach: reach
                    )
                )
            }

        case .nonpareil:
            let spacing = max(8, 14 * scale * (1.35 - density * 0.4) * combSpacingScale)
            let tines = 18 + density * 22
            ops.append(
                .lineTine(
                    origin: CGPoint(x: 0, y: canvas.y * 0.5),
                    direction: CGVector(dx: dir.x * strength, dy: dir.y * strength),
                    numTines: tines,
                    spacing: spacing,
                    reach: reach
                )
            )
            ops.append(
                .lineTine(
                    origin: CGPoint(x: canvas.x, y: canvas.y * 0.5),
                    direction: CGVector(dx: -dir.x * strength * 0.9, dy: -dir.y * strength * 0.9),
                    numTines: tines,
                    spacing: spacing * 0.95,
                    reach: reach
                )
            )
            if turbulence > 0.25 {
                let perp = SIMD2(-dir.y, dir.x) * strength * 0.4
                ops.append(
                    .wavyTine(
                        origin: CGPoint(x: canvas.x * 0.5, y: 0),
                        direction: CGVector(dx: perp.x, dy: perp.y),
                        numTines: 1,
                        spacing: 200,
                        reach: reach
                    )
                )
            }

        case .peacock:
            let halfW = canvas.x * 0.5
            let rings = 3 + Int(density * 3)
            for i in 0...rings {
                let radius = Double(i) * halfW / Double(max(1, rings))
                let interval = max(1, 40 * scale * combSpacingScale)
                ops.append(
                    .circularTine(
                        origin: CGPoint(x: 0, y: canvas.y * 0.5),
                        radius: max(1, radius),
                        numTines: 1,
                        interval: interval,
                        counterClockwise: false
                    )
                )
                ops.append(
                    .circularTine(
                        origin: CGPoint(x: canvas.x, y: canvas.y * 0.5),
                        radius: max(1, radius),
                        numTines: 1,
                        interval: interval,
                        counterClockwise: true
                    )
                )
            }
            ops.append(
                .lineTine(
                    origin: CGPoint(x: canvas.x * 0.5, y: 0),
                    direction: CGVector(dx: -sin(flow) * strength * 0.45, dy: cos(flow) * strength * 0.45),
                    numTines: 8 + density * 6,
                    spacing: 36 * scale * combSpacingScale,
                    reach: reach
                )
            )

        case .combed:
            let spacing = max(16, 36 * scale * combSpacingScale)
            let tines = 8 + density * 10
            ops.append(
                .lineTine(
                    origin: CGPoint(x: 0, y: canvas.y * 0.5),
                    direction: CGVector(dx: dir.x * strength * 1.15, dy: dir.y * strength * 1.15),
                    numTines: tines,
                    spacing: spacing,
                    reach: reach
                )
            )
            ops.append(
                .lineTine(
                    origin: CGPoint(x: 0, y: canvas.y * 0.35),
                    direction: CGVector(dx: dir.x * strength * 0.85, dy: dir.y * strength * 0.85),
                    numTines: tines * 0.85,
                    spacing: spacing * 1.1,
                    reach: reach
                )
            )
            if turbulence > 0.2 {
                ops.append(
                    .wavyTine(
                        origin: CGPoint(x: 0, y: canvas.y * 0.5),
                        direction: CGVector(dx: dir.x * strength * 0.5, dy: dir.y * strength * 0.5),
                        numTines: 1,
                        spacing: 200,
                        reach: reach
                    )
                )
            }
        }

        return ops
    }

    // MARK: - Displacement math (from Marblizer)

    private static func lineTineOffset(
        _ p: SIMD2<Double>,
        origin: SIMD2<Double>,
        line: SIMD2<Double>,
        numTines: Double,
        spacing: Double,
        alpha: Double,
        lambda: Double,
        reach: Double,
        dragLength: Double
    ) -> SIMD2<Double> {
        let d = p - origin
        let nrm = SIMD2(-line.y, line.x)
        var dPerp = abs(simd_dot(d, nrm))
        let halfSpace = spacing / 2
        if dPerp / spacing < numTines {
            let t = fmodPositive(dPerp, spacing)
            dPerp = halfSpace - abs(t - halfSpace)
        } else {
            dPerp -= spacing * numTines
        }
        let dLine = simd_dot(d, line)
        let overshoot = max(0, max(-dLine, dLine - dragLength))
        let longitudinal = reach / (overshoot + reach)
        let factor = alpha * lambda / (dPerp + lambda) * longitudinal
        return line * factor
    }

    private static func wavyOffset(
        _ p: SIMD2<Double>,
        origin: SIMD2<Double>,
        normal: SIMD2<Double>,
        angle: Double,
        amplitude: Double,
        wavelength: Double,
        phase: Double,
        reach: Double,
        dragLength: Double
    ) -> SIMD2<Double> {
        let sinT = sin(angle)
        let cosT = cos(angle)
        let v = p.x * sinT - p.y * cosT
        let factor = amplitude * sin(2 * .pi / wavelength * v + phase)
        let dLine = simd_dot(p - origin, normal)
        let overshoot = max(0, max(-dLine, dLine - dragLength))
        let longitudinal = reach / (overshoot + reach)
        return SIMD2(cosT, sinT) * factor * longitudinal
    }

    private static func circularTineInverse(
        _ p: SIMD2<Double>,
        center: SIMD2<Double>,
        radius: Double,
        numTines: Double,
        interval: Double,
        alpha: Double,
        lambda: Double,
        counterClockwise: Bool
    ) -> SIMD2<Double> {
        let pl = p - center
        let len = simd_length(pl)
        guard len > 1e-6 else { return p }
        var d = abs(len - radius)
        let halfSpace = interval / 2
        if interval > 1e-6, d / interval < numTines {
            let test = fmodPositive(d, interval)
            d = halfSpace - abs(test - halfSpace)
        } else {
            d -= interval * numTines
        }
        let l = alpha * lambda / (d + lambda)
        var theta = counterClockwise ? -l / len : l / len
        theta = -theta // inverse
        let cs = cos(theta)
        let sn = sin(theta)
        return center + SIMD2(pl.x * cs - pl.y * sn, pl.x * sn + pl.y * cs)
    }

    /// Marblizer vortex inverse: `d = abs(100/radius * len)`.
    private static func vortexInverse(
        _ p: SIMD2<Double>,
        center: SIMD2<Double>,
        radius: Double,
        alpha: Double,
        lambda: Double,
        counterClockwise: Bool
    ) -> SIMD2<Double> {
        let pl = p - center
        let len = simd_length(pl)
        guard len > 1e-6, radius > 1e-6 else { return p }
        let d = abs(100 / radius * len)
        let l = alpha * lambda / (d + lambda)
        var theta = counterClockwise ? -l / len : l / len
        theta = -theta // inverse
        let cs = cos(theta)
        let sn = sin(theta)
        return center + SIMD2(pl.x * cs - pl.y * sn, pl.x * sn + pl.y * cs)
    }

    private static func fmodPositive(_ a: Double, _ b: Double) -> Double {
        guard b != 0 else { return 0 }
        let r = a.truncatingRemainder(dividingBy: b)
        return r >= 0 ? r : r + b
    }
}

// MARK: - Deterministic RNG

struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0xDEADBEEF : seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    mutating func nextDouble() -> Double {
        Double(next() % 1_000_000) / 1_000_000
    }
}

extension MarbledPaperSpec {
    var stableHash: Int {
        var hasher = Hasher()
        hasher.combine(style)
        hasher.combine(seed)
        hasher.combine(scale)
        hasher.combine(flowDegrees)
        hasher.combine(turbulence)
        hasher.combine(density)
        hasher.combine(colorBalance)
        hasher.combine(combSpacing)
        hasher.combine(combStrength)
        hasher.combine(dropSize)
        hasher.combine(background)
        for color in palette {
            hasher.combine(color)
        }
        if let operations {
            hasher.combine(operations.count)
            for op in operations {
                hasher.combine(op)
            }
        }
        return hasher.finalize()
    }
}
