import XCTest
@testable import FileWheelKit

final class Phase3LogicTests: XCTestCase {
    func testFailureMessagesMatchTheSpec() {
        XCTAssertEqual(FileWheelMessages.passwordProtectedPDF, "This PDF is password-protected.")
        XCTAssertEqual(FileWheelMessages.pdfNoExtractableText, "This PDF has no extractable text.")
        XCTAssertEqual(FileWheelMessages.xaiKeyRejected, "xAI key was rejected. Update it in Settings.")
        XCTAssertEqual(FileWheelMessages.sentToXAI, "The text of this file is sent to xAI. The MP3 is saved on this Mac.")
        XCTAssertEqual(FileWheelMessages.spokenOnThisMac, "Spoken on this Mac. Nothing is sent.")
        XCTAssertEqual(FileWheelMessages.sameKindRequired, "Same kind of file required")
        XCTAssertEqual(FileWheelMessages.readingPart(3, of: 12), "Reading part 3 of 12")
        XCTAssertEqual(FileWheelMessages.noLocalModel, "No local speech model is installed.")
        XCTAssertEqual(FileWheelMessages.rarBinaryMissing, "unar was not found. Install FFmpeg and unar with: brew install ffmpeg unar")
    }

    func testNamingSkipsTheSourceAndNumbersCollisions() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("Notes.txt")
        try Data("hi".utf8).write(to: source)
        var reserved: Set<URL> = []
        let first = Phase3Naming.uniqueFileURL(directory: directory, base: "Notes", pathExtension: "txt", source: source, reserved: &reserved)
        XCTAssertEqual(first.lastPathComponent, "Notes 2.txt")
        let second = Phase3Naming.uniqueFileURL(directory: directory, base: "Notes", pathExtension: "txt", source: source, reserved: &reserved)
        XCTAssertEqual(second.lastPathComponent, "Notes 3.txt")
        XCTAssertNotEqual(first.standardizedFileURL, source.standardizedFileURL)
    }

    func testPageAndExtractNames() throws {
        XCTAssertEqual(Phase3Naming.pageFileName(base: "Scan", page: 1, pathExtension: "jpg"), "Scan-page-001.jpg")
        XCTAssertEqual(Phase3Naming.sourceBaseName(for: URL(fileURLWithPath: "/tmp/Photos.tar.gz")), "Photos")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var reserved: Set<URL> = []
        let folder = Phase3Naming.uniqueFolderURL(directory: directory, name: "Photos-extracted", reserved: &reserved)
        XCTAssertEqual(folder.lastPathComponent, "Photos-extracted")
        let next = Phase3Naming.uniqueFolderURL(directory: directory, name: "Photos-extracted", reserved: &reserved)
        XCTAssertEqual(next.lastPathComponent, "Photos-extracted 2")
    }

    func testPlainTextBecomesThreeSecondCues() {
        let cues = SubtitleCodec.cuesFromPlainText("one\n\ntwo\nthree\n")
        XCTAssertEqual(cues.map(\.text), ["one", "two", "three"])
        XCTAssertEqual(cues[0].start, 0)
        XCTAssertEqual(cues[0].end, 3)
        XCTAssertEqual(cues[2].start, 6)
        let srt = SubtitleCodec.writeSRT(cues)
        XCTAssertTrue(srt.contains("00:00:00,000 --> 00:00:03,000"))
        XCTAssertTrue(srt.contains("00:00:06,000 --> 00:00:09,000"))
        let vtt = SubtitleCodec.writeVTT(cues)
        XCTAssertTrue(vtt.hasPrefix("WEBVTT\n"))
        XCTAssertTrue(vtt.contains("00:00:03.000 --> 00:00:06.000"))
    }

    func testSubtitleConversionKeepsCueTextAndTimes() throws {
        let srt = """
        1
        00:00:01,500 --> 00:00:04,000
        Hello
        there

        2
        00:01:00,000 --> 00:01:02,000
        Next
        """
        let cues = try SubtitleCodec.cues(from: srt, format: .srt)
        XCTAssertEqual(cues[0].text, "Hello\nthere")
        XCTAssertEqual(cues[0].start, 1.5)
        let parsed = try SubtitleCodec.cues(from: SubtitleCodec.writeVTT(cues), format: .vtt)
        XCTAssertEqual(parsed[0].text, "Hello\nthere")
        XCTAssertEqual(parsed[1].start, 60)
        XCTAssertEqual(SubtitleCodec.plainText(cues), "Hello\nthere\nNext")
        XCTAssertFalse(SubtitleCodec.plainText(cues).contains("-->"))
        XCTAssertFalse(SubtitleCodec.plainText(cues).contains("00:"))
    }

    func testMarkdownCleanupDropsFencesAndKeepsLinkLabels() {
        let raw = """
        # Title
        See [the docs](https://example.com) and **bold** text.
        ```
        secret code
        ```
        A _word_ and snake_case.
        """
        let cleaned = SpeakTextCleanup.cleanMarkdown(raw)
        XCTAssertFalse(cleaned.contains("secret code"))
        XCTAssertFalse(cleaned.contains("```"))
        XCTAssertFalse(cleaned.contains("# "))
        XCTAssertTrue(cleaned.contains("the docs"))
        XCTAssertFalse(cleaned.contains("https://example.com"))
        XCTAssertTrue(cleaned.contains("bold"))
        XCTAssertFalse(cleaned.contains("**"))
        XCTAssertTrue(cleaned.contains("word"))
        XCTAssertTrue(cleaned.contains("snake_case"))
    }

    func testChunkerStaysUnderTheCeilingAndKeepsEveryScalar() {
        let first = String(repeating: "a", count: 10_000)
        let second = String(repeating: "b", count: 10_000)
        let text = first + "\n\n" + second
        let chunks = TextChunker.chunks(text)
        XCTAssertEqual(chunks.count, 2)
        XCTAssertTrue(chunks.allSatisfy { TextChunker.characterCount($0) <= TextChunker.limit })
        XCTAssertEqual(chunks.joined(), first + second)

        let huge = String(repeating: "word ", count: 4_000)
        let pieces = TextChunker.chunks(huge)
        XCTAssertGreaterThan(pieces.count, 1)
        XCTAssertTrue(pieces.allSatisfy { TextChunker.characterCount($0) <= TextChunker.limit })
        XCTAssertEqual(pieces.joined(), huge.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func testCatalogOffers() {
        let pdf = DroppedFile(url: URL(fileURLWithPath: "/tmp/a.pdf"), isDirectory: false, format: "pdf")
        let png = DroppedFile(url: URL(fileURLWithPath: "/tmp/a.png"), isDirectory: false, format: "png")
        let folder = DroppedFile(url: URL(fileURLWithPath: "/tmp/Folder"), isDirectory: true, format: "directory")
        let zip = DroppedFile(url: URL(fileURLWithPath: "/tmp/a.zip"), isDirectory: false, format: "zip")
        let rar = DroppedFile(url: URL(fileURLWithPath: "/tmp/a.rar"), isDirectory: false, format: "rar")
        let txt = DroppedFile(url: URL(fileURLWithPath: "/tmp/a.txt"), isDirectory: false, format: "txt")
        let md = DroppedFile(url: URL(fileURLWithPath: "/tmp/a.md"), isDirectory: false, format: "md")

        let onePDF = Phase3Offer.make(for: [pdf])
        XCTAssertNil(onePDF.notice)
        XCTAssertTrue(onePDF.wedges.contains { $0.id == "pdf.docx" })
        XCTAssertTrue(onePDF.wedges.contains { $0.id == "pdf.jpg" })
        XCTAssertTrue(onePDF.wedges.contains { $0.id == "listen.mp3" })
        XCTAssertTrue(onePDF.wedges.contains { $0.id == "pack.gz" })
        XCTAssertEqual(onePDF.wedges.first { $0.id == "listen.mp3" }?.label, "Listen (MP3)")

        let mixed = Phase3Offer.make(for: [pdf, png])
        XCTAssertEqual(mixed.notice, FileWheelMessages.sameKindRequired)
        XCTAssertTrue(mixed.wedges.isEmpty)

        let twoPDF = Phase3Offer.make(for: [pdf, pdf])
        XCTAssertTrue(twoPDF.wedges.contains { $0.id == "pdf.txt" })
        XCTAssertTrue(twoPDF.wedges.contains { $0.id == "listen.mp3" })
        XCTAssertFalse(twoPDF.wedges.contains { $0.id == "pack.zip" })

        let packedFolder = Phase3Offer.make(for: [folder])
        XCTAssertTrue(packedFolder.wedges.contains { $0.id == "pack.zip" })
        XCTAssertFalse(packedFolder.wedges.contains { $0.id == "pack.gz" })
        XCTAssertFalse(packedFolder.wedges.contains { $0.kind == .readAloud })

        XCTAssertEqual(Phase3Offer.make(for: [rar]).wedges.map(\.id), ["rar.extract"])
        XCTAssertTrue(Phase3Offer.make(for: [zip]).wedges.contains { $0.id == "zip.extract" })
        XCTAssertFalse(Phase3Offer.make(for: [zip]).wedges.contains { $0.id == "pack.zip" })
        XCTAssertTrue(Phase3Offer.make(for: [txt, md]).wedges.contains { $0.id == "listen.mp3" })
        XCTAssertFalse(Phase3Offer.make(for: [txt, png]).wedges.contains { $0.id == "listen.mp3" })

        XCTAssertEqual(FileWheelCatalog.entry(id: "pdf.docx")?.kind, .document)
        XCTAssertEqual(FileWheelCatalog.entry(id: "zip.tar")?.kind, .archive)
        XCTAssertEqual(FileWheelCatalog.readAloudCount, 1)
        XCTAssertGreaterThan(FileWheelCatalog.pairCount, 20)
        XCTAssertFalse(FileWheelCatalog.entries.contains { $0.id == "rar.zip" })
    }

    func testTTSBodyAndAllowlist() throws {
        let body = TTSRequestBody.make(text: "Hello 1", voiceID: "ara", language: "en", speed: 1)
        let json = try JSONSerialization.jsonObject(with: body.jsonData()) as? [String: Any]
        XCTAssertEqual(json?["text"] as? String, "Hello 1")
        XCTAssertEqual(json?["voice_id"] as? String, "ara")
        XCTAssertEqual(json?["language"] as? String, "en")
        XCTAssertEqual(json?["text_normalization"] as? Bool, true)
        XCTAssertEqual(json?["speed"] as? Double, 1)
        let output = json?["output_format"] as? [String: Any]
        XCTAssertEqual(output?["codec"] as? String, "mp3")
        XCTAssertEqual(output?["sample_rate"] as? Int, 44100)
        XCTAssertEqual(output?["bit_rate"] as? Int, 192000)
        XCTAssertTrue(XAITTSEndpoint.isAllowed(XAITTSEndpoint.tts))
        XCTAssertTrue(XAITTSEndpoint.isAllowed(XAITTSEndpoint.voices))
        XCTAssertFalse(XAITTSEndpoint.isAllowed(URL(string: "https://api.x.ai/v1/chat/completions")!))
        XCTAssertFalse(XAITTSEndpoint.isAllowed(URL(string: "https://example.com/v1/tts")!))
        XCTAssertFalse(XAITTSEndpoint.isAllowed(URL(string: "http://api.x.ai/v1/tts")!))
        let fast = TTSRequestBody.make(text: "A", voiceID: "", language: "", speed: 9)
        XCTAssertEqual(fast.voiceID, "ara")
        XCTAssertEqual(fast.language, "en")
        XCTAssertEqual(fast.speed, 1.5)
    }

    func testAudioSniffAndKeyResolver() {
        XCTAssertFalse(MP3Bytes.isAudio(Data("{\"error\":true}".utf8), contentType: "application/json"))
        XCTAssertTrue(MP3Bytes.isAudio(Data([0x49, 0x44, 0x33, 0x04]), contentType: nil))
        XCTAssertTrue(MP3Bytes.isAudio(Data([0x00, 0x01]), contentType: "audio/mpeg"))
        XCTAssertEqual(XAIAPIKeyResolver.resolve(keychain: "stored", environment: "env"), "stored")
        XCTAssertEqual(XAIAPIKeyResolver.resolve(keychain: "  ", environment: "env"), "env")
        XCTAssertNil(XAIAPIKeyResolver.resolve(keychain: nil, environment: nil))
    }

    func testKeepChoiceChangesWithEngineVoiceSpeedOrLanguage() {
        var config = ReadAloudConfiguration.default
        XCTAssertFalse(config.shouldSkipConfirmPanel)
        config = config.keepingCurrentChoice(true)
        XCTAssertTrue(config.shouldSkipConfirmPanel)
        config.speed = 1.2
        XCTAssertFalse(config.shouldSkipConfirmPanel)
        config = config.keepingCurrentChoice(true)
        config.voiceID = "eve"
        XCTAssertFalse(config.shouldSkipConfirmPanel)
        config = config.keepingCurrentChoice(true)
        config.language = "fr"
        XCTAssertFalse(config.shouldSkipConfirmPanel)
        config = config.keepingCurrentChoice(true)
        config.engine = .macos
        XCTAssertFalse(config.shouldSkipConfirmPanel)
    }

    func testPageTextAndShortPages() {
        XCTAssertEqual(PageText.join(["A", "", "C"]), "A\u{000C}\u{000C}C")
        XCTAssertTrue(PageText.allPagesLackExtractableText(["", "hi", "1234567890123456789"]))
        XCTAssertFalse(PageText.allPagesLackExtractableText(["", String(repeating: "a", count: 20)]))
    }

    func testCRCAndStoredZipRoundTrip() throws {
        XCTAssertEqual(CRC32.hash(Data("123456789".utf8)), 0xCBF4_3926)
        let original = StoredZip.Item(path: "word/document.xml", data: Data("<w:t>Hello &amp; co</w:t>".utf8), modified: .epoch)
        let archive = try StoredZip.data(items: [original])
        let read = try StoredZip.items(in: archive)
        XCTAssertEqual(read.count, 1)
        XCTAssertEqual(read[0].path, "word/document.xml")
        XCTAssertEqual(read[0].data, original.data)
        XCTAssertFalse(ArchivePathSafety.isSafe("../secret"))
        XCTAssertFalse(ArchivePathSafety.isSafe("/etc/passwd"))
        XCTAssertTrue(ArchivePathSafety.isSafe("word/document.xml"))
    }

    func testDocxParagraphsAndPackage() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:body>
            <w:p><w:r><w:t>Alpha</w:t><w:t> beta</w:t></w:r></w:p>
            <w:p><w:r><w:t>Gamma</w:t></w:r></w:p>
          </w:body>
        </w:document>
        """.data(using: .utf8)!
        let paragraphs = try DocumentTextExtractor.paragraphs(inDocumentXML: xml)
        XCTAssertEqual(paragraphs, ["Alpha beta", "Gamma"])

        let blocks: [OOXMLBlock] = [.paragraph("One & two"), .pageBreak, .paragraph("Three")]
        let document = OOXMLWriter.documentXML(blocks: blocks)
        XCTAssertTrue(document.contains("One &amp; two"))
        XCTAssertTrue(document.contains("Three"))
        XCTAssertTrue(document.contains("w:type=\"page\""))
        let package = try OOXMLWriter.packageData(blocks: blocks)
        let items = try StoredZip.items(in: package)
        XCTAssertTrue(items.contains { $0.path == "[Content_Types].xml" })
        XCTAssertTrue(items.contains { $0.path == "word/document.xml" })
        let documentXML = items.first { $0.path == "word/document.xml" }?.data ?? Data()
        XCTAssertTrue(String(data: documentXML, encoding: .utf8)?.contains("One &amp; two") == true)
    }

    func testReadingOrderGroupsAGapIntoParagraphs() {
        let lines: [(text: String, bounds: CGRect)] = [
            ("First", CGRect(x: 72, y: 700, width: 200, height: 14)),
            ("line", CGRect(x: 72, y: 684, width: 200, height: 14)),
            ("Second", CGRect(x: 72, y: 640, width: 200, height: 14)),
        ]
        XCTAssertEqual(PDFEngine.paragraphsForLines(lines), ["First line", "Second"])
    }

    func testSettingsRoundTrip() {
        let defaults = UserDefaults(suiteName: "app.filewheel.tests.\(UUID().uuidString)")!
        let settings = Phase3SettingsStore(defaults: defaults)
        var read = ReadAloudConfiguration.default
        read.engine = .macos
        read.speed = 1.3
        read.language = "auto"
        read = read.keepingCurrentChoice(true)
        settings.readAloud = read
        let loaded = settings.readAloud
        XCTAssertEqual(loaded.engine, .macos)
        XCTAssertEqual(loaded.speed, 1.3)
        XCTAssertEqual(loaded.language, "auto")
        XCTAssertTrue(loaded.shouldSkipConfirmPanel)
        settings.output = OutputPreferences(mode: .folder, folderPath: "/tmp/out", revealInFinder: false, pageSizeName: "letter")
        XCTAssertEqual(settings.output.directory(forSource: URL(fileURLWithPath: "/tmp/a.txt")).path, "/tmp/out")
    }

    func testGzipHeaderName() {
        var data = Data([0x1F, 0x8B, 0x08, 0x08, 0, 0, 0, 0, 0, 0])
        data.append(contentsOf: Array("notes.txt".utf8))
        data.append(0)
        XCTAssertEqual(GzipName.originalFilename(in: data), "notes.txt")
        XCTAssertNil(GzipName.originalFilename(in: Data([0x1F, 0x8B, 0x08, 0x00, 0, 0, 0, 0, 0, 0])))
    }
}
