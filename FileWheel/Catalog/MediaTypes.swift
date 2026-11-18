import Foundation

public enum MediaKind: String, Codable, Sendable, CaseIterable {
    case image
    case audio
    case video
    case pdf
    case text
    case subtitle
    case archive
    case folder
    case markdown
    case word
    case unknown
}

public struct MediaFormat: Hashable, Sendable, Identifiable {
    public let id: String
    public let kind: MediaKind
    public let aliases: [String]
    public let displayName: String

    public init(id: String, kind: MediaKind, aliases: [String] = [], displayName: String) {
        self.id = id
        self.kind = kind
        self.aliases = aliases
        self.displayName = displayName
    }

    public func matches(extension raw: String) -> Bool {
        let ext = MediaFormat.normalize(raw)
        return ext == id || aliases.contains(ext)
    }

    public static func normalize(_ raw: String) -> String {
        raw.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
    }
}

public enum EnginePreference: String, Codable, Sendable {
    /// ImageIO, then ffmpeg when ImageIO has no encoder.
    case imageIOThenFFmpeg
    /// Bitmap wrapped in an SVG file. The wedge label is "SVG (wrapped)".
    case svgWrap
    /// Rasterize an SVG, then encode with the still-image path.
    case svgRasterize
    /// AVFoundation, falling through to ffmpeg.
    case avFoundation
    case ffmpeg
    /// PDF, text, and subtitle pairs from Phase 3.
    case document
    /// Archive pack, extract, and repack from Phase 3.
    case archive
    /// Listen (MP3). Not counted as a conversion pair.
    case readAloud
    /// A Phase 4 tool wedge. The target is the tool id.
    case tool
}

public struct CatalogEntry: Hashable, Sendable, Identifiable {
    public var id: String { "\(source)>\(target)" }
    public let source: String
    public let target: String
    public let kind: MediaKind
    public let label: String
    public let engine: EnginePreference

    public init(
        source: String,
        target: String,
        kind: MediaKind,
        label: String,
        engine: EnginePreference
    ) {
        self.source = source
        self.target = target
        self.kind = kind
        self.label = label
        self.engine = engine
    }
}

public enum WedgeState: Equatable, Sendable {
    case enabled
    case disabled(reason: String)
    case hidden
}

public struct Wedge: Equatable, Sendable, Identifiable {
    public var id: String { entry.id }
    public let entry: CatalogEntry
    public let state: WedgeState

    public init(entry: CatalogEntry, state: WedgeState) {
        self.entry = entry
        self.state = state
    }
}

public struct WheelOffer: Equatable, Sendable {
    /// Set when a multi-file drag shares no single format.
    public let message: String?
    public let wedges: [Wedge]

    public init(message: String?, wedges: [Wedge]) {
        self.message = message
        self.wedges = wedges
    }
}

public struct SourceFile: Equatable, Sendable {
    public var fileExtension: String
    public var isDirectory: Bool
    /// Video files set this from a probe. Nil means the probe has not run.
    public var hasAudio: Bool?

    public init(fileExtension: String, isDirectory: Bool = false, hasAudio: Bool? = nil) {
        self.fileExtension = fileExtension
        self.isDirectory = isDirectory
        self.hasAudio = hasAudio
    }
}

public enum KnownFormats {
    public static let all: [MediaFormat] = [
        MediaFormat(id: "jpg", kind: .image, aliases: ["jpeg"], displayName: "JPEG"),
        MediaFormat(id: "png", kind: .image, displayName: "PNG"),
        MediaFormat(id: "webp", kind: .image, displayName: "WebP"),
        MediaFormat(id: "heic", kind: .image, displayName: "HEIC"),
        MediaFormat(id: "tif", kind: .image, aliases: ["tiff"], displayName: "TIFF"),
        MediaFormat(id: "avif", kind: .image, displayName: "AVIF"),
        MediaFormat(id: "bmp", kind: .image, displayName: "BMP"),
        MediaFormat(id: "gif", kind: .image, displayName: "GIF"),
        MediaFormat(id: "svg", kind: .image, displayName: "SVG"),
        MediaFormat(id: "mp3", kind: .audio, displayName: "MP3"),
        MediaFormat(id: "m4a", kind: .audio, displayName: "M4A"),
        MediaFormat(id: "wav", kind: .audio, displayName: "WAV"),
        MediaFormat(id: "flac", kind: .audio, displayName: "FLAC"),
        MediaFormat(id: "ogg", kind: .audio, displayName: "OGG"),
        MediaFormat(id: "opus", kind: .audio, displayName: "Opus"),
        MediaFormat(id: "aiff", kind: .audio, displayName: "AIFF"),
        MediaFormat(id: "wma", kind: .audio, displayName: "WMA"),
        MediaFormat(id: "mp4", kind: .video, displayName: "MP4"),
        MediaFormat(id: "mov", kind: .video, displayName: "MOV"),
        MediaFormat(id: "mkv", kind: .video, displayName: "MKV"),
        MediaFormat(id: "webm", kind: .video, displayName: "WebM"),
        MediaFormat(id: "avi", kind: .video, displayName: "AVI"),
        MediaFormat(id: "wmv", kind: .video, displayName: "WMV"),
        MediaFormat(id: "pdf", kind: .pdf, displayName: "PDF"),
        MediaFormat(id: "txt", kind: .text, aliases: ["text"], displayName: "TXT"),
        MediaFormat(id: "md", kind: .markdown, aliases: ["markdown"], displayName: "MD"),
        MediaFormat(id: "docx", kind: .word, displayName: "DOCX"),
        MediaFormat(id: "srt", kind: .subtitle, displayName: "SRT"),
        MediaFormat(id: "vtt", kind: .subtitle, displayName: "VTT"),
        MediaFormat(id: "zip", kind: .archive, displayName: "ZIP"),
        MediaFormat(id: "tar", kind: .archive, displayName: "TAR"),
        MediaFormat(id: "tar.gz", kind: .archive, aliases: ["tgz"], displayName: "TAR.GZ"),
        MediaFormat(id: "gz", kind: .archive, displayName: "GZ"),
        MediaFormat(id: "rar", kind: .archive, displayName: "RAR"),
    ]

    public static func format(id: String) -> MediaFormat? {
        all.first { $0.id == id }
    }

    public static func canonical(extension raw: String) -> MediaFormat? {
        let ext = MediaFormat.normalize(raw)
        return all.first { $0.matches(extension: ext) }
    }

    public static func displayName(id: String) -> String {
        format(id: id)?.displayName ?? id.uppercased()
    }
}

public struct ConversionOptions: Equatable, Sendable {
    public var svgRasterDPI: Int
    public var jpegQuality: Double
    /// Section 10: 1080p, so the long edge is at most 1920 and smaller sources are not upscaled.
    public var maxLongEdge: Int
    public var videoCRF: Int
    public var gifMaxWidth: Int
    public var gifFPS: Int
    public var hardwareEncoder: Bool

    public init(
        svgRasterDPI: Int = 144,
        jpegQuality: Double = 0.85,
        maxLongEdge: Int = 1920,
        videoCRF: Int = 23,
        gifMaxWidth: Int = 720,
        gifFPS: Int = 12,
        hardwareEncoder: Bool = true
    ) {
        self.svgRasterDPI = svgRasterDPI
        self.jpegQuality = jpegQuality
        self.maxLongEdge = maxLongEdge
        self.videoCRF = videoCRF
        self.gifMaxWidth = gifMaxWidth
        self.gifFPS = gifFPS
        self.hardwareEncoder = hardwareEncoder
    }

    public static let specDefaults = ConversionOptions()

    public var resolvedSVGDPI: Int {
        let allowed: Set<Int> = [72, 144, 300]
        return allowed.contains(svgRasterDPI) ? svgRasterDPI : 144
    }
}

public enum ConversionError: Error, Equatable, LocalizedError {
    case failed(String)
    case noAudio
    case cancelled
    case ffmpegMissing
    case sameKindRequired

    public var errorDescription: String? {
        switch self {
        case .failed(let reason):
            return reason
        case .noAudio:
            return "No audio"
        case .cancelled:
            return "Cancelled"
        case .ffmpegMissing:
            return FileWheelMessages.ffmpegMissing
        case .sameKindRequired:
            return "Same kind of file required"
        }
    }
}

/// AVFoundation could not do the job. The router tries ffmpeg next.
public struct EngineFallback: Error, Sendable {
    public let reason: String

    public init(_ reason: String) {
        self.reason = reason
    }
}

public final class ConversionCancel: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var handlers: [() -> Void] = []

    public init() {}

    public var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    public func cancel() {
        let pending: [() -> Void]
        lock.lock()
        cancelled = true
        pending = handlers
        handlers.removeAll()
        lock.unlock()
        pending.forEach { $0() }
    }

    public func onCancel(_ handler: @escaping () -> Void) {
        lock.lock()
        if cancelled {
            lock.unlock()
            handler()
            return
        }
        handlers.append(handler)
        lock.unlock()
    }
}
