import Foundation

/// Phase 2 catalog: AVIF, BMP, SVG, the audio matrix, and the video matrix.
/// Phase 1 owns JPEG/PNG/WebP/TIFF/HEIC/GIF pairs among themselves. Those pairs are not repeated here.
public enum ConversionCatalog {
    public static let phase1ImageIDs: Set<String> = ["jpg", "png", "webp", "heic", "tif", "gif"]
    public static let phase2ImageIDs: Set<String> = ["avif", "bmp"]
    public static let rasterIDs: Set<String> = phase1ImageIDs.union(phase2ImageIDs)
    public static let audioIDs: [String] = ["mp3", "m4a", "wav", "flac", "ogg", "opus", "aiff", "wma"]
    public static let avFoundationAudioIDs: Set<String> = ["m4a", "wav", "aiff", "mp3"]
    public static let ffmpegAudioIDs: Set<String> = ["flac", "ogg", "opus", "wma"]
    public static let videoContainerIDs: [String] = ["mp4", "mov", "mkv", "webm", "avi", "wmv"]
    public static let avFoundationVideoIDs: Set<String> = ["mp4", "mov"]

    public static let entries: [CatalogEntry] = imageEntries + audioEntries + videoEntries

    /// JPEG/PNG/WebP/TIFF/HEIC/GIF pairs. Kept out of `entries` so the Phase 2
    /// matrix stays a separate list. The wheel reads `wheelEntries`.
    public static let phase1StillEntries: [CatalogEntry] = {
        let ids = ["jpg", "png", "webp", "heic", "tif", "gif"]
        var rows: [CatalogEntry] = []
        for source in ids {
            for target in ids where source != target {
                rows.append(
                    CatalogEntry(
                        source: source,
                        target: target,
                        kind: .image,
                        label: KnownFormats.displayName(id: target),
                        engine: .imageIOThenFFmpeg
                    )
                )
            }
        }
        return rows
    }()

    /// Document, archive, and Listen rows. Listen uses engine `.readAloud` and is not a pair.
    public static let phase3Entries: [CatalogEntry] = {
        func row(_ source: String, _ target: String, _ label: String, _ kind: MediaKind, _ engine: EnginePreference) -> CatalogEntry {
            CatalogEntry(source: source, target: target, kind: kind, label: label, engine: engine)
        }
        var rows: [CatalogEntry] = []
        let documents: [(String, String, String, MediaKind)] = [
            ("pdf", "docx", "DOCX", .pdf),
            ("pdf", "jpg", "JPG", .pdf),
            ("pdf", "png", "PNG", .pdf),
            ("pdf", "txt", "TXT", .pdf),
            ("txt", "pdf", "PDF", .text),
            ("txt", "jpg", "JPG", .text),
            ("txt", "png", "PNG", .text),
            ("txt", "srt", "SRT", .text),
            ("txt", "vtt", "VTT", .text),
            ("srt", "vtt", "VTT", .subtitle),
            ("srt", "txt", "TXT", .subtitle),
            ("vtt", "srt", "SRT", .subtitle),
            ("vtt", "txt", "TXT", .subtitle),
        ]
        rows += documents.map { row($0.0, $0.1, $0.2, $0.3, .document) }
        let archives: [(String, String, String)] = [
            ("zip", "tar", "TAR"),
            ("zip", "tar.gz", "TAR.GZ"),
            ("zip", "extract", "Extract"),
            ("tar", "zip", "ZIP"),
            ("tar", "tar.gz", "TAR.GZ"),
            ("tar", "extract", "Extract"),
            ("tar.gz", "zip", "ZIP"),
            ("tar.gz", "tar", "TAR"),
            ("tar.gz", "extract", "Extract"),
            ("rar", "extract", "Extract"),
            ("gz", "extract", "Extract"),
        ]
        rows += archives.map { row($0.0, $0.1, $0.2, .archive, .archive) }
        for source in ["txt", "md", "pdf", "docx", "srt", "vtt"] {
            rows.append(row(source, "mp3", "Listen (MP3)", .text, .readAloud))
        }
        return rows
    }()

    /// Pack wedges. A folder cannot pack to gz. These are not in `entries(from:)` because the source is not a format id.
    public static func packEntries(allowsFolders: Bool) -> [CatalogEntry] {
        var rows = [
            CatalogEntry(source: "pack", target: "zip", kind: .archive, label: "ZIP", engine: .archive),
            CatalogEntry(source: "pack", target: "tar", kind: .archive, label: "TAR", engine: .archive),
            CatalogEntry(source: "pack", target: "tar.gz", kind: .archive, label: "TAR.GZ", engine: .archive),
        ]
        if !allowsFolders {
            rows.append(CatalogEntry(source: "pack", target: "gz", kind: .archive, label: "GZ", engine: .archive))
        }
        return rows
    }

    /// Phase 1 stills, the Phase 2 catalog, and Phase 3 documents, archives, and Listen.
    public static var wheelEntries: [CatalogEntry] {
        phase1StillEntries + entries + phase3Entries
    }

    public static func entries(from sourceID: String) -> [CatalogEntry] {
        wheelEntries.filter { $0.source == sourceID }
    }

    public static func offer(
        files: [SourceFile],
        capabilities: FFmpegCapabilities,
        imageIO: ImageIOCapabilities
    ) -> WheelOffer {
        if files.isEmpty {
            return WheelOffer(message: nil, wedges: [])
        }
        if files.contains(where: \.isDirectory) {
            if files.allSatisfy(\.isDirectory) {
                return WheelOffer(message: nil, wedges: [])
            }
            return WheelOffer(message: "Same kind of file required", wedges: [])
        }

        let formats = files.map { KnownFormats.canonical(extension: $0.fileExtension) }
        if files.count >= 2 {
            let ids = Set(formats.compactMap { $0?.id })
            if formats.contains(where: { $0 == nil }) || ids.count != 1 {
                return WheelOffer(message: "Same kind of file required", wedges: [])
            }
        }
        guard let format = formats.first ?? nil else {
            if files.count == 1 {
                let wedges = packEntries(allowsFolders: false).map { Wedge(entry: $0, state: .enabled) }
                return WheelOffer(message: nil, wedges: wedges)
            }
            return WheelOffer(message: nil, wedges: [])
        }

        var wedges = entries(from: format.id).map { entry in
            Wedge(entry: entry, state: wedgeState(entry, files: files, capabilities: capabilities, imageIO: imageIO))
        }
        let archives: Set<String> = ["zip", "tar", "tar.gz", "gz", "rar"]
        let timedMedia = ConversionCatalog.rasterIDs
            .union(ConversionCatalog.audioIDs)
            .union(ConversionCatalog.videoContainerIDs)
            .union(["svg"])
        if files.count == 1, !archives.contains(format.id), !timedMedia.contains(format.id) {
            wedges += packEntries(allowsFolders: false).map { Wedge(entry: $0, state: .enabled) }
        }
        return WheelOffer(message: nil, wedges: wedges)
    }

    public static func wedgeState(
        _ entry: CatalogEntry,
        files: [SourceFile],
        capabilities: FFmpegCapabilities,
        imageIO: ImageIOCapabilities
    ) -> WedgeState {
        if isHidden(entry, capabilities: capabilities, imageIO: imageIO) {
            return .hidden
        }
        if entry.kind == .video, entry.target == "mp3", files.contains(where: { $0.hasAudio == false }) {
            return .disabled(reason: "No audio")
        }
        return .enabled
    }

    public static func isHidden(
        _ entry: CatalogEntry,
        capabilities: FFmpegCapabilities,
        imageIO: ImageIOCapabilities
    ) -> Bool {
        switch entry.engine {
        case .svgWrap:
            return false
        case .svgRasterize, .imageIOThenFFmpeg:
            return !canEncodeStill(entry.target, capabilities: capabilities, imageIO: imageIO)
        case .avFoundation:
            return false
        case .ffmpeg:
            guard capabilities.binaryPresent else { return true }
            return !ffmpegCanWrite(entry.target, capabilities: capabilities)
        case .document, .archive, .readAloud, .tool:
            return false
        }
    }

    public static func canEncodeStill(
        _ target: String,
        capabilities: FFmpegCapabilities,
        imageIO: ImageIOCapabilities
    ) -> Bool {
        if imageIO.encodes(target) {
            return true
        }
        guard capabilities.binaryPresent else { return false }
        return ffmpegCanWrite(target, capabilities: capabilities)
    }

    /// True when this ffmpeg build can encode `target`. AVFoundation-only targets return false here.
    public static func ffmpegCanWrite(_ target: String, capabilities: FFmpegCapabilities) -> Bool {
        guard capabilities.binaryPresent else { return false }
        switch target {
        case "mp3":
            return capabilities.hasEncoder("libmp3lame") && capabilities.hasMuxer("mp3")
        case "m4a":
            return capabilities.hasEncoder("aac") && (capabilities.hasMuxer("ipod") || capabilities.hasMuxer("mp4"))
        case "wav":
            return capabilities.hasEncoder("pcm_s16le") && capabilities.hasMuxer("wav")
        case "aiff":
            return capabilities.hasEncoder("pcm_s16be") && capabilities.hasMuxer("aiff")
        case "flac":
            return capabilities.hasEncoder("flac") && capabilities.hasMuxer("flac")
        case "ogg":
            return capabilities.hasEncoder("libvorbis") && capabilities.hasMuxer("ogg")
        case "opus":
            return capabilities.hasEncoder("libopus") && capabilities.hasMuxer("opus")
        case "wma":
            return capabilities.hasEncoder("wmav2") && capabilities.hasMuxer("asf")
        case "mp4":
            return capabilities.hasMuxer("mp4") && hasH264(capabilities)
        case "mov":
            return capabilities.hasMuxer("mov") && hasH264(capabilities)
        case "mkv":
            return capabilities.hasMuxer("matroska") && hasH264(capabilities)
        case "webm":
            return capabilities.hasMuxer("webm")
                && (capabilities.hasEncoder("libvpx-vp9") || capabilities.hasEncoder("libvpx"))
                && capabilities.hasEncoder("libopus")
        case "avi":
            return capabilities.hasMuxer("avi") && capabilities.hasEncoder("mpeg4")
        case "wmv":
            return capabilities.hasMuxer("asf") && capabilities.hasEncoder("wmv2") && capabilities.hasEncoder("wmav2")
        case "gif":
            return capabilities.hasMuxer("gif") && capabilities.hasEncoder("gif")
        case "avif":
            return capabilities.hasMuxer("avif") && capabilities.hasEncoder("libaom-av1")
        case "bmp":
            return capabilities.hasEncoder("bmp")
        case "webp":
            return capabilities.hasEncoder("libwebp")
        case "jpg", "png", "tif":
            return capabilities.hasMuxer("image2")
        case "heic":
            return capabilities.hasMuxer("heic") || capabilities.hasMuxer("heif")
        default:
            return false
        }
    }

    private static func hasH264(_ capabilities: FFmpegCapabilities) -> Bool {
        capabilities.hasEncoder("libx264") || capabilities.hasEncoder("h264_videotoolbox")
    }

    private static var imageEntries: [CatalogEntry] {
        var rows: [CatalogEntry] = []
        let rasters = rasterIDs.sorted()
        for source in rasters {
            for target in rasters where source != target {
                let added = phase2ImageIDs.contains(source) || phase2ImageIDs.contains(target)
                guard added else { continue }
                rows.append(
                    CatalogEntry(
                        source: source,
                        target: target,
                        kind: .image,
                        label: KnownFormats.displayName(id: target),
                        engine: .imageIOThenFFmpeg
                    )
                )
            }
        }
        for target in rasters.sorted() {
            rows.append(
                CatalogEntry(
                    source: "svg",
                    target: target,
                    kind: .image,
                    label: KnownFormats.displayName(id: target),
                    engine: .svgRasterize
                )
            )
        }
        for source in (rasters + ["svg"]).sorted() where source != "svg" {
            rows.append(
                CatalogEntry(
                    source: source,
                    target: "svg",
                    kind: .image,
                    label: "SVG (wrapped)",
                    engine: .svgWrap
                )
            )
        }
        // svg → svg is omitted. A raster source already added svg above; svg itself is not a wrap source of itself.
        return rows.sorted { $0.id < $1.id }
    }

    private static var audioEntries: [CatalogEntry] {
        var rows: [CatalogEntry] = []
        for source in audioIDs {
            for target in audioIDs where source != target {
                let native = avFoundationAudioIDs.contains(source) && avFoundationAudioIDs.contains(target)
                rows.append(
                    CatalogEntry(
                        source: source,
                        target: target,
                        kind: .audio,
                        label: KnownFormats.displayName(id: target),
                        engine: native ? .avFoundation : .ffmpeg
                    )
                )
            }
        }
        return rows
    }

    private static var videoEntries: [CatalogEntry] {
        var rows: [CatalogEntry] = []
        let targets = videoContainerIDs + ["gif", "mp3"]
        for source in videoContainerIDs {
            for target in targets where source != target {
                rows.append(
                    CatalogEntry(
                        source: source,
                        target: target,
                        kind: .video,
                        label: KnownFormats.displayName(id: target),
                        engine: videoEngine(source: source, target: target)
                    )
                )
            }
        }
        return rows
    }

    static func videoEngine(source: String, target: String) -> EnginePreference {
        if target == "gif" {
            return .ffmpeg
        }
        if target == "mp3" {
            return avFoundationVideoIDs.contains(source) ? .avFoundation : .ffmpeg
        }
        if avFoundationVideoIDs.contains(source) && avFoundationVideoIDs.contains(target) {
            return .avFoundation
        }
        return .ffmpeg
    }
}
