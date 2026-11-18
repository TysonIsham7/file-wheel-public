import Foundation

public enum AcceptanceCoverage: String, Equatable, Sendable {
    case coveredHere
    case partialHere
    case needsAppleSilicon
    case earlierPhase
}

public struct AcceptanceItem: Equatable, Sendable, Identifiable {
    public var id: Int
    public var summary: String
    public var coverage: AcceptanceCoverage
    public var note: String

    public init(id: Int, summary: String, coverage: AcceptanceCoverage, note: String) {
        self.id = id
        self.summary = summary
        self.coverage = coverage
        self.note = note
    }

    public static let all: [AcceptanceItem] = [
        AcceptanceItem(id: 1, summary: "Shift-drag PNG to JPEG, outside drop writes nothing.", coverage: .earlierPhase, note: "Wheel hit testing is phase 1. Naming never overwrites the source."),
        AcceptanceItem(id: 2, summary: "Option shows tools and releases back to formats.", coverage: .earlierPhase, note: "ToolCatalog.wheelEntries is the tools side of that toggle."),
        AcceptanceItem(id: 3, summary: "Arrow keys, Return, and Escape.", coverage: .earlierPhase, note: "Phase 1 wheel keyboard."),
        AcceptanceItem(id: 4, summary: "Ten images offer only image actions.", coverage: .partialHere, note: "Shared convert targets and tool visibility are tested. The wheel UI is phase 1."),
        AcceptanceItem(id: 5, summary: "PNG+MP4 has no runnable convert wedge.", coverage: .coveredHere, note: "ConversionCatalog.sharedTargets is empty for a mixed drag."),
        AcceptanceItem(id: 6, summary: "Every section 7 pair converts or is listed as a gap.", coverage: .partialHere, note: "The catalog lists every pair. Engines are phases 2 and 3. WMA hides when the encoder is missing."),
        AcceptanceItem(id: 7, summary: "Three-page PDF to JPEG, TXT, and DOCX.", coverage: .earlierPhase, note: "Phase 3 document conversions."),
        AcceptanceItem(id: 8, summary: "Each of the 28 tools completes on a fixture.", coverage: .coveredHere, note: "Tool execution fixtures. GUI confirmation of the panels is on Apple silicon."),
        AcceptanceItem(id: 9, summary: "PDF redact removes covered text.", coverage: .coveredHere, note: "SimplePDF redaction drops intersecting text spans and paints black boxes."),
        AcceptanceItem(id: 10, summary: "Strip metadata removes GPS.", coverage: .coveredHere, note: "JPEG APP1 GPS segment is removed. The source file is not rewritten."),
        AcceptanceItem(id: 11, summary: "Compress-to-size lands under the target or says it could not.", coverage: .coveredHere, note: "Binary search is capped at 8 encodes."),
        AcceptanceItem(id: 12, summary: "Cancel mid-ffmpeg leaves no destination.", coverage: .coveredHere, note: "The command runner terminates ffmpeg and the temp file is not committed."),
        AcceptanceItem(id: 13, summary: "Two batches queue, and quit asks before killing a job.", coverage: .coveredHere, note: "Heavy jobs stay in order. Quit confirmation is the menu-bar path."),
        AcceptanceItem(id: 14, summary: "A non-Read-aloud batch makes no outbound connection.", coverage: .partialHere, note: "ToolExecutor.allowsNetwork is false and the tool path has no URL client. A packet capture is an Apple silicon check."),
        AcceptanceItem(id: 15, summary: "Password-protected PDF fails with the specified message.", coverage: .coveredHere, note: "The message stays “This PDF is password-protected.” PDF tools and PDF conversions then offer Unlock."),
        AcceptanceItem(id: 16, summary: "Read aloud saves Name.mp3 and Play does not call xAI again.", coverage: .earlierPhase, note: "Phase 3. Settings store the xAI engine, voice ara, and speed 1.0."),
        AcceptanceItem(id: 17, summary: "Long documents split at 15,000 characters.", coverage: .earlierPhase, note: "Phase 3 Read aloud."),
        AcceptanceItem(id: 18, summary: "Rejected xAI key writes no MP3.", coverage: .partialHere, note: "The key is read from the Keychain, then XAI_API_KEY. The request itself is phase 3."),
        AcceptanceItem(id: 19, summary: "PDF with no extractable text writes no MP3.", coverage: .earlierPhase, note: "Phase 3."),
        AcceptanceItem(id: 20, summary: "macOS Read aloud voice makes no outbound connection.", coverage: .earlierPhase, note: "The engine choice is in Settings. Speech synthesis is phase 3."),
        AcceptanceItem(id: 21, summary: "OCR makes a scanned page’s text extractable.", coverage: .coveredHere, note: "The text-layer writer adds invisible text over the page image. A Finder drop is the on-Mac smoke test."),
        AcceptanceItem(id: 22, summary: "Sign places an image on the chosen page.", coverage: .coveredHere, note: "Placement math clamps the signature to the page. The signed copy is flattened."),
        AcceptanceItem(id: 23, summary: "Protect then unlock round-trips the content.", coverage: .coveredHere, note: "PDFKit writes the encrypted copy and the unlocked copy. Passwords are not stored."),
        AcceptanceItem(id: 24, summary: "A wrong unlock password fails cleanly.", coverage: .coveredHere, note: "The message is “The password was not accepted.” No unlocked file is written.")
    ]
}
