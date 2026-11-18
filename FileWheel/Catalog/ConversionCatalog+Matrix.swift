import Foundation

public enum PairGroup: String, Codable, Sendable, Equatable {
    case image
    case audio
    case video
    case document
    case archive
}

public struct DirectedPair: Equatable, Hashable, Sendable, Codable {
    public var source: String
    public var target: String
    public var group: PairGroup
    public var label: String

    public init(source: String, target: String, group: PairGroup, label: String? = nil) {
        self.source = source
        self.target = target
        self.group = group
        self.label = label ?? "\(source) → \(target)"
    }
}

public struct EngineCapabilities: Equatable, Sendable {
    public var canEncodeWMA: Bool
    public var canExtractRAR: Bool
    public var ffmpegVersion: String?

    public init(canEncodeWMA: Bool, canExtractRAR: Bool, ffmpegVersion: String?) {
        self.canEncodeWMA = canEncodeWMA
        self.canExtractRAR = canExtractRAR
        self.ffmpegVersion = ffmpegVersion
    }

    public static let allAvailable = EngineCapabilities(canEncodeWMA: true, canExtractRAR: true, ffmpegVersion: nil)
}

extension ConversionCatalog {
    public static let rasterFormats = ["jpg", "png", "webp", "heic", "tif", "avif", "bmp", "gif"]
    public static let audioFormats = ["mp3", "m4a", "wav", "flac", "ogg", "opus", "aiff", "wma"]
    public static let videoFormats = ["mp4", "mov", "mkv", "webm", "avi", "wmv"]
    public static let mixedKindMessage = "Same kind of file required"

    public static func definedPairs() -> [DirectedPair] {
        var pairs: [DirectedPair] = []
        for source in rasterFormats {
            for target in rasterFormats where target != source {
                pairs.append(DirectedPair(source: source, target: target, group: .image))
            }
            pairs.append(DirectedPair(source: source, target: "pdf", group: .image))
            pairs.append(DirectedPair(source: source, target: "docx", group: .image))
            pairs.append(DirectedPair(source: source, target: "svg", group: .image, label: "SVG (wrapped)"))
        }
        for target in rasterFormats + ["pdf", "docx"] {
            pairs.append(DirectedPair(source: "svg", target: target, group: .image))
        }
        for source in audioFormats {
            for target in audioFormats where target != source {
                pairs.append(DirectedPair(source: source, target: target, group: .audio))
            }
        }
        for source in videoFormats {
            for target in videoFormats where target != source {
                pairs.append(DirectedPair(source: source, target: target, group: .video))
            }
            pairs.append(DirectedPair(source: source, target: "gif", group: .video))
            pairs.append(DirectedPair(source: source, target: "mp3", group: .video))
        }
        for target in ["docx", "jpg", "png", "txt"] {
            pairs.append(DirectedPair(source: "pdf", target: target, group: .document))
        }
        for target in ["pdf", "jpg", "png", "srt", "vtt"] {
            pairs.append(DirectedPair(source: "txt", target: target, group: .document))
        }
        pairs.append(DirectedPair(source: "srt", target: "vtt", group: .document))
        pairs.append(DirectedPair(source: "srt", target: "txt", group: .document))
        pairs.append(DirectedPair(source: "vtt", target: "srt", group: .document))
        pairs.append(DirectedPair(source: "vtt", target: "txt", group: .document))

        for target in ["zip", "tar", "tar.gz", "gz"] {
            pairs.append(DirectedPair(source: "file", target: target, group: .archive))
        }
        for target in ["zip", "tar", "tar.gz"] {
            pairs.append(DirectedPair(source: "folder", target: target, group: .archive))
        }
        pairs.append(contentsOf: [
            DirectedPair(source: "zip", target: "tar", group: .archive),
            DirectedPair(source: "zip", target: "tar.gz", group: .archive),
            DirectedPair(source: "zip", target: "extract", group: .archive, label: "zip → extract"),
            DirectedPair(source: "tar", target: "zip", group: .archive),
            DirectedPair(source: "tar", target: "tar.gz", group: .archive),
            DirectedPair(source: "tar", target: "extract", group: .archive, label: "tar → extract"),
            DirectedPair(source: "tar.gz", target: "zip", group: .archive),
            DirectedPair(source: "tar.gz", target: "tar", group: .archive),
            DirectedPair(source: "tar.gz", target: "extract", group: .archive, label: "tar.gz → extract"),
            DirectedPair(source: "rar", target: "extract", group: .archive, label: "rar → extract"),
            DirectedPair(source: "gz", target: "file", group: .archive, label: "gz → file")
        ])
        return pairs
    }

    /// Pairs the wheel should offer. WMA encode is omitted when the ffmpeg build cannot do it.
    /// RAR extract stays listed; a missing `unar` fails the job and is explained in About.
    public static func offeredPairs(capabilities: EngineCapabilities) -> [DirectedPair] {
        definedPairs().filter { pair in
            if pair.target == "wma" && !capabilities.canEncodeWMA {
                return false
            }
            return true
        }
    }

    public static func gaps(capabilities: EngineCapabilities) -> [String] {
        var lines: [String] = []
        if !capabilities.canEncodeWMA {
            lines.append("WMA encode is hidden. This ffmpeg build has no WMA encoder.")
        }
        if !capabilities.canExtractRAR {
            lines.append(FileWheelMessages.rarBinaryMissing)
        }
        return lines
    }

    public static func targets(for file: FileInput) -> Set<String> {
        let ext = file.normalizedExtension
        if file.isDirectory {
            return Set(offeredPairs(capabilities: .allAvailable).filter { $0.source == "folder" }.map(\.target))
        }
        let sourceKey: String
        if ext == "svg" || ConversionCatalog.rasterFormats.contains(ext) || ext == "pdf" || ext == "txt" || ext == "srt" || ext == "vtt" || MediaClassifier.archiveExtensions.contains(ext) || ConversionCatalog.audioFormats.contains(ext) || ConversionCatalog.videoFormats.contains(ext) {
            sourceKey = ext
        } else if file.kind == .unknown || file.kind == .text || file.kind == .markdown || file.kind == .word {
            sourceKey = "file"
        } else {
            sourceKey = "file"
        }
        return Set(definedPairs().filter { $0.source == sourceKey }.map(\.target))
    }

    /// Targets every file in the drag can produce. Empty means the wheel has no runnable convert wedge.
    /// A PNG and an MP4 both name `gif`, but they are not the same action, so different kinds share nothing.
    public static func sharedTargets(for files: [FileInput]) -> Set<String> {
        guard let first = files.first else { return [] }
        let family = conversionFamily(first)
        guard files.allSatisfy({ conversionFamily($0) == family }) else { return [] }
        var shared = targets(for: first)
        for file in files.dropFirst() {
            shared.formIntersection(targets(for: file))
        }
        return shared
    }

    public static func conversionFamily(_ file: FileInput) -> String {
        if file.isDirectory {
            return "folder"
        }
        switch file.kind {
        case .image, .video, .audio, .pdf:
            return file.kind.rawValue
        case .archive, .subtitle, .text, .markdown, .word:
            return file.normalizedExtension.isEmpty ? file.kind.rawValue : "\(file.kind.rawValue):\(file.normalizedExtension)"
        case .folder:
            return "folder"
        case .unknown:
            return "file"
        }
    }
}
