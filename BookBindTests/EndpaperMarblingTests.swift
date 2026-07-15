import PDFKit
import XCTest
@testable import BookBind

final class EndpaperMarblingTests: XCTestCase {
    func testMarbledPaperSpecRoundTrip() throws {
        var job = BindingJob()
        var spec = MarbledPaperSpec(style: .peacock, seed: 12345)
        spec.palette = MarbledPaperPalette.venetianRed.colors
        spec.background = MarbledPaperPalette.venetianRed.background
        spec.scale = 1.25
        spec.flowDegrees = 30
        spec.turbulence = 0.4
        spec.density = 0.7
        spec.colorBalance = 0.6
        job.endpapers.front.mode = .marbled
        job.endpapers.front.marbling = spec

        let data = try JSONEncoder().encode(job)
        let restored = try JSONDecoder().decode(BindingJob.self, from: data)
        XCTAssertEqual(restored.endpapers.front.mode, .marbled)
        XCTAssertEqual(restored.endpapers.front.marbling, spec)
    }

    func testLegacyEndpaperFieldsMigrateIntoDesign() throws {
        let json = """
        {
          "bindingStyle": "Section-sewn",
          "signatureSize": 16,
          "frontEndpapers": 2,
          "backEndpapers": 2,
          "frontEndpaperColor": "Sage",
          "backEndpaperColor": "Blank"
        }
        """.data(using: .utf8)!
        let job = try JSONDecoder().decode(BindingJob.self, from: json)
        XCTAssertEqual(job.endpapers.front.solidColor, .sage)
        XCTAssertEqual(job.endpapers.front.mode, .solidColor)
        XCTAssertEqual(job.endpapers.back.mode, .blank)
    }

    func testDeterministicMarblingSameSeedSamePixels() {
        let spec = MarbledPaperSpec(style: .nonpareil, seed: 99)
        let a = MarbledPaperGenerator.render(spec: spec, width: 64, height: 96)
        let b = MarbledPaperGenerator.render(spec: spec, width: 64, height: 96)
        XCTAssertNotNil(a)
        XCTAssertNotNil(b)
        XCTAssertEqual(pixelChecksum(a!), pixelChecksum(b!))
    }

    func testRegenerateChangesSeedButKeepsPalette() {
        var spec = MarbledPaperSpec(style: .stone, seed: 10)
        let palette = spec.palette
        let before = spec.seed
        spec.regenerateVariation()
        XCTAssertNotEqual(spec.seed, before)
        XCTAssertEqual(spec.palette, palette)
    }

    func testMarbledEndpapersAppearInBookBlock() throws {
        let size = CGSize(width: 200, height: 300)
        let content = PDFDocument()
        for _ in 0..<4 {
            content.insert(PDFDocumentService.makeBlankPage(size: size), at: content.pageCount)
        }
        var front = EndpaperFaceDesign(mode: .marbled)
        front.marbling = MarbledPaperSpec(style: .combed, seed: 7)
        let block = PDFDocumentService.buildBookBlock(
            from: content,
            frontEndpapers: 2,
            backEndpapers: 0,
            padPages: 0,
            targetPageSize: size,
            frontEndpaperDesign: front,
            backEndpaperDesign: EndpaperFaceDesign()
        )
        XCTAssertEqual(block.pageCount, 6)
        let page = try XCTUnwrap(block.page(at: 0))
        let bounds = page.bounds(for: .mediaBox)
        XCTAssertEqual(bounds.width, 200, accuracy: 0.5)
        XCTAssertEqual(bounds.height, 300, accuracy: 0.5)
    }

    func testDifferentSizesRenderFromSameParams() {
        let spec = MarbledPaperSpec(style: .stone, seed: 5)
        let small = MarbledPaperGenerator.render(spec: spec, width: 32, height: 48)
        let large = MarbledPaperGenerator.render(spec: spec, width: 96, height: 144)
        XCTAssertNotNil(small)
        XCTAssertNotNil(large)
        XCTAssertNotEqual(small!.width, large!.width)
    }

    private func pixelChecksum(_ image: CGImage) -> UInt64 {
        guard let data = image.dataProvider?.data else { return 0 }
        let length = CFDataGetLength(data)
        let ptr = CFDataGetBytePtr(data)!
        var hash: UInt64 = 14695981039346656037
        for i in 0..<length {
            hash ^= UInt64(ptr[i])
            hash &*= 1099511628211
        }
        return hash
    }
}
