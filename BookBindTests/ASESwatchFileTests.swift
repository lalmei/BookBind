import XCTest
@testable import BookBind

final class ASESwatchFileTests: XCTestCase {
    func testRoundTripPreservesNamesAndColours() throws {
        let swatches = [
            Swatch(name: "Oxblood cloth", color: CodableColor(red: 0.42, green: 0.12, blue: 0.13)),
            Swatch(name: "Gold föil ✦", color: CodableColor(red: 0.83, green: 0.67, blue: 0.29))
        ]
        let data = ASESwatchFile.write(swatches, groupName: "Bindery")
        XCTAssertEqual(Array(data.prefix(4)), Array("ASEF".utf8))

        let read = try ASESwatchFile.read(data)
        XCTAssertEqual(read.map(\.name), swatches.map(\.name), "groups are flattened, unicode survives")
        for (a, b) in zip(read, swatches) {
            XCTAssertEqual(a.color.red, b.color.red, accuracy: 1e-6)
            XCTAssertEqual(a.color.green, b.color.green, accuracy: 1e-6)
            XCTAssertEqual(a.color.blue, b.color.blue, accuracy: 1e-6)
        }
    }

    /// Builds a block-level file by hand to cover the models Adobe apps export.
    private func file(_ blocks: [(UInt16, [UInt8])]) -> Data {
        func be<T: FixedWidthInteger>(_ v: T) -> [UInt8] { withUnsafeBytes(of: v.bigEndian) { Array($0) } }
        var out = Array("ASEF".utf8) + be(UInt16(1)) + be(UInt16(0)) + be(UInt32(blocks.count))
        for (type, payload) in blocks { out += be(type) + be(UInt32(payload.count)) + payload }
        return Data(out)
    }

    private func colour(_ name: String, _ model: String, _ values: [Float32]) -> (UInt16, [UInt8]) {
        func be<T: FixedWidthInteger>(_ v: T) -> [UInt8] { withUnsafeBytes(of: v.bigEndian) { Array($0) } }
        let units = Array(name.utf16) + [0]
        var payload = be(UInt16(units.count)) + units.flatMap { be($0) } + Array(model.utf8)
        payload += values.flatMap { be($0.bitPattern) } + be(UInt16(0))
        return (0x0001, payload)
    }

    func testReadsCMYKGrayAndLab() throws {
        let data = file([
            (0xC001, [0, 2, 0, 0x41, 0, 0]), // group "A"
            colour("Process Cyan", "CMYK", [1, 0, 0, 0]),
            colour("50% Grey", "Gray", [0.5]),
            colour("Lab white", "LAB ", [1, 0, 0]),
            (0xC002, [])
        ])
        let swatches = try ASESwatchFile.read(data)
        XCTAssertEqual(swatches.map(\.name), ["Process Cyan", "50% Grey", "Lab white"])
        XCTAssertEqual(swatches[0].color, CodableColor(red: 0, green: 1, blue: 1))
        XCTAssertEqual(swatches[1].color.red, 0.5, accuracy: 1e-6)
        XCTAssertEqual(swatches[2].color.red, 1, accuracy: 0.01)
        XCTAssertEqual(swatches[2].color.green, 1, accuracy: 0.01)
        XCTAssertEqual(swatches[2].color.blue, 1, accuracy: 0.01)
    }

    func testRejectsOtherFilesAndTruncation() {
        XCTAssertThrowsError(try ASESwatchFile.read(Data("%PDF-1.7".utf8)))
        let good = ASESwatchFile.write([Swatch(name: "x", color: CodableColor(red: 1, green: 0, blue: 0))])
        XCTAssertThrowsError(try ASESwatchFile.read(good.prefix(good.count - 3)))
    }

    @MainActor
    func testStoreImportsWithoutDuplicates() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "ASESwatchFileTests-\(UUID().uuidString)"))
        let store = SwatchStore(defaults: defaults)
        XCTAssertEqual(store.swatches, SwatchStore.starter)

        let file = ASESwatchFile.write([
            SwatchStore.starter[0],
            Swatch(name: "Teal", color: CodableColor(red: 0, green: 0.5, blue: 0.5))
        ])
        XCTAssertEqual(try store.importASE(file), 1, "existing colour skipped")
        XCTAssertEqual(SwatchStore(defaults: defaults).swatches.last?.name, "Teal", "persisted")
    }
}
