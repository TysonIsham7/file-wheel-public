import Foundation

public struct AboutContent: Equatable, Sendable {
    public var pairCount: Int
    public var toolCount: Int
    public var readAloudSummary: String
    public var ffmpegVersionLine: String
    public var gaps: [String]
    public var privacyLine: String

    public init(pairCount: Int, toolCount: Int, readAloudSummary: String, ffmpegVersionLine: String, gaps: [String], privacyLine: String) {
        self.pairCount = pairCount
        self.toolCount = toolCount
        self.readAloudSummary = readAloudSummary
        self.ffmpegVersionLine = ffmpegVersionLine
        self.gaps = gaps
        self.privacyLine = privacyLine
    }

    public static let privacyLine = "Local only. No telemetry and no auto-update. Read aloud is the only feature that can use the network, and only the xAI engine sends extracted text to api.x.ai."

    public static func make(capabilities: EngineCapabilities, ffmpeg: FFmpegVersionCheck) -> AboutContent {
        let pairs = ConversionCatalog.offeredPairs(capabilities: capabilities)
        var gaps = ConversionCatalog.gaps(capabilities: capabilities)
        if ffmpeg.executable == nil || ffmpeg.foundVersion == nil {
            gaps.append(ffmpeg.summary)
        }
        return AboutContent(
            pairCount: pairs.count,
            toolCount: ToolID.allCases.count,
            readAloudSummary: "Read aloud: Listen (MP3) for txt, md, pdf, docx, srt, and vtt. Counted on its own line, separate from the \(pairs.count) conversion pairs.",
            ffmpegVersionLine: ffmpeg.summary,
            gaps: gaps,
            privacyLine: privacyLine
        )
    }
}

public enum MenuBarSpec {
    public static let convertSelection = "Convert selection"
    public static let pauseQueue = "Pause queue"
    public static let resumeQueue = "Resume queue"
    public static let showQueue = "Show queue"
    public static let settings = "Settings"
    public static let about = "About"
    public static let quit = "Quit"
    public static let serviceTitle = "File Wheel: Convert"
    public static let serviceMessage = "convertSelection"

    public static func itemTitles(queuePaused: Bool) -> [String] {
        [
            convertSelection,
            queuePaused ? resumeQueue : pauseQueue,
            showQueue,
            settings,
            about,
            quit
        ]
    }
}
