import Foundation

public enum ToolID: String, CaseIterable, Codable, Sendable, Identifiable, Equatable {
    case compress
    case cropImage
    case adjustImage
    case annotate
    case redact
    case trimVideo
    case cropVideo
    case speed
    case splitVideo
    case joinVideos
    case snapshots
    case normalizeAudio
    case trimAudio
    case bleep
    case channels
    case editMetadata
    case stripMetadata
    case mergePDFs
    case splitPDF
    case reorganizePDF
    case imagesToPDF
    case collage
    case readQR
    case extractArchive
    case packArchive
    case ocrPDF
    case signPDF
    case protectPDF

    public var id: String { rawValue }

    public var number: Int {
        switch self {
        case .compress: return 1
        case .cropImage: return 2
        case .adjustImage: return 3
        case .annotate: return 4
        case .redact: return 5
        case .trimVideo: return 6
        case .cropVideo: return 7
        case .speed: return 8
        case .splitVideo: return 9
        case .joinVideos: return 10
        case .snapshots: return 11
        case .normalizeAudio: return 12
        case .trimAudio: return 13
        case .bleep: return 14
        case .channels: return 15
        case .editMetadata: return 16
        case .stripMetadata: return 17
        case .mergePDFs: return 18
        case .splitPDF: return 19
        case .reorganizePDF: return 20
        case .imagesToPDF: return 21
        case .collage: return 22
        case .readQR: return 23
        case .extractArchive: return 24
        case .packArchive: return 25
        case .ocrPDF: return 26
        case .signPDF: return 27
        case .protectPDF: return 28
        }
    }

    public var title: String {
        switch self {
        case .compress: return "Compress"
        case .cropImage: return "Crop image"
        case .adjustImage: return "Adjust image"
        case .annotate: return "Annotate"
        case .redact: return "Redact"
        case .trimVideo: return "Trim video"
        case .cropVideo: return "Crop video"
        case .speed: return "Speed"
        case .splitVideo: return "Split video"
        case .joinVideos: return "Join videos"
        case .snapshots: return "Snapshots"
        case .normalizeAudio: return "Normalize audio"
        case .trimAudio: return "Trim audio"
        case .bleep: return "Bleep"
        case .channels: return "Channels"
        case .editMetadata: return "Edit metadata"
        case .stripMetadata: return "Strip metadata"
        case .mergePDFs: return "Merge PDFs"
        case .splitPDF: return "Split PDF"
        case .reorganizePDF: return "Reorganize PDF"
        case .imagesToPDF: return "Images to PDF"
        case .collage: return "Collage"
        case .readQR: return "Read QR"
        case .extractArchive: return "Extract archive"
        case .packArchive: return "Pack archive"
        case .ocrPDF: return "OCR PDF"
        case .signPDF: return "Sign PDF"
        case .protectPDF: return "Protect PDF"
        }
    }

    public var summary: String {
        switch self {
        case .compress:
            return "Quality slider or a target size. Video adds codec and max dimension."
        case .cropImage:
            return "Crop one image to a rectangle. Aspect presets included."
        case .adjustImage:
            return "Exposure, contrast, saturation, sharpness, rotate, and flip."
        case .annotate:
            return "Pen, text, rectangle, and arrow. Exports a flattened copy."
        case .redact:
            return "Black boxes. PDF redaction removes the text underneath."
        case .trimVideo:
            return "In and out points on a filmstrip."
        case .cropVideo:
            return "One rectangle applied to the whole duration."
        case .speed:
            return "0.25×, 0.5×, 1.5×, 2×, or a custom rate. Pitch stays natural."
        case .splitVideo:
            return "Split at the playhead or into equal parts."
        case .joinVideos:
            return "Join two or more videos. Mixed sizes scale to the first clip."
        case .snapshots:
            return "Stills every N seconds, or a count spread across the duration."
        case .normalizeAudio:
            return "Loudness-normalize audio, or a video’s audio track."
        case .trimAudio:
            return "In and out on the waveform."
        case .bleep:
            return "Replace marked ranges with a tone. Word search uses on-device recognition when it returns timings."
        case .channels:
            return "Mono, stereo, left only, right only, or swap."
        case .editMetadata:
            return "Title, author, description, creation date, and GPS."
        case .stripMetadata:
            return "Remove EXIF, XMP, GPS, and container tags."
        case .mergePDFs:
            return "Merge two or more PDFs."
        case .splitPDF:
            return "Page ranges, or one file per page."
        case .reorganizePDF:
            return "Reorder, delete, and rotate pages."
        case .imagesToPDF:
            return "One page per image, in drag order. Drop fits the page."
        case .collage:
            return "Grid, horizontal, or vertical, with gap and background."
        case .readQR:
            return "List every code. Nothing is written unless you save a text file."
        case .extractArchive:
            return "Extract zip, tar, tar.gz, gz, or rar beside the archive."
        case .packArchive:
            return "Pack files or a folder as zip, tar, tar.gz, or gz."
        case .ocrPDF:
            return "Make a PDF or image searchable. Recognition stays on this Mac."
        case .signPDF:
            return "Place a saved signature, text, and a date. This is a visual signature, not a cryptographic digital signature."
        case .protectPDF:
            return "Protect writes an encrypted copy. Unlock writes a decrypted copy. Passwords stay in memory only."
        }
    }
}

public enum ChannelMode: String, CaseIterable, Codable, Sendable, Equatable {
    case mono
    case stereo
    case left
    case right
    case swap

    public var title: String {
        switch self {
        case .mono: return "Mono"
        case .stereo: return "Stereo"
        case .left: return "Left only"
        case .right: return "Right only"
        case .swap: return "Swap"
        }
    }
}

public enum ToolPresentation: String, Equatable, Sendable {
    /// Runs as soon as the wedge is chosen.
    case runOnDrop
    /// Opens a parameter panel and runs on confirm.
    case openPanel
    /// Runs on drop, then shows a result panel. Read QR writes nothing until Save as TXT.
    case runOnDropThenShowResult
}

public struct WheelEntry: Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var tool: ToolID
    public var presentation: ToolPresentation
    public var channel: ChannelMode?
    public var pdfAccess: PDFLockAction?

    public init(id: String, title: String, tool: ToolID, presentation: ToolPresentation, channel: ChannelMode? = nil, pdfAccess: PDFLockAction? = nil) {
        self.id = id
        self.title = title
        self.tool = tool
        self.presentation = presentation
        self.channel = channel
        self.pdfAccess = pdfAccess
    }

    public var runsOnDrop: Bool {
        presentation != .openPanel
    }
}

public enum ToolCatalog {
    public static func isShown(_ tool: ToolID, for files: [FileInput]) -> Bool {
        switch tool {
        case .compress, .editMetadata, .stripMetadata:
            return all(files, isCompressible)
        case .cropImage, .adjustImage, .annotate:
            return single(files) { $0.kind == .image }
        case .redact:
            return single(files) { $0.kind == .image || $0.kind == .pdf }
        case .trimVideo, .cropVideo, .speed, .splitVideo, .snapshots:
            return single(files) { $0.kind == .video }
        case .joinVideos:
            return files.count >= 2 && files.allSatisfy { $0.kind == .video }
        case .normalizeAudio:
            return all(files) { $0.kind == .audio } || all(files) { $0.kind == .video }
        case .trimAudio, .channels:
            return single(files) { $0.kind == .audio }
        case .bleep:
            return single(files) { $0.kind == .audio || $0.kind == .video }
        case .mergePDFs:
            return files.count >= 2 && files.allSatisfy { $0.kind == .pdf }
        case .splitPDF, .reorganizePDF:
            return single(files) { $0.kind == .pdf }
        case .imagesToPDF:
            return all(files) { $0.kind == .image }
        case .collage:
            return files.count >= 2 && files.allSatisfy { $0.kind == .image }
        case .readQR:
            return single(files) { $0.kind == .image || $0.kind == .pdf }
        case .extractArchive:
            return all(files) { MediaClassifier.archiveExtensions.contains($0.normalizedExtension) }
        case .packArchive:
            return !files.isEmpty
        case .ocrPDF:
            return single(files) { $0.kind == .pdf || $0.kind == .image }
        case .signPDF, .protectPDF:
            return single(files) { $0.kind == .pdf }
        }
    }

    public static func presentation(_ tool: ToolID, for files: [FileInput]) -> ToolPresentation {
        switch tool {
        case .normalizeAudio, .stripMetadata, .extractArchive, .imagesToPDF:
            return .runOnDrop
        case .channels:
            return .runOnDrop
        case .joinVideos:
            return files.count >= 2 ? .runOnDrop : .openPanel
        case .mergePDFs:
            return files.count >= 2 ? .runOnDrop : .openPanel
        case .readQR:
            return .runOnDropThenShowResult
        case .ocrPDF:
            return .runOnDrop
        default:
            return .openPanel
        }
    }

    public static func wheelEntries(for files: [FileInput]) -> [WheelEntry] {
        var entries: [WheelEntry] = []
        for tool in ToolID.allCases where isShown(tool, for: files) {
            if tool == .channels {
                for mode in ChannelMode.allCases {
                    entries.append(WheelEntry(
                        id: "channels.\(mode.rawValue)",
                        title: mode.title,
                        tool: .channels,
                        presentation: .runOnDrop,
                        channel: mode
                    ))
                }
            } else if tool == .ocrPDF {
                entries.append(WheelEntry(
                    id: tool.rawValue,
                    title: tool.title,
                    tool: tool,
                    presentation: .runOnDrop
                ))
                entries.append(WheelEntry(
                    id: "ocrPDF.options",
                    title: "OCR options",
                    tool: tool,
                    presentation: .openPanel
                ))
            } else if tool == .protectPDF {
                for action in PDFLockAction.allCases {
                    entries.append(WheelEntry(
                        id: "protectPDF.\(action.rawValue)",
                        title: action.title,
                        tool: .protectPDF,
                        presentation: .openPanel,
                        pdfAccess: action
                    ))
                }
            } else {
                entries.append(WheelEntry(
                    id: tool.rawValue,
                    title: tool.title,
                    tool: tool,
                    presentation: presentation(tool, for: files)
                ))
            }
        }
        return entries
    }

    public static func weight(for tool: ToolID, files: [FileInput]) -> JobWeight {
        let imageTools: Set<ToolID> = [.cropImage, .adjustImage, .annotate, .collage]
        if tool == .redact && files.allSatisfy({ $0.kind == .image }) {
            return .image
        }
        if tool == .compress && files.allSatisfy({ $0.kind == .image }) {
            return .image
        }
        if tool == .stripMetadata && files.allSatisfy({ $0.kind == .image }) {
            return .image
        }
        if tool == .editMetadata && files.allSatisfy({ $0.kind == .image }) {
            return .image
        }
        if imageTools.contains(tool) {
            return .image
        }
        return .heavy
    }

    private static func isCompressible(_ file: FileInput) -> Bool {
        switch file.kind {
        case .image, .video, .audio, .pdf:
            return true
        default:
            return false
        }
    }

    private static func all(_ files: [FileInput], _ predicate: (FileInput) -> Bool) -> Bool {
        !files.isEmpty && files.allSatisfy(predicate)
    }

    private static func single(_ files: [FileInput], _ predicate: (FileInput) -> Bool) -> Bool {
        files.count == 1 && predicate(files[0])
    }
}

public enum JobWeight: String, Equatable, Sendable {
    case image
    case heavy
}
