import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import FileWheelKit

final class Phase2Tests: XCTestCase {
    func testAudioMatrixPrefersAVFoundationUntilAFmpegFormatIsInvolved() {
        let audio = ConversionCatalog.entries.filter { $0.kind == .audio }
        XCTAssertEqual(audio.count, 56)
        XCTAssertTrue(audio.allSatisfy { $0.source != $0.target })
        let ids = Set(audio.map(\.id))
        for source in ConversionCatalog.audioIDs {
            for target in ConversionCatalog.audioIDs where source != target {
                XCTAssertTrue(ids.contains("\(source)>\(target)"))
            }
        }
        XCTAssertEqual(entry("mp3", "m4a").engine, .avFoundation)
        XCTAssertEqual(entry("wav", "aiff").engine, .avFoundation)
        XCTAssertEqual(entry("m4a", "mp3").engine, .avFoundation)
        XCTAssertEqual(entry("flac", "mp3").engine, .ffmpeg)
        XCTAssertEqual(entry("mp3", "flac").engine, .ffmpeg)
        XCTAssertEqual(entry("ogg", "opus").engine, .ffmpeg)
        XCTAssertEqual(entry("wav", "wma").engine, .ffmpeg)
        XCTAssertEqual(entry("wma", "wav").engine, .ffmpeg)
    }

    func testVideoMatrixUsesAVFoundationOnlyForMP4AndMOV() {
        let video = ConversionCatalog.entries.filter { $0.kind == .video }
        XCTAssertEqual(video.count, 42)
        XCTAssertEqual(entry("mp4", "mov").engine, .avFoundation)
        XCTAssertEqual(entry("mov", "mp4").engine, .avFoundation)
        XCTAssertEqual(entry("mp4", "mkv").engine, .ffmpeg)
        XCTAssertEqual(entry("mkv", "mp4").engine, .ffmpeg)
        XCTAssertEqual(entry("webm", "avi").engine, .ffmpeg)
        XCTAssertEqual(entry("mp4", "gif").engine, .ffmpeg)
        XCTAssertEqual(entry("wmv", "gif").engine, .ffmpeg)
        XCTAssertEqual(entry("mp4", "mp3").engine, .avFoundation)
        XCTAssertEqual(entry("mov", "mp3").engine, .avFoundation)
        XCTAssertEqual(entry("mkv", "mp3").engine, .ffmpeg)
        XCTAssertEqual(entry("webm", "mp3").engine, .ffmpeg)
        XCTAssertFalse(video.contains { $0.source == $0.target })
        XCTAssertEqual(video.filter { $0.target == "gif" }.count, 6)
    }

    func testRemainingImagePairsLeavePhase1StillsToTheOtherBranch() {
        let images = ConversionCatalog.entries.filter { $0.kind == .image }
        XCTAssertEqual(images.count, 42)
        XCTAssertNil(ConversionCatalog.entries.first { $0.source == "jpg" && $0.target == "png" })
        XCTAssertEqual(entry("jpg", "avif").engine, .imageIOThenFFmpeg)
        XCTAssertEqual(entry("avif", "jpg").engine, .imageIOThenFFmpeg)
        XCTAssertEqual(entry("bmp", "png").engine, .imageIOThenFFmpeg)
        XCTAssertEqual(entry("png", "bmp").engine, .imageIOThenFFmpeg)
        XCTAssertEqual(entry("svg", "png").engine, .svgRasterize)
        XCTAssertEqual(entry("svg", "avif").engine, .svgRasterize)
        let wrapped = entry("png", "svg")
        XCTAssertEqual(wrapped.engine, .svgWrap)
        XCTAssertEqual(wrapped.label, "SVG (wrapped)")
        XCTAssertEqual(entry("heic", "svg").label, "SVG (wrapped)")
        XCTAssertNil(ConversionCatalog.entries.first { $0.source == "svg" && $0.target == "svg" })
        XCTAssertNil(ConversionCatalog.entries.first { $0.target == "pdf" || $0.target == "docx" })
        XCTAssertEqual(ConversionCatalog.entries.count, 140)
    }

    func testAliasesAndMixedDrags() {
        XCTAssertEqual(KnownFormats.canonical(extension: "JPEG")?.id, "jpg")
        XCTAssertEqual(KnownFormats.canonical(extension: "tiff")?.id, "tif")
        let caps = fullCapabilities()
        let mixed = ConversionCatalog.offer(
            files: [
                SourceFile(fileExtension: "png"),
                SourceFile(fileExtension: "mp4", hasAudio: true),
            ],
            capabilities: caps,
            imageIO: .current()
        )
        XCTAssertEqual(mixed.message, "Same kind of file required")
        XCTAssertTrue(mixed.wedges.isEmpty)

        let folder = ConversionCatalog.offer(
            files: [SourceFile(fileExtension: "zip", isDirectory: true)],
            capabilities: caps,
            imageIO: .current()
        )
        XCTAssertNil(folder.message)
        XCTAssertTrue(folder.wedges.isEmpty)
    }

    func testWMAEncodeHidesAndAboutListsTheGap() {
        var caps = fullCapabilities()
        caps.encoders.remove("wmav2")
        caps.encoders.remove("wmav1")
        let offer = ConversionCatalog.offer(
            files: [SourceFile(fileExtension: "mp3")],
            capabilities: caps,
            imageIO: fullImageIO()
        )
        let wma = offer.wedges.first { $0.entry.target == "wma" }
        XCTAssertEqual(wma?.state, .hidden)
        XCTAssertEqual(offer.wedges.first { $0.entry.target == "wav" }?.state, .enabled)
        XCTAssertEqual(offer.wedges.first { $0.entry.target == "flac" }?.state, .enabled)

        let report = CapabilityReportBuilder.make(
            capabilities: caps,
            imageIO: fullImageIO()
        )
        XCTAssertTrue(report.gaps.contains { $0.title == "WMA encode is unavailable" })
        XCTAssertTrue(report.aboutText.contains("WMA encode is unavailable"))
        XCTAssertTrue(report.livePairCount < report.catalogPairCount)
    }

    func testPinnedBuildShowsWMAWhenTheEncoderExists() {
        let caps = fullCapabilities()
        let offer = ConversionCatalog.offer(
            files: [SourceFile(fileExtension: "wav")],
            capabilities: caps,
            imageIO: fullImageIO()
        )
        XCTAssertEqual(offer.wedges.first { $0.entry.target == "wma" }?.state, .enabled)
        let report = CapabilityReportBuilder.make(
            capabilities: caps,
            imageIO: fullImageIO()
        )
        XCTAssertTrue(report.gaps.isEmpty)
        XCTAssertTrue(report.aboutText.contains("Gaps: none"))
    }

    func testVideoWithoutAudioDisablesMP3ExtractOnly() {
        let offer = ConversionCatalog.offer(
            files: [SourceFile(fileExtension: "mp4", hasAudio: false)],
            capabilities: fullCapabilities(),
            imageIO: fullImageIO()
        )
        XCTAssertEqual(offer.wedges.first { $0.entry.target == "mp3" }?.state, .disabled(reason: "No audio"))
        XCTAssertEqual(offer.wedges.first { $0.entry.target == "mov" }?.state, .enabled)
        XCTAssertEqual(offer.wedges.first { $0.entry.target == "gif" }?.state, .enabled)
    }

    func testMissingFFmpegHidesFFmpegWedgesAndKeepsAVFoundation() {
        let offer = ConversionCatalog.offer(
            files: [SourceFile(fileExtension: "mp4", hasAudio: true)],
            capabilities: .missing,
            imageIO: fullImageIO()
        )
        XCTAssertEqual(offer.wedges.first { $0.entry.target == "mov" }?.state, .enabled)
        XCTAssertEqual(offer.wedges.first { $0.entry.target == "mkv" }?.state, .hidden)
        XCTAssertEqual(offer.wedges.first { $0.entry.target == "gif" }?.state, .hidden)
        let report = CapabilityReportBuilder.make(
            capabilities: .missing,
            imageIO: fullImageIO()
        )
        XCTAssertTrue(report.gaps.contains { $0.title == "ffmpeg was not found" })
        XCTAssertFalse(report.gaps.contains { $0.title == "WMA encode is unavailable" })
    }

    func testFFmpegArgumentsAreAnArrayAndNeverAShellString() {
        let input = URL(fileURLWithPath: "/tmp/My Files/clip.mp4")
        let output = URL(fileURLWithPath: "/tmp/My Files/clip.gif")
        let task = FFmpegTask.gif(maxWidth: 720, fps: 12)
        let args = FFmpegCommand.arguments(input: input, output: output, task: task, progress: false)
        XCTAssertEqual(args.filter { $0 == input.path }.count, 1)
        XCTAssertEqual(args.last, output.path)
        XCTAssertFalse(args.contains("/bin/sh"))
        XCTAssertFalse(args.contains("/bin/bash"))
        XCTAssertFalse(args.contains("-c"))
        XCTAssertFalse(args.contains { $0.contains(" && ") || $0.contains("| ffmpeg") })
        XCTAssertTrue(args.contains { $0.contains("fps=12") && $0.contains("min(720\\,iw)") })

        let mkv = FFmpegCommand.task(entry: entry("mp4", "mkv"), options: ConversionOptions(videoCRF: 23, hardwareEncoder: false))
        if case .video(let codec, let extra, _, _, let edge, _) = mkv {
            XCTAssertEqual(codec, "libx264")
            XCTAssertEqual(extra, ["-preset", "medium", "-crf", "23"])
            XCTAssertEqual(edge, 1920)
        } else {
            XCTFail("expected a video task")
        }

        let hardware = FFmpegCommand.task(entry: entry("mkv", "mp4"), options: .specDefaults)
        if case .video(let codec, let extra, _, _, _, let fastStart) = hardware {
            XCTAssertEqual(codec, "h264_videotoolbox")
            XCTAssertTrue(extra.contains("8M"))
            XCTAssertTrue(fastStart)
        } else {
            XCTFail("expected videotoolbox")
        }

        let webm = FFmpegCommand.task(entry: entry("mp4", "webm"), options: .specDefaults)
        if case .video(let codec, _, let audio, _, _, _) = webm {
            XCTAssertEqual(codec, "libvpx-vp9")
            XCTAssertEqual(audio, "libopus")
        } else {
            XCTFail("expected webm")
        }
    }

    func testNamingNeverOverwritesTheSource() {
        let name = OutputNaming.uniqueName(
            base: "Photo",
            ext: "jpg",
            sourceFileName: "Photo.png",
            existingLowercased: ["photo.jpg", "photo 2.jpg"]
        )
        XCTAssertEqual(name, "Photo 3.jpg")
        let same = OutputNaming.uniqueName(
            base: "Photo",
            ext: "png",
            sourceFileName: "Photo.png",
            existingLowercased: []
        )
        XCTAssertEqual(same, "Photo 2.png")
    }

    func testDiagnosticsAndPin() {
        let stderr = """
        ffmpeg version 6.0
        Input #0, mov, from 'clip.mp4':
          Duration: 00:01:02.50, start: 0.000000
          Stream #0:0(und): Video: h264
        frame=  10 fps=0.0 q=0.0 size= 1kB time=00:00:01.00 bitrate= 1.0kbits/s speed=1.0x
        Error opening output file
        Conversion failed!
        """
        XCTAssertEqual(FFmpegDiagnostics.lastUsefulLine(stderr), "Conversion failed!")
        let streams = FFmpegDiagnostics.streams(fromStderr: stderr)
        XCTAssertTrue(streams.hasVideo)
        XCTAssertFalse(streams.hasAudio)
        XCTAssertEqual(streams.durationSeconds, 62.5)

        let encoders = """
         A..... = Audio
         A....D libmp3lame           libmp3lame MP3
         A....D wmav2                Windows Media Audio 2
        """
        let muxers = """
         D. = Demuxing supported
         .E = Muxing supported
          E mp3             MP3
          E asf             ASF
        """
        let parsed = FFmpegCapabilities.parse(
            versionOutput: "ffmpeg version 6.0 Copyright (c) 2000-2023\n",
            encodersOutput: encoders,
            muxersOutput: muxers
        )
        XCTAssertEqual(parsed.encoders, ["libmp3lame", "wmav2"])
        XCTAssertEqual(parsed.muxers, ["mp3", "asf"])
    }

    func testShellFlagIsRefusedBeforeAProcessStarts() async {
        do {
            _ = try await ProcessRunner.run(
                executable: URL(fileURLWithPath: "/bin/echo"),
                arguments: ["-c", "printf hi"],
                cancel: nil
            )
            XCTFail("expected a refusal")
        } catch let error as ConversionError {
            XCTAssertEqual(error, .failed("Refusing to invoke a shell"))
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    func testSVGWrapAndRasterizeAndBMP() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let png = directory.appendingPathComponent("Square.png")
        try writePNG(to: png, width: 4, height: 2)
        let router = EngineRouter(ffmpegURL: FFmpegLocator.resolve(), imageIO: .current())
        let cancel = ConversionCancel()
        let svg = directory.appendingPathComponent(".wrap.filewheel.svg")
        try await router.convert(
            EngineJob(
                source: png,
                tempOutput: svg,
                entry: entry("png", "svg"),
                cancel: cancel
            )
        )
        let wrapped = try String(contentsOf: svg, encoding: .utf8)
        XCTAssertTrue(wrapped.contains("<svg"))
        XCTAssertTrue(wrapped.contains("data:image/png;base64,"))
        XCTAssertFalse(wrapped.contains("<path"))

        let bmpJob = EngineJob(
            source: png,
            tempOutput: directory.appendingPathComponent(".out.filewheel.bmp"),
            entry: entry("png", "bmp"),
            cancel: cancel
        )
        try await router.convert(bmpJob)
        let bmp = StillProbe.image(at: bmpJob.tempOutput)
        XCTAssertEqual(bmp?.width, 4)
        XCTAssertEqual(bmp?.height, 2)

        let svgSource = directory.appendingPathComponent("Card.svg")
        try """
        <?xml version="1.0" encoding="UTF-8"?>
        <svg xmlns="http://www.w3.org/2000/svg" width="72" height="36">
          <rect width="72" height="36" fill="red"/>
        </svg>
        """.write(to: svgSource, atomically: true, encoding: .utf8)
        let renderedURL = directory.appendingPathComponent(".card.filewheel.png")
        try await router.convert(
            EngineJob(
                source: svgSource,
                tempOutput: renderedURL,
                entry: entry("svg", "png"),
                options: ConversionOptions(svgRasterDPI: 144),
                cancel: cancel
            )
        )
        let rendered = StillProbe.image(at: renderedURL)
        XCTAssertEqual(rendered?.width, 144)
        XCTAssertEqual(rendered?.height, 72)
    }

    func testSystemFFmpegConvertsWhenInstalled() async throws {
        guard let ffmpeg = FFmpegLocator.resolve() else {
            throw XCTSkip("ffmpeg is not installed. Install it with: brew install ffmpeg unar")
        }
        let session = await FFmpegSession.launch()
        XCTAssertEqual(session.url?.standardizedFileURL.path, ffmpeg.standardizedFileURL.path)
        XCTAssertTrue(session.capabilities.hasEncoder("wmav2"))
        XCTAssertTrue(session.capabilities.hasEncoder("libmp3lame"))
        XCTAssertTrue(session.capabilities.hasEncoder("libvpx-vp9"))
        XCTAssertTrue(session.capabilities.hasEncoder("libaom-av1"))
        XCTAssertTrue(session.capabilities.hasMuxer("matroska"))
        XCTAssertFalse(session.report.gaps.contains { $0.title == "WMA encode is unavailable" })
        XCTAssertFalse(session.report.aboutText.contains("Pinned ffmpeg"))

        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let wav = directory.appendingPathComponent("tone.wav")
        try await runFFmpeg(ffmpeg, [
            "-hide_banner", "-nostdin", "-y",
            "-f", "lavfi", "-i", "sine=frequency=440:duration=0.4",
            "-c:a", "pcm_s16le", wav.path,
        ])
        let mp4 = directory.appendingPathComponent("tiny.mp4")
        try await runFFmpeg(ffmpeg, [
            "-hide_banner", "-nostdin", "-y",
            "-f", "lavfi", "-i", "testsrc=size=64x48:rate=8:duration=0.5",
            "-f", "lavfi", "-i", "sine=frequency=440:duration=0.5",
            "-shortest", "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "28",
            "-c:a", "aac", mp4.path,
        ])
        let silent = directory.appendingPathComponent("silent.mp4")
        try await runFFmpeg(ffmpeg, [
            "-hide_banner", "-nostdin", "-y",
            "-f", "lavfi", "-i", "testsrc=size=64x48:rate=8:duration=0.3",
            "-an", "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "28", silent.path,
        ])

        let runner = ConversionJobRunner(router: EngineRouter(ffmpegURL: ffmpeg, imageIO: .current()))
        let aiff = await runner.run(ConversionRequest(inputs: [wav], entry: entry("wav", "aiff"), destinationDirectory: directory))
        XCTAssertEqual(aiff.failures, [])
        XCTAssertEqual(aiff.outputs.count, 1)
        XCTAssertEqual(aiff.outputs.first?.pathExtension, "aiff")

        let flac = await runner.run(ConversionRequest(inputs: [wav], entry: entry("wav", "flac"), destinationDirectory: directory))
        XCTAssertEqual(flac.failures, [])
        XCTAssertEqual(flac.outputs.first?.lastPathComponent, "tone.flac")

        let gif = await runner.run(ConversionRequest(inputs: [mp4], entry: entry("mp4", "gif"), destinationDirectory: directory))
        XCTAssertEqual(gif.failures.map(\.reason), [], gif.failures.map(\.reason).joined(separator: " | "))
        let gifURL = try XCTUnwrap(gif.outputs.first)
        let gifSize = try FileManager.default.attributesOfItem(atPath: gifURL.path)[.size] as? Int ?? 0
        XCTAssertGreaterThan(gifSize, 0)

        let mov = await runner.run(ConversionRequest(inputs: [mp4], entry: entry("mp4", "mov"), destinationDirectory: directory))
        XCTAssertEqual(mov.failures.map(\.reason), [], mov.failures.map(\.reason).joined(separator: " | "))
        XCTAssertEqual(mov.outputs.first?.pathExtension, "mov")

        let silentFacts = await SourceProbe.inspect(url: silent, ffmpegURL: ffmpeg)
        XCTAssertEqual(silentFacts.hasAudio, false)
        let silentOffer = ConversionCatalog.offer(
            files: [silentFacts],
            capabilities: session.capabilities,
            imageIO: .current()
        )
        XCTAssertEqual(silentOffer.wedges.first { $0.entry.target == "mp3" }?.state, .disabled(reason: "No audio"))

        let png = directory.appendingPathComponent("dot.png")
        try writePNG(to: png, width: 8, height: 8)
        let avif = await runner.run(ConversionRequest(inputs: [png], entry: entry("png", "avif"), destinationDirectory: directory))
        XCTAssertEqual(avif.failures.map(\.reason), [], avif.failures.map(\.reason).joined(separator: " | "))
        let avifSize = try FileManager.default.attributesOfItem(atPath: try XCTUnwrap(avif.outputs.first).path)[.size] as? Int ?? 0
        XCTAssertGreaterThan(avifSize, 0)

        let original = try Data(contentsOf: wav)
        XCTAssertEqual(try Data(contentsOf: wav), original)
    }

    func testCancelLeavesNoDestination() async throws {
        guard let ffmpeg = FFmpegLocator.resolve() else {
            throw XCTSkip("ffmpeg is not installed. Install it with: brew install ffmpeg unar")
        }
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("long.mp4")
        try await runFFmpeg(ffmpeg, [
            "-hide_banner", "-nostdin", "-y",
            "-f", "lavfi", "-i", "testsrc=size=320x240:rate=30:duration=8",
            "-f", "lavfi", "-i", "sine=frequency=440:duration=8",
            "-shortest", "-c:v", "libx264", "-pix_fmt", "yuv420p", "-preset", "ultrafast",
            "-c:a", "aac", source.path,
        ])
        let cancel = ConversionCancel()
        let runner = ConversionJobRunner(router: EngineRouter(ffmpegURL: ffmpeg, imageIO: .current()))
        let task = Task {
            await runner.run(
                ConversionRequest(inputs: [source], entry: entry("mp4", "webm"), destinationDirectory: directory),
                cancel: cancel
            )
        }
        try await Task.sleep(nanoseconds: 200_000_000)
        cancel.cancel()
        let result = await task.value
        XCTAssertTrue(result.cancelled)
        XCTAssertTrue(result.outputs.isEmpty)
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertFalse(names.contains { $0.hasSuffix(".webm") })
        XCTAssertFalse(names.contains { $0.contains(".filewheel.") })
    }

    private func entry(_ source: String, _ target: String) -> CatalogEntry {
        guard let found = ConversionCatalog.entries.first(where: { $0.source == source && $0.target == target }) else {
            XCTFail("missing \(source)>\(target)")
            return CatalogEntry(source: source, target: target, kind: .audio, label: target, engine: .ffmpeg)
        }
        return found
    }

    private func fullImageIO() -> ImageIOCapabilities {
        ImageIOCapabilities(
            encodesJPEG: true,
            encodesPNG: true,
            encodesGIF: true,
            encodesTIFF: true,
            encodesBMP: true,
            encodesHEIC: true,
            encodesWebP: true,
            encodesAVIF: true
        )
    }

    private func fullCapabilities() -> FFmpegCapabilities {
        FFmpegCapabilities(
            binaryPresent: true,
            versionLine: "ffmpeg version 6.0 Copyright",
            encoders: [
                "libmp3lame", "aac", "pcm_s16le", "pcm_s16be", "flac", "libvorbis", "libopus", "wmav2",
                "libx264", "h264_videotoolbox", "libvpx", "libvpx-vp9", "mpeg4", "wmv2", "gif", "bmp",
                "libaom-av1", "libwebp", "png", "mjpeg",
            ],
            muxers: [
                "mp3", "ipod", "mp4", "wav", "aiff", "flac", "ogg", "opus", "asf", "mov", "matroska",
                "webm", "avi", "gif", "avif", "image2",
            ]
        )
    }

    private func makeTempDirectory() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("filewheel-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func writePNG(to url: URL, width: Int, height: Int) throws {
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

    private func runFFmpeg(_ executable: URL, _ arguments: [String]) async throws {
        let result = try await ProcessRunner.run(executable: executable, arguments: arguments, cancel: nil)
        if result.status != 0 {
            XCTFail(FFmpegDiagnostics.lastUsefulLine(result.stderr))
        }
    }
}

private enum StillProbe {
    static func image(at url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}
