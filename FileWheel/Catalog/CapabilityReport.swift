import Foundation

public struct ImageIOCapabilities: Equatable, Sendable {
    public var encodesJPEG: Bool
    public var encodesPNG: Bool
    public var encodesGIF: Bool
    public var encodesTIFF: Bool
    public var encodesBMP: Bool
    public var encodesHEIC: Bool
    public var encodesWebP: Bool
    public var encodesAVIF: Bool

    public init(
        encodesJPEG: Bool = true,
        encodesPNG: Bool = true,
        encodesGIF: Bool = true,
        encodesTIFF: Bool = true,
        encodesBMP: Bool = true,
        encodesHEIC: Bool = true,
        encodesWebP: Bool = true,
        encodesAVIF: Bool = false
    ) {
        self.encodesJPEG = encodesJPEG
        self.encodesPNG = encodesPNG
        self.encodesGIF = encodesGIF
        self.encodesTIFF = encodesTIFF
        self.encodesBMP = encodesBMP
        self.encodesHEIC = encodesHEIC
        self.encodesWebP = encodesWebP
        self.encodesAVIF = encodesAVIF
    }

    public func encodes(_ target: String) -> Bool {
        switch target {
        case "jpg": return encodesJPEG
        case "png": return encodesPNG
        case "gif": return encodesGIF
        case "tif": return encodesTIFF
        case "bmp": return encodesBMP
        case "heic": return encodesHEIC
        case "webp": return encodesWebP
        case "avif": return encodesAVIF
        default: return false
        }
    }

    public static let none = ImageIOCapabilities(
        encodesJPEG: false,
        encodesPNG: false,
        encodesGIF: false,
        encodesTIFF: false,
        encodesBMP: false,
        encodesHEIC: false,
        encodesWebP: false,
        encodesAVIF: false
    )
}

public struct FFmpegCapabilities: Equatable, Sendable {
    public var binaryPresent: Bool
    public var versionLine: String?
    public var encoders: Set<String>
    public var muxers: Set<String>

    public init(
        binaryPresent: Bool,
        versionLine: String? = nil,
        encoders: Set<String> = [],
        muxers: Set<String> = []
    ) {
        self.binaryPresent = binaryPresent
        self.versionLine = versionLine
        self.encoders = encoders
        self.muxers = muxers
    }

    public static let missing = FFmpegCapabilities(binaryPresent: false)

    public func hasEncoder(_ name: String) -> Bool {
        encoders.contains(name)
    }

    public func hasMuxer(_ name: String) -> Bool {
        muxers.contains(name)
    }

    public static func parse(versionOutput: String, encodersOutput: String, muxersOutput: String) -> FFmpegCapabilities {
        let versionLine = versionOutput
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .first { $0.hasPrefix("ffmpeg version") }
        return FFmpegCapabilities(
            binaryPresent: true,
            versionLine: versionLine,
            encoders: parseToolList(encodersOutput, kind: .encoder),
            muxers: parseToolList(muxersOutput, kind: .muxer)
        )
    }

    private enum ListKind {
        case encoder
        case muxer
    }

    private static func parseToolList(_ text: String, kind: ListKind) -> Set<String> {
        var names: Set<String> = []
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            let parts = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard parts.count >= 2 else { continue }
            let flags = parts[0]
            let name = parts[1]
            guard name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }) else { continue }
            switch kind {
            case .encoder:
                guard flags.count == 6, let first = flags.first, "VAS".contains(first) else { continue }
                names.insert(name)
            case .muxer:
                guard flags.allSatisfy({ $0 == "D" || $0 == "E" }) else { continue }
                names.insert(name)
            }
        }
        return names
    }
}

public struct CapabilityGap: Equatable, Sendable {
    public let title: String
    public let detail: String

    public init(title: String, detail: String) {
        self.title = title
        self.detail = detail
    }
}

public struct CapabilityReport: Equatable, Sendable {
    public let ffmpegVersionLine: String?
    public let gaps: [CapabilityGap]
    public let livePairCount: Int
    public let catalogPairCount: Int

    public init(
        ffmpegVersionLine: String?,
        gaps: [CapabilityGap],
        livePairCount: Int,
        catalogPairCount: Int
    ) {
        self.ffmpegVersionLine = ffmpegVersionLine
        self.gaps = gaps
        self.livePairCount = livePairCount
        self.catalogPairCount = catalogPairCount
    }

    /// Text for About. Phase 1 should pass the merged catalog when it lands.
    public var aboutText: String {
        var lines = [
            "File Wheel",
            "Supported conversions in this build: \(livePairCount)",
            "Catalog pairs: \(catalogPairCount)",
        ]
        if let ffmpegVersionLine {
            lines.append("ffmpeg: \(ffmpegVersionLine)")
        } else {
            lines.append("ffmpeg: \(FileWheelMessages.ffmpegMissing)")
        }
        if gaps.isEmpty {
            lines.append("Gaps: none")
        } else {
            lines.append("Gaps:")
            for gap in gaps {
                lines.append("- \(gap.title). \(gap.detail)")
            }
        }
        return lines.joined(separator: "\n")
    }
}

public enum CapabilityReportBuilder {
    public static func make(
        entries: [CatalogEntry] = ConversionCatalog.entries,
        capabilities: FFmpegCapabilities,
        imageIO: ImageIOCapabilities
    ) -> CapabilityReport {
        let visible = entries.filter {
            !ConversionCatalog.isHidden($0, capabilities: capabilities, imageIO: imageIO)
        }
        return CapabilityReport(
            ffmpegVersionLine: capabilities.versionLine,
            gaps: gaps(entries: entries, capabilities: capabilities, imageIO: imageIO),
            livePairCount: visible.count,
            catalogPairCount: entries.count
        )
    }

    static func gaps(
        entries: [CatalogEntry],
        capabilities: FFmpegCapabilities,
        imageIO: ImageIOCapabilities
    ) -> [CapabilityGap] {
        var gaps: [CapabilityGap] = []
        if !capabilities.binaryPresent {
            gaps.append(
                CapabilityGap(
                    title: "ffmpeg was not found",
                    detail: "\(FileWheelMessages.ffmpegMissing) Formats that need ffmpeg are hidden."
                )
            )
        } else {
            let hidden = entries.filter {
                ConversionCatalog.isHidden($0, capabilities: capabilities, imageIO: imageIO)
            }
            let hiddenTargets = Set(hidden.map(\.target))
            if hiddenTargets.contains("wma") {
                gaps.append(
                    CapabilityGap(
                        title: "WMA encode is unavailable",
                        detail: "This ffmpeg build has no WMA encoder. WMA output wedges are hidden."
                    )
                )
            }
            for target in hiddenTargets.sorted() where target != "wma" {
                let label = KnownFormats.displayName(id: target)
                gaps.append(
                    CapabilityGap(
                        title: "\(label) encode is unavailable",
                        detail: "Those wedges are hidden because neither ImageIO nor ffmpeg can write \(label)."
                    )
                )
            }
        }
        return gaps
    }
}
