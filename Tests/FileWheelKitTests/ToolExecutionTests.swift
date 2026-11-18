import XCTest
@testable import FileWheelKit

final class ToolExecutionTests: XCTestCase {
    private var directory: URL!
    private var environment: ToolEnvironment!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("filewheel-exec-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        environment = ToolEnvironment.system()
        try XCTSkipIf(environment.ffmpeg == nil, "ffmpeg is required for tool fixtures")
    }

    override func tearDownWithError() throws {
        if let directory {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    func testEachToolCompletesOnAFixture() throws {
        let image = try makeImage(name: "Photo.png")
        let secondImage = try makeImage(name: "Other.png", color: "blue")
        let video = try makeVideo(name: "Clip.mp4")
        let videoB = try makeVideo(name: "ClipB.mp4")
        let audio = try makeAudio(name: "Tone.wav")
        let pdf = try makePDF(name: "Pages.pdf")
        let pdfB = try makePDF(name: "More.pdf", text: "SECOND")
        let zip = try makeZip(name: "Bundle.zip")

        try run(.compress, [image], .compress(CompressParameters(mode: .quality(0.8), videoCodec: .h264, maxDimension: 1080)))
        try run(.cropImage, [image], .cropImage(CropImageParameters(rect: FWRect(x: 0, y: 0, width: 16, height: 16))))
        try run(.adjustImage, [image], .adjustImage(AdjustImageParameters(exposure: 0.2, contrast: 1.1, saturation: 1.1, sharpness: 0.2, rotation: 90, flipHorizontal: true, flipVertical: false)))
        try run(.annotate, [image], .annotate(AnnotateParameters(marks: [.text("Note", at: FWPoint(x: 2, y: 2), size: 14), .rectangle(FWRect(x: 1, y: 1, width: 10, height: 8), width: 1)])))
        try run(.redact, [image], .redact(RedactParameters(boxes: [RedactBox(pageIndex: 0, rect: FWRect(x: 0, y: 0, width: 8, height: 8))])))
        try run(.trimVideo, [video], .trimVideo(TrimParameters(start: 0, end: 0.2)))
        try run(.cropVideo, [video], .cropVideo(CropVideoParameters(rect: FWRect(x: 0, y: 0, width: 16, height: 16))))
        try run(.speed, [video], .speed(SpeedParameters(rate: .preset(2))))
        try run(.splitVideo, [video], .splitVideo(SplitVideoParameters(mode: .equalParts(2))), minimumOutputs: 2)
        try run(.joinVideos, [video, videoB], .joinVideos(OrderedInputs(files: [input(video, "mp4", .video), input(videoB, "mp4", .video)])))
        try run(.snapshots, [video], .snapshots(SnapshotParameters(mode: .count(2))), minimumOutputs: 2)
        try run(.normalizeAudio, [audio], .normalize)
        try run(.trimAudio, [audio], .trimAudio(TrimParameters(start: 0, end: 0.2)))
        var speechEnvironment = environment!
        speechEnvironment.speech = FailingSpeechFinder()
        try run(.bleep, [audio], .bleep(BleepParameters(ranges: [TimeRange(start: 0.05, end: 0.15)], word: "nope")), environment: speechEnvironment)
        try run(.channels, [audio], .channels(.mono))
        try run(.editMetadata, [image], .editMetadata(MetadataEdit(title: "Title", author: "Ada", description: "A photo", creationDate: "2026:10:02 12:00:00", gps: .set(latitude: 1, longitude: 2))))
        let gpsImage = try makeJPEGWithGPS(name: "Located.jpg")
        let original = try Data(contentsOf: gpsImage)
        let stripped = try run(.stripMetadata, [gpsImage], .stripMetadata)
        let strippedData = try Data(contentsOf: try XCTUnwrap(stripped.outputs.first))
        XCTAssertNil(JPEGMetadata.gps(in: strippedData))
        XCTAssertEqual(try Data(contentsOf: gpsImage), original)
        try run(.mergePDFs, [pdf, pdfB], .mergePDFs(OrderedInputs(files: [input(pdf, "pdf", .pdf), input(pdfB, "pdf", .pdf)])))
        let split = try run(.splitPDF, [pdf], .splitPDF(SplitPDFParameters(mode: .eachPage)), minimumOutputs: 2)
        XCTAssertEqual(split.outputs.count, 2)
        try run(.reorganizePDF, [pdf], .reorganizePDF(ReorganizeParameters(pages: [PDFPageEdit(id: 1), PDFPageEdit(id: 0, rotation: 90)])))
        try run(.imagesToPDF, [image, secondImage], .imagesToPDF(ImagesToPDFParameters(mode: .fit)))
        try run(.collage, [image, secondImage], .collage(CollageParameters()))
        var qrEnvironment = environment!
        qrEnvironment.qr = FixedQRDetector(codes: ["https://example.test/filewheel"])
        let qr = try run(.readQR, [image], .readQR(ReadQRParameters(saveAsText: false)), environment: qrEnvironment)
        XCTAssertTrue(qr.outputs.isEmpty)
        XCTAssertEqual(qr.qrCodes, ["https://example.test/filewheel"])
        let saved = try run(.readQR, [image], .readQR(ReadQRParameters(saveAsText: true)), environment: qrEnvironment)
        XCTAssertEqual(saved.outputs.count, 1)
        try run(.extractArchive, [zip], .extractArchive)
        try run(.packArchive, [image, secondImage], .packArchive(PackParameters(format: .zip)))
        XCTAssertThrowsError(try run(.packArchive, [image, secondImage], .packArchive(PackParameters(format: .gz))))

        var ocrEnvironment = environment!
        ocrEnvironment.textRecognizer = FixedTextRecognizer(words: [RecognizedWord(text: "SCANNED", rect: FWRect(x: 2, y: 2, width: 20, height: 8))])
        let ocr = try run(.ocrPDF, [image], .ocrPDF(OCRParameters()), environment: ocrEnvironment)
        XCTAssertTrue(ocr.outputs[0].lastPathComponent.contains("-ocr"))
        XCTAssertTrue(try SimplePDF.read(Data(contentsOf: ocr.outputs[0])).extractableText().contains("SCANNED"))
        let placement = SignatureTransform.placing(click: FWPoint(x: 200, y: 200), baseSize: FWSize(width: 120, height: 40), page: PageSize.usLetter)
        let signed = try run(.signPDF, [pdf], .signPDF(SignPDFParameters(imageJPEG: Data([0xFF, 0xD8, 0xFF, 0xD9]), pixelWidth: 1, pixelHeight: 1, placement: placement, text: "Initial", date: "2026-01-15")))
        XCTAssertTrue(signed.outputs[0].lastPathComponent.contains("-signed"))
        let protected = try run(.protectPDF, [pdf], .protectPDF(ProtectPDFParameters(password: "open-pass", confirm: "open-pass", allowPrinting: false, allowCopying: false)))
        XCTAssertTrue(protected.outputs[0].lastPathComponent.contains("-protected"))
        let unlocked = try run(.protectPDF, [protected.outputs[0]], .unlockPDF(UnlockPDFParameters(password: "open-pass")))
        XCTAssertTrue(unlocked.outputs[0].lastPathComponent.contains("-unlocked"))
    }

    func testPDFRedactToolRemovesExtractableText() throws {
        let pdf = try makePDF(name: "Secret.pdf")
        let outcome = try run(.redact, [pdf], .redact(RedactParameters(boxes: [RedactBox(pageIndex: 0, rect: FWRect(x: 60, y: 60, width: 180, height: 40))])))
        let edited = try SimplePDF.read(Data(contentsOf: try XCTUnwrap(outcome.outputs.first)))
        XCTAssertFalse(edited.extractableText().contains("SECRET"))
        XCTAssertTrue(edited.extractableText().contains("KEEP"))
        let source = try SimplePDF.read(Data(contentsOf: pdf))
        XCTAssertTrue(source.extractableText().contains("SECRET"))
    }

    func testCompressToSizeOnAJPEG() throws {
        let image = try makeNoiseJPEG(name: "Noise.jpg")
        let outcome = try run(.compress, [image], .compress(CompressParameters(mode: .target(bytes: 2500), videoCodec: .h264, maxDimension: 1080)))
        let output = try Data(contentsOf: try XCTUnwrap(outcome.outputs.first))
        if outcome.metCompressTarget == true {
            XCTAssertLessThanOrEqual(output.count, 2500)
        } else {
            XCTAssertTrue(outcome.message?.contains("Could not get under the target size") == true)
        }
        XCTAssertNotEqual(try Data(contentsOf: image), output)
    }

    func testCancelMidFFmpegLeavesNoDestination() throws {
        let ffmpeg = try XCTUnwrap(environment.ffmpeg)
        let destination = directory.appendingPathComponent("cancelled.mp4")
        let flag = CancellationFlag()
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.25) {
            flag.cancel()
        }
        XCTAssertThrowsError(try AtomicFileWrite.commit(destination: destination) { temp in
            try FFmpegRun.run(
                ffmpeg,
                arguments: ["-hide_banner", "-y", "-f", "lavfi", "-i", "testsrc=size=64x64:rate=30", "-t", "30", temp.path],
                runner: environment.runner,
                cancellation: flag
            )
        })
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertFalse(leftovers.contains { $0.contains("cancelled") })
    }

    @discardableResult
    private func run(_ tool: ToolID, _ urls: [URL], _ parameters: ToolParameters, environment: ToolEnvironment? = nil, minimumOutputs: Int = 1) throws -> ToolRunOutcome {
        let files = urls.map { MediaClassifier.classify($0) }
        let before = try urls.map { try Data(contentsOf: $0) }
        let outcome: ToolRunOutcome
        do {
            outcome = try ToolExecutor.run(
                ToolRunRequest(tool: tool, files: files, parameters: parameters, settings: .default),
                environment: environment ?? self.environment
            )
        } catch let error as ToolError {
            throw ToolError.message("\(tool.title): \(error.message)")
        }
        if tool != .readQR || (outcome.qrCodes.isEmpty == false && minimumOutputs == 1 && !outcome.outputs.isEmpty) {
            if tool != .readQR {
                XCTAssertGreaterThanOrEqual(outcome.outputs.count, minimumOutputs, tool.title)
            }
        }
        if tool == .readQR && outcome.outputs.isEmpty {
            XCTAssertTrue(outcome.qrCodes.isEmpty || parameters == .readQR(ReadQRParameters(saveAsText: false)))
        }
        let after = try urls.map { try Data(contentsOf: $0) }
        XCTAssertEqual(before, after, "\(tool.title) modified the source")
        for output in outcome.outputs {
            XCTAssertTrue(FileManager.default.fileExists(atPath: output.path), output.path)
            XCTAssertFalse(urls.contains(output))
        }
        return outcome
    }

    private func input(_ url: URL, _ ext: String, _ kind: MediaKind) -> FileInput {
        FileInput(url: url, normalizedExtension: ext, kind: kind, isDirectory: false)
    }

    private func makeImage(name: String, color: String = "red") throws -> URL {
        let url = directory.appendingPathComponent(name)
        try ffmpeg(["-f", "lavfi", "-i", "color=c=\(color):s=32x32", "-frames:v", "1", url.path])
        return url
    }

    private func makeNoiseJPEG(name: String) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try ffmpeg(["-f", "lavfi", "-i", "testsrc=size=128x128:rate=1", "-frames:v", "1", "-q:v", "2", url.path])
        return url
    }

    private func makeJPEGWithGPS(name: String) throws -> URL {
        let url = try makeImage(name: name, color: "green")
        let tagged = JPEGMetadata.injectGPS(try Data(contentsOf: url), gps: GPSFix(latitude: 37.7, longitude: -122.4))
        try tagged.write(to: url)
        return url
    }

    private func makeVideo(name: String) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try ffmpeg([
            "-f", "lavfi", "-i", "color=c=red:s=32x32:d=0.6",
            "-f", "lavfi", "-i", "sine=frequency=440:duration=0.6",
            "-shortest", "-c:v", "libx264", "-pix_fmt", "yuv420p", "-c:a", "aac",
            url.path
        ])
        return url
    }

    private func makeAudio(name: String) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try ffmpeg(["-f", "lavfi", "-i", "sine=frequency=440:duration=0.4", url.path])
        return url
    }

    private func makePDF(name: String, text: String = "SECRET") throws -> URL {
        let document = SimplePDF(pages: [
            SimplePDF.Page(texts: [SimplePDF.TextObject(text: text, x: 72, y: 72), SimplePDF.TextObject(text: "KEEP", x: 72, y: 400)]),
            SimplePDF.Page(texts: [SimplePDF.TextObject(text: "PAGE2", x: 72, y: 72)])
        ])
        let url = directory.appendingPathComponent(name)
        try document.data().write(to: url)
        return url
    }

    private func makeZip(name: String) throws -> URL {
        let payload = directory.appendingPathComponent("note.txt")
        try Data("hello".utf8).write(to: payload)
        let url = directory.appendingPathComponent(name)
        let zip = URL(fileURLWithPath: "/usr/bin/zip")
        let result = try FoundationCommandRunner().run(executable: zip, arguments: ["-q", url.path, "note.txt"], currentDirectory: directory, standardInput: nil, cancellation: nil)
        XCTAssertEqual(result.status, 0, result.stderrText)
        return url
    }

    private func ffmpeg(_ arguments: [String]) throws {
        let ffmpeg = try XCTUnwrap(environment.ffmpeg)
        try FFmpegRun.run(ffmpeg, arguments: ["-hide_banner", "-y"] + arguments, runner: environment.runner, cancellation: nil)
    }
}
