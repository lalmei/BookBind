import Foundation

/// A named colour, as stored in the swatch palette and in `.ase` files.
struct Swatch: Identifiable, Equatable, Codable, Hashable {
    var id = UUID()
    var name: String
    var color: CodableColor
}

/// Adobe Swatch Exchange (`.ase`) reader and writer, so palettes move between InABind and
/// Illustrator, InDesign, Affinity, Procreate, and others.
///
/// Layout (big-endian): `ASEF`, version 1.0, block count, then blocks of
/// `type:u16 length:u32 payload`. Colour payload: UTF-16 name (length in code units, including
/// the terminator), a 4-byte model (`RGB `, `CMYK`, `LAB `, `Gray`), float32 components, and a
/// u16 colour type. Groups are flattened. Format notes follow DesignCraft's `ase.rs`
/// (storytold/designcraft, MIT OR Apache-2.0); independent Swift implementation.
enum ASESwatchFile {
    enum ReadError: Error, LocalizedError {
        case notASE
        case truncated

        var errorDescription: String? {
            switch self {
            case .notASE: return "This isn't an Adobe Swatch Exchange (.ase) file."
            case .truncated: return "The swatch file is incomplete or damaged."
            }
        }
    }

    private static let colorBlock: UInt16 = 0x0001
    private static let groupStart: UInt16 = 0xC001
    private static let groupEnd: UInt16 = 0xC002

    // MARK: - Read

    static func read(_ data: Data) throws -> [Swatch] {
        var reader = Reader(bytes: [UInt8](data))
        guard try reader.bytes(4) == Array("ASEF".utf8) else { throw ReadError.notASE }
        _ = try reader.u16() // major
        _ = try reader.u16() // minor
        let count = try reader.u32()

        var swatches: [Swatch] = []
        for _ in 0..<count {
            let type = try reader.u16()
            let length = Int(try reader.u32())
            let blockEnd = reader.offset + length
            guard blockEnd <= reader.count else { throw ReadError.truncated }
            if type == colorBlock {
                let name = try reader.utf16Name()
                let model = String(decoding: try reader.bytes(4), as: UTF8.self)
                if let color = try readColor(model: model, reader: &reader) {
                    swatches.append(Swatch(name: name.isEmpty ? "Swatch \(swatches.count + 1)" : name, color: color))
                }
            }
            // Group markers carry only a name; skip whatever remains of any block.
            reader.offset = blockEnd
        }
        return swatches
    }

    private static func readColor(model: String, reader: inout Reader) throws -> CodableColor? {
        switch model {
        case "RGB ":
            let r = try reader.f32(), g = try reader.f32(), b = try reader.f32()
            return CodableColor(red: r, green: g, blue: b)
        case "CMYK":
            let c = try reader.f32(), m = try reader.f32(), y = try reader.f32(), k = try reader.f32()
            // Naive device conversion — fine for picking; printers will profile it anyway.
            return CodableColor(red: (1 - c) * (1 - k), green: (1 - m) * (1 - k), blue: (1 - y) * (1 - k))
        case "Gray":
            let g = try reader.f32()
            return CodableColor(red: g, green: g, blue: g)
        case "LAB ":
            let l = try reader.f32(), a = try reader.f32(), b = try reader.f32()
            return labToSRGB(l: l * 100, a: a, b: b)
        default:
            return nil
        }
    }

    /// CIE L*a*b* (D50, as ASE stores it) → sRGB via XYZ with Bradford adaptation to D65.
    static func labToSRGB(l: Double, a: Double, b: Double) -> CodableColor {
        let fy = (l + 16) / 116
        let fx = fy + a / 500
        let fz = fy - b / 200
        func inverse(_ t: Double) -> Double {
            let t3 = t * t * t
            return t3 > 0.008856 ? t3 : (116 * t - 16) / 903.3
        }
        // D50 reference white.
        let x50 = 0.96422 * inverse(fx)
        let y50 = 1.0 * (l > 8 ? fy * fy * fy : l / 903.3)
        let z50 = 0.82521 * inverse(fz)
        // Bradford D50 → D65.
        let x = 0.9555766 * x50 - 0.0230393 * y50 + 0.0631636 * z50
        let y = -0.0282895 * x50 + 1.0099416 * y50 + 0.0210077 * z50
        let z = 0.0122982 * x50 - 0.0204830 * y50 + 1.3299098 * z50
        func gamma(_ c: Double) -> Double {
            let v = c <= 0.0031308 ? 12.92 * c : 1.055 * pow(c, 1 / 2.4) - 0.055
            return min(1, max(0, v))
        }
        return CodableColor(
            red: gamma(3.2404542 * x - 1.5371385 * y - 0.4985314 * z),
            green: gamma(-0.9692660 * x + 1.8760108 * y + 0.0415560 * z),
            blue: gamma(0.0556434 * x - 0.2040259 * y + 1.0572252 * z)
        )
    }

    // MARK: - Write

    /// RGB `.ase` of `swatches`, optionally wrapped in a named group.
    static func write(_ swatches: [Swatch], groupName: String? = nil) -> Data {
        var blocks: [(UInt16, [UInt8])] = []
        if let groupName {
            blocks.append((groupStart, utf16Name(groupName)))
        }
        for swatch in swatches {
            var payload = utf16Name(swatch.name)
            payload += Array("RGB ".utf8)
            for component in [swatch.color.red, swatch.color.green, swatch.color.blue] {
                payload += bigEndian(Float32(component).bitPattern)
            }
            payload += bigEndian(UInt16(2)) // normal (process) colour
            blocks.append((colorBlock, payload))
        }
        if groupName != nil {
            blocks.append((groupEnd, []))
        }

        var out: [UInt8] = Array("ASEF".utf8)
        out += bigEndian(UInt16(1)) + bigEndian(UInt16(0))
        out += bigEndian(UInt32(blocks.count))
        for (type, payload) in blocks {
            out += bigEndian(type) + bigEndian(UInt32(payload.count)) + payload
        }
        return Data(out)
    }

    private static func utf16Name(_ name: String) -> [UInt8] {
        let units = Array(name.utf16) + [0]
        var bytes = bigEndian(UInt16(units.count))
        for unit in units {
            bytes += bigEndian(unit)
        }
        return bytes
    }

    private static func bigEndian<T: FixedWidthInteger>(_ value: T) -> [UInt8] {
        withUnsafeBytes(of: value.bigEndian) { Array($0) }
    }

    // MARK: - Reader

    private struct Reader {
        let bytes: [UInt8]
        var offset = 0
        var count: Int { bytes.count }

        init(bytes: [UInt8]) {
            self.bytes = bytes
        }

        mutating func bytes(_ n: Int) throws -> [UInt8] {
            guard offset + n <= bytes.count else { throw ReadError.truncated }
            defer { offset += n }
            return Array(bytes[offset..<(offset + n)])
        }

        mutating func u16() throws -> UInt16 {
            let b = try bytes(2)
            return UInt16(b[0]) << 8 | UInt16(b[1])
        }

        mutating func u32() throws -> UInt32 {
            let b = try bytes(4)
            return b.reduce(0) { $0 << 8 | UInt32($1) }
        }

        mutating func f32() throws -> Double {
            Double(Float32(bitPattern: try u32()))
        }

        mutating func utf16Name() throws -> String {
            let length = Int(try u16())
            var units: [UInt16] = []
            for _ in 0..<length {
                units.append(try u16())
            }
            if units.last == 0 { units.removeLast() }
            return String(decoding: units, as: UTF16.self)
        }
    }
}
