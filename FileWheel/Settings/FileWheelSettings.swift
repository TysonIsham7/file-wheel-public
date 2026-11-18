import Foundation

public enum OutputLocation: Equatable, Sendable, Codable {
    case besideOriginal
    case folder(String)
}

public enum VideoCodecChoice: String, Codable, Sendable, CaseIterable {
    case h264
    case hevc

    public var ffmpegEncoder: String {
        switch self {
        case .h264:
            return "libx264"
        case .hevc:
            return "libx265"
        }
    }

    public var title: String {
        switch self {
        case .h264:
            return "H.264"
        case .hevc:
            return "HEVC"
        }
    }
}

public enum ReadAloudEngine: String, Codable, Sendable, CaseIterable {
    case xai
    case macOS
    case localModel

    public var title: String {
        switch self {
        case .xai:
            return "xAI"
        case .macOS:
            return "macOS voice"
        case .localModel:
            return "Local model"
        }
    }
}

public struct ReadAloudSettings: Equatable, Sendable, Codable {
    public var engine: ReadAloudEngine
    /// xAI voice id. Default is `ara`.
    public var voiceID: String
    public var language: String
    public var speed: Double
    /// Nil selects the system voice.
    public var macOSVoiceIdentifier: String?
    public var localModelIdentifier: String?
    public var keepChoice: Bool

    public init(
        engine: ReadAloudEngine,
        voiceID: String,
        language: String,
        speed: Double,
        macOSVoiceIdentifier: String?,
        localModelIdentifier: String?,
        keepChoice: Bool
    ) {
        self.engine = engine
        self.voiceID = voiceID
        self.language = language
        self.speed = speed
        self.macOSVoiceIdentifier = macOSVoiceIdentifier
        self.localModelIdentifier = localModelIdentifier
        self.keepChoice = keepChoice
    }

    public static let `default` = ReadAloudSettings(
        engine: .xai,
        voiceID: "ara",
        language: "en",
        speed: 1.0,
        macOSVoiceIdentifier: nil,
        localModelIdentifier: nil,
        keepChoice: false
    )
}

public struct FileWheelSettings: Equatable, Sendable, Codable {
    public var settingsVersion: Int
    public var output: OutputLocation
    public var revealInFinder: Bool
    public var soundOnCompletion: Bool
    public var jpegQuality: Double
    public var videoCodec: VideoCodecChoice
    public var videoLongEdge: Int
    public var videoCRF: Int
    public var svgRasterDPI: Int
    public var hardwareEncoder: Bool
    public var launchAtLogin: Bool
    public var readAloud: ReadAloudSettings

    public init(
        settingsVersion: Int = 1,
        output: OutputLocation,
        revealInFinder: Bool,
        soundOnCompletion: Bool,
        jpegQuality: Double,
        videoCodec: VideoCodecChoice,
        videoLongEdge: Int,
        videoCRF: Int,
        svgRasterDPI: Int,
        hardwareEncoder: Bool,
        launchAtLogin: Bool,
        readAloud: ReadAloudSettings
    ) {
        self.settingsVersion = settingsVersion
        self.output = output
        self.revealInFinder = revealInFinder
        self.soundOnCompletion = soundOnCompletion
        self.jpegQuality = jpegQuality
        self.videoCodec = videoCodec
        self.videoLongEdge = videoLongEdge
        self.videoCRF = videoCRF
        self.svgRasterDPI = svgRasterDPI
        self.hardwareEncoder = hardwareEncoder
        self.launchAtLogin = launchAtLogin
        self.readAloud = readAloud
    }

    public static let `default` = FileWheelSettings(
        output: .besideOriginal,
        revealInFinder: true,
        soundOnCompletion: false,
        jpegQuality: 0.85,
        videoCodec: .h264,
        videoLongEdge: 1080,
        videoCRF: 23,
        svgRasterDPI: 144,
        hardwareEncoder: true,
        launchAtLogin: false,
        readAloud: .default
    )

    public func clamped() -> FileWheelSettings {
        var copy = self
        copy.jpegQuality = min(1, max(0.01, jpegQuality))
        copy.videoLongEdge = max(16, videoLongEdge)
        copy.videoCRF = min(51, max(0, videoCRF))
        if !SVGRaster.choices.contains(copy.svgRasterDPI) {
            copy.svgRasterDPI = 144
        }
        copy.readAloud.speed = min(1.5, max(0.7, readAloud.speed))
        if copy.readAloud.voiceID.isEmpty {
            copy.readAloud.voiceID = "ara"
        }
        if copy.readAloud.language.isEmpty {
            copy.readAloud.language = "en"
        }
        return copy
    }
}
