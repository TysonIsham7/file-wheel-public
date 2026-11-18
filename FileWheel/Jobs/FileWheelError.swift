import Foundation

/// Short failure text shown in the progress window.
/// Messages quoted in the spec are the `message` string, unchanged.
struct FileWheelError: LocalizedError, Equatable {
    let message: String
    /// HTTP 401 from xAI. Not retried.
    let isUnauthorized: Bool

    init(_ message: String, unauthorized: Bool = false) {
        self.message = message
        self.isUnauthorized = unauthorized
    }

    var errorDescription: String? { message }
}

/// Strings the spec requires verbatim, plus the short reasons Phase 3 surfaces.
enum FileWheelMessages {
    static let passwordProtectedPDF = "This PDF is password-protected."
    static let pdfNoExtractableText = "This PDF has no extractable text."
    static let xaiKeyRejected = "xAI key was rejected. Update it in Settings."
    static let sentToXAI = "The text of this file is sent to xAI. The MP3 is saved on this Mac."
    static let spokenOnThisMac = "Spoken on this Mac. Nothing is sent."
    static let sameKindRequired = "Same kind of file required"
    static let noLocalModel = "No local speech model is installed."
    static let installFFmpegAndUnar = "Install FFmpeg and unar with: brew install ffmpeg unar"
    static let rarBinaryMissing = "unar was not found. \(installFFmpegAndUnar)"
    static let ffmpegMissing = "ffmpeg was not found. \(installFFmpegAndUnar)"
    static let missingAPIKey = "Add an xAI API key in Settings."
    static let xaiNotAudio = "xAI returned a response that was not audio."
    static let noTextToRead = "This file has no text to read."
    static let pdfUnreadable = "This PDF could not be read."
    static let textUnreadable = "This file could not be read as text."
    static let subtitleUnreadable = "This subtitle file could not be read."
    static let docxUnreadable = "This document could not be read."
    static let archiveUnreadable = "This archive could not be read."
    static let unsafeArchivePath = "This archive contains an unsafe path."
    static let missingMacVoice = "The selected macOS voice is not available."
    static let emptyMacSpeech = "macOS speech produced no audio."
    static let emptyLocalSpeech = "The local speech model produced no audio."
    static let gzSingleFileOnly = "gz can only pack a single file."

    static func readingPart(_ part: Int, of total: Int) -> String {
        "Reading part \(part) of \(total)"
    }
}
