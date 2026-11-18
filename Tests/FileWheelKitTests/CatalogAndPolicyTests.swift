import XCTest
@testable import FileWheelKit

final class CatalogAndPolicyTests: XCTestCase {
    func testToolCatalogAndPresentationRules() {
        XCTAssertEqual(ToolID.allCases.count, 28)
        XCTAssertEqual(ToolID.allCases.map(\.number), Array(1...28))

        let image = file("a.png", "png", .image)
        let images = [image, file("b.png", "png", .image)]
        let video = file("a.mp4", "mp4", .video)
        let videos = [video, file("b.mp4", "mp4", .video)]
        let audio = file("a.wav", "wav", .audio)
        let pdf = file("a.pdf", "pdf", .pdf)
        let pdfs = [pdf, file("b.pdf", "pdf", .pdf)]
        let zip = file("a.zip", "zip", .archive)
        let folder = file("Folder", "", .folder, directory: true)

        XCTAssertTrue(ToolCatalog.isShown(.cropImage, for: [image]))
        XCTAssertFalse(ToolCatalog.isShown(.cropImage, for: images))
        XCTAssertEqual(ToolCatalog.presentation(.compress, for: [image]), .openPanel)
        XCTAssertEqual(ToolCatalog.presentation(.normalizeAudio, for: [audio]), .runOnDrop)
        XCTAssertEqual(ToolCatalog.presentation(.stripMetadata, for: [image]), .runOnDrop)
        XCTAssertEqual(ToolCatalog.presentation(.imagesToPDF, for: images), .runOnDrop)
        XCTAssertEqual(ToolCatalog.presentation(.extractArchive, for: [zip]), .runOnDrop)
        XCTAssertEqual(ToolCatalog.presentation(.readQR, for: [image]), .runOnDropThenShowResult)
        XCTAssertEqual(ToolCatalog.presentation(.joinVideos, for: videos), .runOnDrop)
        XCTAssertEqual(ToolCatalog.presentation(.joinVideos, for: [video]), .openPanel)
        XCTAssertFalse(ToolCatalog.isShown(.joinVideos, for: [video]))
        XCTAssertEqual(ToolCatalog.presentation(.mergePDFs, for: pdfs), .runOnDrop)
        XCTAssertEqual(ToolCatalog.presentation(.collage, for: images), .openPanel)
        XCTAssertEqual(ToolCatalog.presentation(.packArchive, for: [folder]), .openPanel)
        XCTAssertFalse(ToolCatalog.isShown(.extractArchive, for: [folder]))
        XCTAssertFalse(ToolCatalog.isShown(.cropImage, for: [folder]))

        let channels = ToolCatalog.wheelEntries(for: [audio]).filter { $0.tool == .channels }
        XCTAssertEqual(channels.map(\.title), ["Mono", "Stereo", "Left only", "Right only", "Swap"])
        XCTAssertTrue(channels.allSatisfy { $0.presentation == .runOnDrop })

        let ocr = ToolCatalog.wheelEntries(for: [pdf]).filter { $0.tool == .ocrPDF }
        XCTAssertEqual(ocr.map(\.id), ["ocrPDF", "ocrPDF.options"])
        XCTAssertEqual(ocr.map(\.presentation), [.runOnDrop, .openPanel])
        XCTAssertEqual(ToolCatalog.presentation(.ocrPDF, for: [pdf]), .runOnDrop)
        XCTAssertTrue(ToolCatalog.isShown(.ocrPDF, for: [image]))
        XCTAssertFalse(ToolCatalog.isShown(.ocrPDF, for: images))
        XCTAssertEqual(ToolCatalog.presentation(.signPDF, for: [pdf]), .openPanel)
        XCTAssertFalse(ToolCatalog.isShown(.signPDF, for: [image]))
        let locks = ToolCatalog.wheelEntries(for: [pdf]).filter { $0.tool == .protectPDF }
        XCTAssertEqual(locks.map(\.title), ["Protect PDF", "Unlock PDF"])
        XCTAssertEqual(locks.compactMap(\.pdfAccess), [PDFLockAction.protect, .unlock])
        XCTAssertTrue(locks.allSatisfy { $0.presentation == .openPanel })
        XCTAssertFalse(ToolCatalog.isShown(.protectPDF, for: pdfs))
        XCTAssertFalse(ToolCatalog.isShown(.signPDF, for: pdfs))

        XCTAssertTrue(ToolCatalog.isShown(.redact, for: [pdf]))
        XCTAssertTrue(ToolCatalog.isShown(.redact, for: [image]))
        XCTAssertFalse(ToolCatalog.isShown(.redact, for: [video]))
        XCTAssertTrue(ToolCatalog.isShown(.bleep, for: [video]))
        XCTAssertTrue(ToolCatalog.isShown(.normalizeAudio, for: [video]))
        XCTAssertFalse(ToolCatalog.isShown(.trimAudio, for: [video]))
    }

    func testMixedDragHasNoSharedConvertTarget() {
        let files = [file("a.png", "png", .image), file("b.mp4", "mp4", .video)]
        XCTAssertTrue(ConversionCatalog.sharedTargets(for: files).isEmpty)
        let images = [file("a.png", "png", .image), file("b.jpg", "jpg", .image)]
        XCTAssertTrue(ConversionCatalog.sharedTargets(for: images).contains("pdf"))
    }

    func testCatalogPairsOmitSelfAndHideWMAEncode() {
        let pairs = ConversionCatalog.definedPairs()
        XCTAssertFalse(pairs.contains { $0.source == $0.target && $0.target != "extract" && $0.target != "file" })
        XCTAssertTrue(pairs.contains { $0.source == "png" && $0.target == "svg" && $0.label == "SVG (wrapped)" })
        XCTAssertFalse(pairs.contains { $0.label.localizedCaseInsensitiveContains("listen") })
        let hidden = ConversionCatalog.offeredPairs(capabilities: EngineCapabilities(canEncodeWMA: false, canExtractRAR: false, ffmpegVersion: nil))
        XCTAssertFalse(hidden.contains { $0.target == "wma" })
        XCTAssertTrue(hidden.contains { $0.source == "wma" })
        XCTAssertTrue(hidden.contains { $0.source == "rar" })
        let gaps = ConversionCatalog.gaps(capabilities: EngineCapabilities(canEncodeWMA: false, canExtractRAR: false, ffmpegVersion: nil))
        XCTAssertTrue(gaps.contains { $0.contains("WMA") })
        XCTAssertTrue(gaps.contains { $0.contains("unar") })
        let about = AboutContent.make(
            capabilities: EngineCapabilities(canEncodeWMA: true, canExtractRAR: true, ffmpegVersion: "6.1.1"),
            ffmpeg: FFmpegVersionCheck(executable: URL(fileURLWithPath: "/usr/bin/ffmpeg"), foundVersion: "6.1.1", pinnedVersion: "6.1.1", matchesPin: true, summary: "ffmpeg 6.1.1", canEncodeWMA: true, hardwareH264: false)
        )
        XCTAssertEqual(about.toolCount, 28)
        XCTAssertEqual(about.pairCount, pairs.count)
        XCTAssertFalse(about.readAloudSummary.contains("188"))
    }

    func testMenuServicesAndPrivacy() throws {
        XCTAssertEqual(MenuBarSpec.itemTitles(queuePaused: false), ["Convert selection", "Pause queue", "Show queue", "Settings", "About", "Quit"])
        XCTAssertEqual(MenuBarSpec.itemTitles(queuePaused: true)[1], "Resume queue")
        XCTAssertEqual(MenuBarSpec.serviceTitle, "File Wheel: Convert")
        let plist = try String(contentsOf: repoRoot().appendingPathComponent("FileWheel/Support/Info.plist"))
        XCTAssertTrue(plist.contains("File Wheel: Convert"))
        XCTAssertTrue(plist.contains("<key>LSUIElement</key>"))
        XCTAssertTrue(plist.contains("<true/>"))
        XCTAssertFalse(plist.localizedCaseInsensitiveContains("tangerine"))
        XCTAssertFalse(plist.contains("SUFeedURL"))
        XCTAssertFalse(ToolExecutor.allowsNetwork)
        let settings = try JSONEncoder().encode(FileWheelSettings.default)
        let object = try JSONSerialization.jsonObject(with: settings) as? [String: Any]
        let keys = Set(object?.keys.map { $0.lowercased() } ?? [])
        XCTAssertFalse(keys.contains { $0.contains("telemetry") || $0.contains("analytics") || $0.contains("sparkle") })
        XCTAssertEqual(FileWheelSettings.default.jpegQuality, 0.85)
        XCTAssertEqual(FileWheelSettings.default.videoCodec, .h264)
        XCTAssertEqual(FileWheelSettings.default.videoLongEdge, 1080)
        XCTAssertEqual(FileWheelSettings.default.videoCRF, 23)
        XCTAssertEqual(FileWheelSettings.default.svgRasterDPI, 144)
        XCTAssertTrue(FileWheelSettings.default.revealInFinder)
        XCTAssertFalse(FileWheelSettings.default.soundOnCompletion)
        XCTAssertTrue(FileWheelSettings.default.hardwareEncoder)
        XCTAssertFalse(FileWheelSettings.default.launchAtLogin)
        XCTAssertEqual(FileWheelSettings.default.readAloud.engine, .xai)
        XCTAssertEqual(FileWheelSettings.default.readAloud.voiceID, "ara")
        XCTAssertEqual(FileWheelSettings.default.readAloud.language, "en")
        XCTAssertEqual(FileWheelSettings.default.readAloud.speed, 1.0)
        XCTAssertNil(FileWheelSettings.default.readAloud.macOSVoiceIdentifier)
    }

    func testKeychainFallsBackToEnvironment() {
        let memory = MemoryAPIKeyStore()
        let store = LayeredAPIKeyStore(primary: memory, environment: ["XAI_API_KEY": "env-key"])
        XCTAssertEqual(store.read(), "env-key")
        try? memory.save("keychain-key")
        XCTAssertEqual(store.read(), "keychain-key")
    }

    func testSourceDoesNotUseReferenceBranding() throws {
        let root = repoRoot().appendingPathComponent("FileWheel")
        let files = try FileManager.default.subpathsOfDirectory(atPath: root.path).filter { $0.hasSuffix(".swift") || $0.hasSuffix(".plist") }
        for relative in files {
            let text = try String(contentsOf: root.appendingPathComponent(relative))
            XCTAssertFalse(text.localizedCaseInsensitiveContains("tangerine"), relative)
            XCTAssertFalse(text.contains("6813034065"), relative)
            XCTAssertFalse(text.contains("SUUpdater"), relative)
        }
    }

    private func file(_ name: String, _ ext: String, _ kind: MediaKind, directory: Bool = false) -> FileInput {
        FileInput(url: URL(fileURLWithPath: "/tmp/\(name)"), normalizedExtension: ext, kind: kind, isDirectory: directory)
    }
}

enum TestPaths {
    static func repoRoot(_ file: String = #filePath) -> URL {
        URL(fileURLWithPath: file)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

func repoRoot() -> URL { TestPaths.repoRoot() }
