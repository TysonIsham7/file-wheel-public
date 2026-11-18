import CoreGraphics
import XCTest
@testable import FileWheelKit

final class Phase1StillTests: XCTestCase {
    func testPhase1StillsStayOutOfThePhase2ListAndEnterTheWheel() {
        XCTAssertEqual(ConversionCatalog.phase1StillEntries.count, 30)
        XCTAssertEqual(ConversionCatalog.entries.count, 140)
        XCTAssertNil(ConversionCatalog.entries.first { $0.source == "jpg" && $0.target == "png" })
        XCTAssertNotNil(ConversionCatalog.phase1StillEntries.first { $0.source == "jpg" && $0.target == "png" })
        XCTAssertTrue(ConversionCatalog.phase1StillEntries.allSatisfy { $0.engine == .imageIOThenFFmpeg })
        XCTAssertTrue(ConversionCatalog.phase1StillEntries.allSatisfy { $0.source != $0.target })

        let offer = ConversionCatalog.offer(
            files: [SourceFile(fileExtension: "png")],
            capabilities: .missing,
            imageIO: ImageIOCapabilities()
        )
        XCTAssertEqual(
            offer.wedges.map(\.entry.target).filter { ConversionCatalog.phase1ImageIDs.contains($0) },
            ["jpg", "webp", "heic", "tif", "gif"]
        )
        XCTAssertNil(offer.message)
    }

    func testTenPngsShareOneImageOfferAndMixedKindsDoNot() {
        let caps = FFmpegCapabilities.missing
        let imageIO = ImageIOCapabilities()
        let one = ConversionCatalog.offer(
            files: [SourceFile(fileExtension: "png")],
            capabilities: caps,
            imageIO: imageIO
        )
        let ten = ConversionCatalog.offer(
            files: (1...10).map { _ in SourceFile(fileExtension: "png") },
            capabilities: caps,
            imageIO: imageIO
        )
        XCTAssertEqual(ten.wedges.map(\.entry.id), one.wedges.map(\.entry.id))
        XCTAssertFalse(ten.wedges.isEmpty)

        let mixed = ConversionCatalog.offer(
            files: [SourceFile(fileExtension: "png"), SourceFile(fileExtension: "mp4")],
            capabilities: caps,
            imageIO: imageIO
        )
        XCTAssertEqual(mixed.message, "Same kind of file required")
        XCTAssertTrue(mixed.wedges.isEmpty)
    }

    func testAboutCountsPhase1PairsWhenAsked() {
        let report = CapabilityReportBuilder.make(
            entries: ConversionCatalog.wheelEntries,
            capabilities: .missing,
            imageIO: ImageIOCapabilities()
        )
        XCTAssertGreaterThan(report.catalogPairCount, ConversionCatalog.entries.count)
        XCTAssertTrue(report.aboutText.contains("Supported conversions"))
    }

    func testPNGToJPEGLeavesTheSourceAndWritesASibling() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let png = directory.appendingPathComponent("shot.png")
        try writePNG(to: png)
        let original = try Data(contentsOf: png)
        let entry = try XCTUnwrap(ConversionCatalog.phase1StillEntries.first { $0.source == "png" && $0.target == "jpg" })
        let runner = ConversionJobRunner(router: EngineRouter(ffmpegURL: nil, imageIO: .current()))
        let result = await runner.run(ConversionRequest(inputs: [png], entry: entry, destinationDirectory: directory))
        XCTAssertEqual(result.failures.map(\.reason), [], result.failures.map(\.reason).joined(separator: " | "))
        XCTAssertEqual(result.outputs.first?.lastPathComponent, "shot.jpg")
        XCTAssertEqual(try Data(contentsOf: png), original)
        let jpeg = try Data(contentsOf: try XCTUnwrap(result.outputs.first))
        XCTAssertGreaterThan(jpeg.count, 0)
    }

    func testTenPNGsWriteTenJPEGs() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let inputs = (1...10).map { directory.appendingPathComponent("frame \($0).png") }
        for url in inputs {
            try writePNG(to: url)
        }
        let entry = try XCTUnwrap(ConversionCatalog.phase1StillEntries.first { $0.source == "png" && $0.target == "jpg" })
        let runner = ConversionJobRunner(router: EngineRouter(ffmpegURL: nil, imageIO: .current()))
        let result = await runner.run(ConversionRequest(inputs: inputs, entry: entry, destinationDirectory: directory))
        XCTAssertEqual(result.failures.map(\.reason), [], result.failures.map(\.reason).joined(separator: " | "))
        XCTAssertEqual(result.outputs.count, 10)
        XCTAssertEqual(Set(result.outputs.map(\.pathExtension)), ["jpg"])
        for url in inputs {
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        }
    }

    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("filewheel-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func writePNG(to url: URL) throws {
        let width = 8
        let height = 8
        let bytes = [UInt8](repeating: 255, count: width * height * 4)
        let image = bytes.withUnsafeBufferPointer { pointer -> CGImage? in
            guard let context = CGContext(
                data: UnsafeMutableRawPointer(mutating: pointer.baseAddress),
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return nil }
            return context.makeImage()
        }
        guard let image else {
            XCTFail("could not draw")
            return
        }
        try StillImage.write(image, to: url, type: .png, quality: nil)
    }
}
