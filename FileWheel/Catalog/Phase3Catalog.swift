import Foundation

/// Document, archive, and Listen rows (spec 7.4, 7.5, 7.7).
/// Image, audio, and video rows belong to Phase 1 and Phase 2.
enum Phase3Catalog {
    static let entries: [Phase3Entry] = documentEntries + archiveEntries + listenEntries

    static let documentEntries: [Phase3Entry] = [
        entry("pdf.docx", "DOCX", "Convert to DOCX", ["pdf"]),
        entry("pdf.jpg", "JPG", "Convert to JPG", ["pdf"]),
        entry("pdf.png", "PNG", "Convert to PNG", ["pdf"]),
        entry("pdf.txt", "TXT", "Convert to TXT", ["pdf"]),
        entry("txt.pdf", "PDF", "Convert to PDF", ["txt"]),
        entry("txt.jpg", "JPG", "Convert to JPG", ["txt"]),
        entry("txt.png", "PNG", "Convert to PNG", ["txt"]),
        entry("txt.srt", "SRT", "Convert to SRT", ["txt"]),
        entry("txt.vtt", "VTT", "Convert to VTT", ["txt"]),
        entry("srt.vtt", "VTT", "Convert to VTT", ["srt"]),
        entry("srt.txt", "TXT", "Convert to TXT", ["srt"]),
        entry("vtt.srt", "SRT", "Convert to SRT", ["vtt"]),
        entry("vtt.txt", "TXT", "Convert to TXT", ["vtt"]),
    ]

    static let archiveEntries: [Phase3Entry] = [
        pack("pack.zip", "ZIP", "Pack as ZIP", folders: true),
        pack("pack.tar", "TAR", "Pack as TAR", folders: true),
        pack("pack.tar.gz", "TAR.GZ", "Pack as TAR.GZ", folders: true),
        pack("pack.gz", "GZ", "Pack as GZ", folders: false),
        entry("zip.tar", "TAR", "Convert to TAR", ["zip"]),
        entry("zip.tar.gz", "TAR.GZ", "Convert to TAR.GZ", ["zip"]),
        entry("zip.extract", "Extract", "Extract", ["zip"]),
        entry("tar.zip", "ZIP", "Convert to ZIP", ["tar"]),
        entry("tar.tar.gz", "TAR.GZ", "Convert to TAR.GZ", ["tar"]),
        entry("tar.extract", "Extract", "Extract", ["tar"]),
        entry("tar.gz.zip", "ZIP", "Convert to ZIP", ["tar.gz"]),
        entry("tar.gz.tar", "TAR", "Convert to TAR", ["tar.gz"]),
        entry("tar.gz.extract", "Extract", "Extract", ["tar.gz"]),
        entry("rar.extract", "Extract", "Extract", ["rar"]),
        entry("gz.extract", "Extract", "Extract", ["gz"]),
    ]

    static let listenEntries: [Phase3Entry] = [
        Phase3Entry(
            id: "listen.mp3",
            label: "Listen (MP3)",
            progressTitle: "Listen (MP3)",
            source: .files(["txt", "md", "pdf", "docx", "srt", "vtt"]),
            kind: .readAloud,
            countsAsPair: false
        ),
    ]

    private static func entry(_ id: String, _ label: String, _ title: String, _ formats: Set<String>) -> Phase3Entry {
        Phase3Entry(id: id, label: label, progressTitle: title, source: .files(formats), kind: id.hasPrefix("pack") || id.contains("extract") || formats.contains("zip") || formats.contains("tar") || formats.contains("tar.gz") || formats.contains("rar") || formats.contains("gz") ? .archive : .document)
    }

    private static func pack(_ id: String, _ label: String, _ title: String, folders: Bool) -> Phase3Entry {
        Phase3Entry(id: id, label: label, progressTitle: title, source: .pack(folders: folders), kind: .archive)
    }
}
