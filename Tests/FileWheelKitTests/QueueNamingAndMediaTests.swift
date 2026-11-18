import XCTest
@testable import FileWheelKit

final class QueueNamingAndMediaTests: XCTestCase {
    func testNamingNeverOverwritesTheSource() {
        let directory = URL(fileURLWithPath: "/tmp/filewheel-names")
        let source = directory.appendingPathComponent("Photo.png")
        let first = OutputNames.allocate(directory: directory, base: "Photo", ext: "png", source: source, reserved: [], fileExists: { _ in false })
        XCTAssertEqual(first.lastPathComponent, "Photo 2.png")
        let jpeg = OutputNames.allocate(directory: directory, base: "Photo", ext: "jpg", source: source, reserved: [], fileExists: { _ in false })
        XCTAssertEqual(jpeg.lastPathComponent, "Photo.jpg")
        let second = OutputNames.allocate(directory: directory, base: "Photo", ext: "jpg", source: source, reserved: ["Photo.jpg"], fileExists: { _ in false })
        XCTAssertEqual(second.lastPathComponent, "Photo 2.jpg")
    }

    func testCompressSearchPicksLargestUnderTargetAndCapsEncodes() {
        let under = CompressSearch.search(targetBytes: 400, low: 0, high: 1) { parameter in
            Int(parameter * 1000)
        }
        XCTAssertLessThanOrEqual(under.attempts.count, 8)
        XCTAssertTrue(under.metTarget)
        XCTAssertLessThanOrEqual(under.chosen.byteSize, 400)
        XCTAssertGreaterThan(under.chosen.byteSize, 300)

        let missed = CompressSearch.search(targetBytes: 10, low: 0, high: 1) { _ in 500 }
        XCTAssertFalse(missed.metTarget)
        XCTAssertEqual(missed.chosen.byteSize, 500)
        XCTAssertTrue(missed.notice?.contains("Could not get under the target size") == true)
        XCTAssertLessThanOrEqual(missed.attempts.count, CompressSearchResult.maxEncodes)
    }

    func testAtempoChainAndSnapshots() {
        XCTAssertEqual(AtempoChain.filters(for: 0.25), ["atempo=0.5", "atempo=0.5000"])
        XCTAssertEqual(AtempoChain.filters(for: 1.5), ["atempo=1.5000"])
        XCTAssertEqual(FFmpegGraphs.channelFilter(.swap), ["-af", "pan=stereo|c0=c1|c1=c0"])
        XCTAssertEqual(SnapshotTimes.count(3, duration: 10), [0, 5, 10])
        XCTAssertEqual(SnapshotTimes.every(3, duration: 10), [0, 3, 6, 9])
        let ranges = try? PageRangeParser.parse("1-2,4", pageCount: 5)
        XCTAssertEqual(ranges?.count, 2)
    }

    func testQueueOrdersHeavyBatchesAndConfirmsQuit() {
        let queue = JobQueue()
        queue.executeInline = true
        var order: [String] = []
        let first = UUID()
        let second = UUID()
        queue.enqueue(title: "first", weight: .heavy, batchID: first) { _ in
            order.append("first")
            return ToolRunOutcome(outputs: [])
        }
        queue.enqueue(title: "second", weight: .heavy, batchID: second) { _ in
            order.append("second")
            return ToolRunOutcome(outputs: [])
        }
        XCTAssertEqual(order, ["first", "second"])
        XCTAssertFalse(JobQueue.needsQuitConfirmation(outstanding: 0))
        XCTAssertTrue(JobQueue.needsQuitConfirmation(outstanding: 1))

        let paused = JobQueue()
        paused.executeInline = true
        paused.pause()
        paused.enqueue(title: "held", weight: .heavy) { _ in
            order.append("held")
            return ToolRunOutcome(outputs: [])
        }
        XCTAssertFalse(order.contains("held"))
        paused.resume()
        XCTAssertTrue(order.contains("held"))
    }

    func testImageJobsRunTwoAtATime() {
        let queue = JobQueue()
        let started = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        let finished = DispatchSemaphore(value: 0)
        for name in ["a", "b"] {
            queue.enqueue(title: name, weight: .image) { _ in
                started.signal()
                release.wait()
                return ToolRunOutcome(outputs: [])
            }
        }
        XCTAssertEqual(started.wait(timeout: .now() + 2), .success)
        XCTAssertEqual(started.wait(timeout: .now() + 2), .success)
        release.signal()
        release.signal()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            while queue.outstandingCount > 0 {
                Thread.sleep(forTimeInterval: 0.01)
            }
            group.leave()
        }
        XCTAssertEqual(group.wait(timeout: .now() + 2), .success)
        _ = finished
    }

    func testPDFRedactionRemovesCoveredTextAndRejectsPasswords() throws {
        let page = SimplePDF.Page(texts: [
            SimplePDF.TextObject(text: "SECRET", x: 72, y: 72, size: 12),
            SimplePDF.TextObject(text: "KEEP", x: 72, y: 400, size: 12)
        ])
        let document = SimplePDF(pages: [page])
        let box = RedactBox(pageIndex: 0, rect: FWRect(x: 60, y: 60, width: 200, height: 40))
        let redacted = document.redacting([box])
        let remaining = Redaction.remainingText(redacted.pages[0].spans(), covering: [box.rect])
        XCTAssertFalse(remaining.contains("SECRET"))
        XCTAssertTrue(remaining.contains("KEEP"))
        let roundTrip = try SimplePDF.read(redacted.data())
        XCTAssertFalse(roundTrip.extractableText().contains("SECRET"))
        XCTAssertTrue(roundTrip.extractableText().contains("KEEP"))
        XCTAssertFalse(roundTrip.pages[0].fills.isEmpty)
        let reread = try SimplePDF.read(document.data())
        XCTAssertEqual(reread.pages[0].texts.map(\.text), ["SECRET", "KEEP"])
        XCTAssertEqual(reread.pages[0].texts[0].y, 72, accuracy: 0.2)
        XCTAssertEqual(reread.pages[0].height, 792, accuracy: 0.2)

        let encrypted = Data("%PDF-1.4\n1 0 obj<< /Type /Catalog /Encrypt 2 0 R /Pages 3 0 R >>\nendobj\n%%EOF\n".utf8)
        XCTAssertThrowsError(try SimplePDF.read(encrypted)) { error in
            XCTAssertEqual((error as? ToolError)?.message, "This PDF is password-protected.")
        }
    }

    func testStripRemovesJPEGGPS() throws {
        let base = Data([
            0xFF, 0xD8, 0xFF, 0xD9
        ])
        let tagged = JPEGMetadata.injectGPS(base, gps: GPSFix(latitude: 37.5, longitude: -122.25))
        let before = try XCTUnwrap(JPEGMetadata.gps(in: tagged))
        XCTAssertEqual(before.latitude, 37.5, accuracy: 0.02)
        XCTAssertEqual(before.longitude, -122.25, accuracy: 0.02)
        let stripped = JPEGMetadata.strip(tagged)
        XCTAssertNil(JPEGMetadata.gps(in: stripped))
        XCTAssertFalse(stripped.contains(0xE1))
        XCTAssertEqual(stripped.prefix(2), Data([0xFF, 0xD8]))
    }

    func testSettingsRoundTrip() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("filewheel-settings-\(UUID().uuidString).json")
        let store = JSONSettingsStore(fileURL: url)
        var settings = FileWheelSettings.default
        settings.output = .folder("/tmp/filewheel-out")
        settings.soundOnCompletion = true
        try store.save(settings)
        let loaded = store.load()
        XCTAssertEqual(loaded.output, .folder("/tmp/filewheel-out"))
        XCTAssertTrue(loaded.soundOnCompletion)
        XCTAssertEqual(loaded.readAloud.voiceID, "ara")
    }
}
