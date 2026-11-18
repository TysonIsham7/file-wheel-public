import PDFKit
import XCTest
@testable import FileWheelKit

final class PDFToolLogicTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("filewheel-pdf-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let directory {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    func testOCRPolicySkipsPagesThatAlreadyHaveText() {
        XCTAssertTrue(OCRTextLayer.shouldRecognize(extractableText: "", force: false))
        XCTAssertTrue(OCRTextLayer.shouldRecognize(extractableText: String(repeating: "a", count: 20), force: false))
        XCTAssertFalse(OCRTextLayer.shouldRecognize(extractableText: String(repeating: "a", count: 21), force: false))
        XCTAssertTrue(OCRTextLayer.shouldRecognize(extractableText: String(repeating: "a", count: 21), force: true))
    }

    func testOCRTextLayerMakesAScannedPageExtractable() throws {
        let jpeg = Data([0xFF, 0xD8, 0xFF, 0xD9])
        let image = SimplePDF.ImageObject(
            jpeg: jpeg,
            rect: FWRect(x: 0, y: 0, width: 612, height: 792),
            pixelWidth: 2,
            pixelHeight: 2
        )
        let scanned = OCRPageSpec(
            width: 612,
            height: 792,
            extractableText: "",
            keptImages: [image],
            recognized: [RecognizedWord(text: "SCANNED", rect: FWRect(x: 72, y: 80, width: 140, height: 20))]
        )
        let kept = OCRPageSpec(
            width: 612,
            height: 792,
            extractableText: "ALREADY EXTRACTABLE TEXT!!",
            existingObjects: [SimplePDF.TextObject(text: "ALREADY EXTRACTABLE TEXT!!", x: 72, y: 72)],
            recognized: [RecognizedWord(text: "SCANNED", rect: FWRect(x: 72, y: 80, width: 140, height: 20))]
        )
        let document = OCRTextLayer.document(pages: [scanned, kept])
        let data = document.data()
        let raw = String(decoding: data, as: UTF8.self)
        XCTAssertEqual(raw.components(separatedBy: "3 Tr").count - 1, 1)
        let parsed = try SimplePDF.read(data)
        XCTAssertTrue(parsed.extractableText().contains("SCANNED"))
        XCTAssertTrue(parsed.extractableText().contains("ALREADY EXTRACTABLE TEXT!!"))
        XCTAssertEqual(parsed.pages[0].texts[0].invisible, true)
        let roundTrip = try SimplePDF.read(parsed.data())
        XCTAssertTrue(roundTrip.extractableText().contains("SCANNED"))
        if let kit = PDFDocument(data: data) {
            XCTAssertTrue(kit.string?.contains("SCANNED") == true)
            XCTAssertTrue(kit.string?.contains("ALREADY EXTRACTABLE TEXT!!") == true)
        }
    }

    func testForceOCRReplacesAPageThatAlreadyHasText() throws {
        let image = SimplePDF.ImageObject(
            jpeg: Data([0xFF, 0xD8, 0xFF, 0xD9]),
            rect: FWRect(x: 0, y: 0, width: 200, height: 200),
            pixelWidth: 2,
            pixelHeight: 2
        )
        let spec = OCRPageSpec(
            width: 200,
            height: 200,
            extractableText: "ALREADY EXTRACTABLE TEXT!!",
            existingObjects: [SimplePDF.TextObject(text: "ALREADY EXTRACTABLE TEXT!!", x: 10, y: 10)],
            keptImages: [image],
            recognized: [RecognizedWord(text: "FORCED", rect: FWRect(x: 12, y: 12, width: 80, height: 16))],
            force: true
        )
        let parsed = try SimplePDF.read(OCRTextLayer.document(pages: [spec]).data())
        XCTAssertTrue(parsed.extractableText().contains("FORCED"))
        XCTAssertFalse(parsed.extractableText().contains("ALREADY EXTRACTABLE TEXT!!"))
    }

    func testOCRExecutorWritesSearchableCopyBesideTheSource() throws {
        let jpeg = Data([0xFF, 0xD8, 0xFF, 0xD9])
        let sourceDocument = SimplePDF(pages: [
            SimplePDF.Page(images: [SimplePDF.ImageObject(jpeg: jpeg, rect: FWRect(x: 0, y: 0, width: 612, height: 792), pixelWidth: 2, pixelHeight: 2)])
        ])
        let source = directory.appendingPathComponent("Scan.pdf")
        try sourceDocument.data().write(to: source)
        let original = try Data(contentsOf: source)
        var environment = ToolEnvironment.system()
        environment.textRecognizer = FixedTextRecognizer(words: [RecognizedWord(text: "SCANNED", rect: FWRect(x: 48, y: 48, width: 100, height: 16))])
        let file = MediaClassifier.classify(source)
        let outcome = try ToolExecutor.run(
            ToolRunRequest(tool: .ocrPDF, files: [file], parameters: .ocrPDF(OCRParameters()), settings: .default),
            environment: environment
        )
        XCTAssertEqual(try Data(contentsOf: source), original)
        let output = try XCTUnwrap(outcome.outputs.first)
        XCTAssertTrue(output.lastPathComponent.hasPrefix("Scan-ocr"))
        XCTAssertNotEqual(output, source)
        let parsed = try SimplePDF.read(Data(contentsOf: output))
        XCTAssertTrue(parsed.extractableText().contains("SCANNED"))
        XCTAssertTrue(String(decoding: try Data(contentsOf: output), as: UTF8.self).contains("3 Tr"))
    }

    func testSignaturePlacementStaysInsideThePage() {
        let page = PageSize.usLetter
        let base = FWSize(width: 180, height: 60)
        let centered = SignatureTransform.placing(click: FWPoint(x: 306, y: 396), baseSize: base, page: page)
        XCTAssertEqual(centered.rect().x, 216, accuracy: 0.001)
        XCTAssertEqual(centered.rect().y, 366, accuracy: 0.001)
        let corner = SignatureTransform.placing(click: FWPoint(x: 0, y: 0), baseSize: base, page: page)
        XCTAssertEqual(corner.rect().x, 0, accuracy: 0.001)
        XCTAssertEqual(corner.rect().y, 0, accuracy: 0.001)
        XCTAssertLessThanOrEqual(corner.rect().maxX, page.width)
        XCTAssertLessThanOrEqual(corner.rect().maxY, page.height)
        let grown = corner.scaled(to: 3, page: page)
        XCTAssertLessThanOrEqual(grown.rect().maxX, page.width + 0.001)
        XCTAssertLessThanOrEqual(grown.rect().maxY, page.height + 0.001)
        XCTAssertGreaterThan(grown.size.width, corner.size.width)
        let mapped = SignaturePlacementMath.pagePoint(
            viewPoint: FWPoint(x: 10, y: 20),
            viewSize: FWSize(width: 100, height: 200),
            pageSize: page
        )
        XCTAssertEqual(mapped.x, 61.2, accuracy: 0.001)
        XCTAssertEqual(mapped.y, 79.2, accuracy: 0.001)
        let view = SignaturePlacementMath.viewRect(FWRect(x: 61.2, y: 79.2, width: 100, height: 50), page: page, view: FWSize(width: 100, height: 200))
        XCTAssertEqual(view.x, 10, accuracy: 0.02)
        XCTAssertEqual(view.y, 20, accuracy: 0.02)
        let low = FWRect(x: 40, y: 770, width: 120, height: 20)
        let caption = SignaturePlacementMath.captionOrigin(signature: low, pageHeight: page.height)
        XCTAssertLessThan(caption.y, low.y)
    }

    func testSignatureComposerPlacesTheImageOnTheChosenPage() throws {
        let page = PageSize.usLetter
        let placement = SignatureTransform.placing(click: FWPoint(x: 300, y: 400), baseSize: FWSize(width: 120, height: 40), page: page)
        let signature = SimplePDF.ImageObject(
            jpeg: Data([0xFF, 0xD8, 0xFF, 0xD9]),
            rect: placement.rect(),
            pixelWidth: 1,
            pixelHeight: 1
        )
        let document = SimplePDF(pages: [
            SimplePDF.Page(texts: [SimplePDF.TextObject(text: "PAGEONE", x: 72, y: 72)]),
            SimplePDF.Page(texts: [SimplePDF.TextObject(text: "PAGETWO", x: 72, y: 72)])
        ])
        let signed = SignatureComposer.applying(document: document, pageIndex: 1, signature: signature, text: "Initial", date: "2026-01-15")
        let parsed = try SimplePDF.read(signed.data())
        XCTAssertTrue(parsed.pages[0].images.isEmpty)
        XCTAssertEqual(parsed.pages[0].texts.map(\.text), ["PAGEONE"])
        XCTAssertEqual(parsed.pages[1].images.count, 1)
        let rect = try XCTUnwrap(parsed.pages[1].images.first).rect
        XCTAssertEqual(rect.x, placement.rect().x, accuracy: 0.02)
        XCTAssertEqual(rect.y, placement.rect().y, accuracy: 0.02)
        XCTAssertEqual(rect.width, placement.rect().width, accuracy: 0.02)
        XCTAssertEqual(rect.height, placement.rect().height, accuracy: 0.02)
        XCTAssertTrue(parsed.pages[1].texts.map(\.text).contains("PAGETWO"))
        XCTAssertTrue(parsed.pages[1].texts.map(\.text).contains("Initial"))
        XCTAssertTrue(parsed.pages[1].texts.map(\.text).contains("2026-01-15"))
    }

    func testNearWhiteBackgroundBecomesTransparent() {
        var pixels: [UInt8] = [
            255, 255, 255, 255,
            250, 248, 246, 255,
            10, 10, 10, 255,
            200, 200, 200, 255
        ]
        SignatureBackground.removeNearWhite(&pixels, threshold: 245)
        XCTAssertEqual(pixels[3], 0)
        XCTAssertEqual(pixels[7], 0)
        XCTAssertEqual(pixels[11], 255)
        XCTAssertEqual(pixels[15], 255)
    }

    func testSignatureStoreRoundTripStaysInItsDirectory() throws {
        let store = SignatureStore(directory: directory.appendingPathComponent("Signatures", isDirectory: true))
        let saved = SavedSignature(id: UUID(), name: "Ink", png: Data([1, 2, 3, 4]))
        try store.save(saved)
        let loaded = try store.load()
        XCTAssertEqual(loaded.map(\.name), ["Ink"])
        XCTAssertEqual(loaded.map(\.png), [Data([1, 2, 3, 4])])
        let outside = SignatureRecordBox(id: UUID(), name: "Outside", file: "../outside.png")
        let index = try JSONEncoder().encode([outside])
        try index.write(to: store.directory.appendingPathComponent("index.json"))
        XCTAssertTrue(try store.load().isEmpty)
        let support = SignatureStore.applicationSupportDirectory()
        XCTAssertEqual(support.lastPathComponent, "Signatures")
        XCTAssertEqual(support.deletingLastPathComponent().lastPathComponent, "File Wheel")
    }

    func testProtectPlanDoesNotEchoPasswords() {
        XCTAssertThrowsError(try PDFProtectionPlan.make(password: "alpha", confirm: "beta", ownerPassword: "", allowPrinting: true, allowCopying: true)) { error in
            let message = (error as? ToolError)?.message ?? ""
            XCTAssertEqual(message, PDFProtectValidation.mismatch)
            XCTAssertFalse(message.contains("alpha"))
            XCTAssertFalse(message.contains("beta"))
        }
        XCTAssertThrowsError(try PDFProtectionPlan.make(password: "", confirm: "", ownerPassword: "", allowPrinting: true, allowCopying: true)) { error in
            XCTAssertEqual((error as? ToolError)?.message, PDFProtectValidation.enterPassword)
        }
        let plan = try? PDFProtectionPlan.make(password: "alpha", confirm: "alpha", ownerPassword: "", allowPrinting: false, allowCopying: true)
        XCTAssertEqual(plan?.ownerPassword, "alpha")
        XCTAssertEqual(plan?.allowPrinting, false)
        XCTAssertEqual(plan?.allowCopying, true)
        XCTAssertEqual(PDFEncryptionChoice.keyLengthsToTry().first, 256)
        var secret = "temporary-secret"
        PasswordMemory.clear(&secret)
        XCTAssertEqual(secret, "")
        var parameters = ToolParameters.protectPDF(ProtectPDFParameters(password: "temporary-secret", confirm: "temporary-secret", ownerPassword: "temporary-secret"))
        parameters = parameters.scrubbed()
        if case .protectPDF(let value) = parameters {
            XCTAssertEqual(value.password, "")
            XCTAssertEqual(value.confirm, "")
            XCTAssertEqual(value.ownerPassword, "")
        } else {
            XCTFail("Expected protect parameters")
        }
        XCTAssertTrue(PasswordPrompt.shouldOfferUnlock(forFailure: ToolError.passwordProtected.message))
        XCTAssertTrue(PasswordPrompt.shouldOfferUnlock(forFailure: FileWheelMessages.passwordProtectedPDF))
        XCTAssertFalse(PasswordPrompt.shouldOfferUnlock(forFailure: PDFUnlock.rejectedMessage))
        XCTAssertFalse(PasswordPrompt.shouldOfferUnlock(forFailure: ToolError.passwordProtected.message, suppressForUnlockAttempt: true))
    }

    func testUnlockNameStripsProtectedSuffix() {
        XCTAssertEqual(PDFToolSuffix.unlockedBase(from: "Doc"), "Doc-unlocked")
        XCTAssertEqual(PDFToolSuffix.unlockedBase(from: "Doc-protected"), "Doc-unlocked")
    }

    func testProtectThenUnlockRoundTripsAndWrongPasswordFailsCleanly() throws {
        let sourceDocument = SimplePDF(pages: [
            SimplePDF.Page(texts: [SimplePDF.TextObject(text: "ROUNDTRIP", x: 72, y: 72)])
        ])
        let source = directory.appendingPathComponent("Doc.pdf")
        try sourceDocument.data().write(to: source)
        let original = try Data(contentsOf: source)
        let file = MediaClassifier.classify(source)
        let environment = ToolEnvironment.system()
        let protected = try ToolExecutor.run(
            ToolRunRequest(
                tool: .protectPDF,
                files: [file],
                parameters: .protectPDF(ProtectPDFParameters(password: "open-pass", confirm: "open-pass", allowPrinting: false, allowCopying: false)),
                settings: .default
            ),
            environment: environment
        )
        XCTAssertEqual(try Data(contentsOf: source), original)
        let protectedURL = try XCTUnwrap(protected.outputs.first)
        XCTAssertTrue(protectedURL.lastPathComponent.hasPrefix("Doc-protected"))
        let locked = PDFDocument(url: protectedURL)
        XCTAssertEqual(locked?.isLocked, true)
        XCTAssertEqual(locked?.unlock(withPassword: "not-the-password"), false)
        XCTAssertThrowsError(try SimplePDF.read(Data(contentsOf: protectedURL))) { error in
            XCTAssertEqual((error as? ToolError)?.message, ToolError.passwordProtected.message)
        }
        let before = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).map(\.lastPathComponent).sorted()
        XCTAssertThrowsError(try ToolExecutor.run(
            ToolRunRequest(
                tool: .protectPDF,
                files: [MediaClassifier.classify(protectedURL)],
                parameters: .unlockPDF(UnlockPDFParameters(password: "not-the-password")),
                settings: .default
            ),
            environment: environment
        )) { error in
            let message = (error as? ToolError)?.message ?? ""
            XCTAssertEqual(message, PDFUnlock.rejectedMessage)
            XCTAssertFalse(message.contains("not-the-password"))
            XCTAssertFalse(message.contains("open-pass"))
        }
        let after = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).map(\.lastPathComponent).sorted()
        XCTAssertEqual(before, after)
        let unlocked = try ToolExecutor.run(
            ToolRunRequest(
                tool: .protectPDF,
                files: [MediaClassifier.classify(protectedURL)],
                parameters: .unlockPDF(UnlockPDFParameters(password: "open-pass")),
                settings: .default
            ),
            environment: environment
        )
        let unlockedURL = try XCTUnwrap(unlocked.outputs.first)
        XCTAssertTrue(unlockedURL.lastPathComponent.hasPrefix("Doc-unlocked"))
        XCTAssertEqual(try Data(contentsOf: source), original)
        let opened = PDFDocument(url: unlockedURL)
        XCTAssertEqual(opened?.isLocked, false)
        let kitText = opened?.string ?? ""
        let raw = String(data: try Data(contentsOf: unlockedURL), encoding: .isoLatin1) ?? ""
        XCTAssertTrue(kitText.contains("ROUNDTRIP") || raw.contains("ROUNDTRIP"))
    }
}

private struct SignatureRecordBox: Codable {
    var id: UUID
    var name: String
    var file: String
}
