import AppKit
import CoreGraphics
import Foundation
import simd

/// Procedural marbled paper via mathematical marbling (Lu et al.).
/// Operation inverse back-mapping follows the approach used by
/// [Marblizer](https://github.com/nickswalker/marblizer) (MIT) —
/// ink drops with area-preserving radial spread, then line / circular tines.
enum MarbledPaperGenerator {
    private static let cacheLock = NSLock()
    private static var imageCache: [CacheKey: CGImage] = [:]
    private static let maxCacheEntries = 24

    /// Logical composition size (Marblizer-style CSS pixels). Math is authored
    /// in this space, then sampled for any output resolution.
    private static let logicalWidth: Double = 1000

    private struct CacheKey: Hashable {
        let specHash: Int
        let width: Int
        let height: Int
    }

    static func render(spec: MarbledPaperSpec, width: Int, height: Int) -> CGImage? {
        let w = max(8, width)
        let h = max(8, height)
        let key = CacheKey(specHash: spec.stableHash, width: w, height: h)
        cacheLock.lock()
        if let cached = imageCache[key] {
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()

        guard let image = renderUncached(spec: spec, width: w, height: h) else { return nil }

        cacheLock.lock()
        if imageCache.count >= maxCacheEntries {
            imageCache.removeAll(keepingCapacity: true)
        }
        imageCache[key] = image
        cacheLock.unlock()
        return image
    }

    static func clearCache() {
        cacheLock.lock()
        imageCache.removeAll()
        cacheLock.unlock()
    }

    static func nsImage(spec: MarbledPaperSpec, sizePoints: CGSize, dpi: CGFloat = 300) -> NSImage? {
        let scale = dpi / 72
        let w = max(8, Int(ceil(sizePoints.width * scale)))
        let h = max(8, Int(ceil(sizePoints.height * scale)))
        guard let cg = render(spec: spec, width: w, height: h) else { return nil }
        return NSImage(cgImage: cg, size: sizePoints)
    }

    // MARK: - Render

    private static func renderUncached(spec: MarbledPaperSpec, width: Int, height: Int) -> CGImage? {
        let logicalH = logicalWidth * Double(height) / Double(width)
        var rng = SeededGenerator(seed: spec.seed)
        let ops = buildOperations(
            spec: spec,
            canvas: SIMD2(logicalWidth, logicalH),
            rng: &rng
        )
        let base = spec.background

        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)

        // Parallel rows for responsive previews / print export.
        pixels.withUnsafeMutableBytes { rawBuffer in
            let baseAddress = rawBuffer.bindMemory(to: UInt8.self).baseAddress!
            DispatchQueue.concurrentPerform(iterations: height) { y in
                let row = baseAddress + y * bytesPerRow
                let py = (Double(y) + 0.5) / Double(height) * logicalH
                for x in 0..<width {
                    let px = (Double(x) + 0.5) / Double(width) * logicalWidth
                    let color = colorAt(SIMD2(px, py), ops: ops, base: base)
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

    /// Newest-first inverse walk (Marblizer `colorAt` / backmap).
    private static func colorAt(_ sample: SIMD2<Double>, ops: [Op], base: CodableColor) -> CodableColor {
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
                    // Inverse radial spread: r = sqrt(r'² − R²)
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
            }
        }
        return base
    }

    // MARK: - Operations (Marblizer-compatible)

    private enum Op {
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
    }

    private static func buildOperations(
        spec: MarbledPaperSpec,
        canvas: SIMD2<Double>,
        rng: inout SeededGenerator
    ) -> [Op] {
        let scale = max(0.35, min(2.5, spec.scale))
        let density = min(1, max(0.1, spec.density))
        let turbulence = min(1, max(0, spec.turbulence))
        let balance = min(1, max(0, spec.colorBalance))
        let combSpacingScale = max(0.35, min(2.5, spec.combSpacing))
        let combStrengthScale = max(0.35, min(2.5, spec.combStrength))
        let dropSizeScale = max(0.35, min(2.5, spec.dropSize))
        let flow = spec.flowDegrees * .pi / 180
        let palette = spec.palette.isEmpty ? MarbledPaperPalette.traditionalStone.colors : spec.palette

        var ops: [Op] = []

        // Ink bath — larger drops first, then smaller (stone / traditional layering).
        let dropCount = Int((28 + density * 70) / scale)
        let maxRadius = min(canvas.x, canvas.y) * (0.12 + density * 0.08) * scale * dropSizeScale
        for i in 0..<dropCount {
            let t = Double(i) / Double(max(1, dropCount - 1))
            let radius = maxRadius * (1.0 - t * 0.75) * (0.55 + rng.nextDouble() * 0.55)
            let center = SIMD2(
                rng.nextDouble() * canvas.x,
                rng.nextDouble() * canvas.y
            )
            // Higher colorBalance → prefer later (top) inks.
            let colorIndex = Int(rng.nextDouble() * Double(palette.count) * (0.55 + balance * 0.45))
                % palette.count
            ops.append(.inkDrop(center: center, radius: radius, color: palette[colorIndex], displacing: true))
        }

        // Optional fine spatters (stone grain / turbulence).
        if turbulence > 0.05 {
            let spatters = Int(8 + turbulence * 40)
            for _ in 0..<spatters {
                let r = (4 + rng.nextDouble() * 18) * scale * dropSizeScale
                ops.append(
                    .inkDrop(
                        center: SIMD2(rng.nextDouble() * canvas.x, rng.nextDouble() * canvas.y),
                        radius: r,
                        color: palette[Int(rng.nextDouble() * Double(palette.count)) % palette.count],
                        displacing: turbulence > 0.35
                    )
                )
            }
        }

        let dir = SIMD2(cos(flow), sin(flow))
        let strength = min(canvas.x, canvas.y) * (0.35 + density * 0.25) * combStrengthScale

        switch spec.style {
        case .stone:
            // Mostly drops; a light rake if turbulence is high.
            if turbulence > 0.45 {
                appendLineTine(
                    &ops,
                    origin: SIMD2(0, canvas.y * 0.5),
                    direction: dir * strength * 0.55,
                    numTines: 6 + density * 8,
                    spacing: 28 * scale * combSpacingScale,
                    strengthScale: combStrengthScale,
                    canvas: canvas
                )
            }

        case .nonpareil:
            // Fine parallel combs, then reverse — classic nonpareil.
            let spacing = max(8, 14 * scale * (1.35 - density * 0.4) * combSpacingScale)
            let tines = 18 + density * 22
            appendLineTine(
                &ops,
                origin: SIMD2(0, canvas.y * 0.5),
                direction: dir * strength,
                numTines: tines,
                spacing: spacing,
                strengthScale: combStrengthScale,
                canvas: canvas
            )
            appendLineTine(
                &ops,
                origin: SIMD2(canvas.x, canvas.y * 0.5),
                direction: -dir * strength * 0.9,
                numTines: tines,
                spacing: spacing * 0.95,
                strengthScale: combStrengthScale,
                canvas: canvas
            )
            if turbulence > 0.25 {
                appendWavyTine(
                    &ops,
                    origin: SIMD2(canvas.x * 0.5, 0),
                    direction: SIMD2(-dir.y, dir.x) * strength * 0.4,
                    amplitude: (8 + turbulence * 18) * combStrengthScale,
                    wavelength: 180 + 120 * scale * combSpacingScale,
                    phase: rng.nextDouble() * .pi * 2,
                    canvas: canvas
                )
            }

        case .peacock:
            // Circular tines from left/right (Marblizer tutorial bouquet/peacock motif).
            let halfW = canvas.x * 0.5
            let rings = 3 + Int(density * 3)
            for i in 0...rings {
                let radius = Double(i) * halfW / Double(max(1, rings))
                ops.append(
                    .circularTine(
                        center: SIMD2(0, canvas.y * 0.5),
                        radius: max(1, radius),
                        numTines: 1,
                        interval: max(1, 40 * scale * combSpacingScale),
                        alpha: (70 + turbulence * 30) * combStrengthScale,
                        lambda: 32,
                        counterClockwise: false
                    )
                )
                ops.append(
                    .circularTine(
                        center: SIMD2(canvas.x, canvas.y * 0.5),
                        radius: max(1, radius),
                        numTines: 1,
                        interval: max(1, 40 * scale * combSpacingScale),
                        alpha: (70 + turbulence * 30) * combStrengthScale,
                        lambda: 32,
                        counterClockwise: true
                    )
                )
            }
            // Cross comb for peacock eye elongation along flow.
            appendLineTine(
                &ops,
                origin: SIMD2(canvas.x * 0.5, 0),
                direction: SIMD2(-sin(flow), cos(flow)) * strength * 0.45,
                numTines: 8 + density * 6,
                spacing: 36 * scale * combSpacingScale,
                strengthScale: combStrengthScale,
                canvas: canvas
            )

        case .combed:
            let spacing = max(16, 36 * scale * combSpacingScale)
            let tines = 8 + density * 10
            appendLineTine(
                &ops,
                origin: SIMD2(0, canvas.y * 0.5),
                direction: dir * strength * 1.15,
                numTines: tines,
                spacing: spacing,
                strengthScale: combStrengthScale,
                canvas: canvas
            )
            appendLineTine(
                &ops,
                origin: SIMD2(0, canvas.y * 0.35),
                direction: dir * strength * 0.85,
                numTines: tines * 0.85,
                spacing: spacing * 1.1,
                strengthScale: combStrengthScale,
                canvas: canvas
            )
            if turbulence > 0.2 {
                appendWavyTine(
                    &ops,
                    origin: SIMD2(0, canvas.y * 0.5),
                    direction: dir * strength * 0.5,
                    amplitude: (12 + turbulence * 28) * combStrengthScale,
                    wavelength: 260 * scale * combSpacingScale,
                    phase: rng.nextDouble() * .pi * 2,
                    canvas: canvas
                )
            }
        }

        return ops
    }

    private static func appendLineTine(
        _ ops: inout [Op],
        origin: SIMD2<Double>,
        direction: SIMD2<Double>,
        numTines: Double,
        spacing: Double,
        strengthScale: Double,
        canvas: SIMD2<Double>
    ) {
        let strength = simd_length(direction)
        guard strength > 1e-6 else { return }
        let line = direction / strength
        ops.append(
            .lineTine(
                origin: origin,
                line: line,
                numTines: numTines,
                spacing: max(4, spacing),
                alpha: (30 + strength / 10) * strengthScale,
                lambda: 32,
                reach: max(canvas.x, canvas.y) * 4,
                dragLength: strength
            )
        )
    }

    private static func appendWavyTine(
        _ ops: inout [Op],
        origin: SIMD2<Double>,
        direction: SIMD2<Double>,
        amplitude: Double,
        wavelength: Double,
        phase: Double,
        canvas: SIMD2<Double>
    ) {
        let strength = simd_length(direction)
        guard strength > 1e-6 else { return }
        let normal = direction / strength
        let line = SIMD2(-normal.y, normal.x) // perp — Marblizer WavyLineTine
        let angle = atan2(line.y, line.x)
        ops.append(
            .wavyTine(
                origin: origin,
                normal: normal,
                angle: angle,
                amplitude: amplitude + strength / 10,
                wavelength: max(40, wavelength),
                phase: phase,
                reach: max(canvas.x, canvas.y) * 4,
                dragLength: strength
            )
        )
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

private extension MarbledPaperSpec {
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
        return hasher.finalize()
    }
}
