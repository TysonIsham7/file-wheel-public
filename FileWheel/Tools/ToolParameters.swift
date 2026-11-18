import Foundation

public enum CompressMode: Equatable, Sendable {
    case quality(Double)
    case target(bytes: Int)
}

public struct CompressParameters: Equatable, Sendable {
    public var mode: CompressMode
    public var videoCodec: VideoCodecChoice
    public var maxDimension: Int

    public init(mode: CompressMode, videoCodec: VideoCodecChoice, maxDimension: Int) {
        self.mode = mode
        self.videoCodec = videoCodec
        self.maxDimension = maxDimension
    }
}

public enum AspectPreset: String, CaseIterable, Equatable, Sendable {
    case free
    case square
    case fourThree
    case sixteenNine
    case threeTwo

    public var title: String {
        switch self {
        case .free: return "Free"
        case .square: return "1:1"
        case .fourThree: return "4:3"
        case .sixteenNine: return "16:9"
        case .threeTwo: return "3:2"
        }
    }

    public var ratio: Double? {
        switch self {
        case .free: return nil
        case .square: return 1
        case .fourThree: return 4.0 / 3.0
        case .sixteenNine: return 16.0 / 9.0
        case .threeTwo: return 3.0 / 2.0
        }
    }
}

public struct CropImageParameters: Equatable, Sendable {
    public var rect: FWRect
    public var aspect: AspectPreset

    public init(rect: FWRect, aspect: AspectPreset = .free) {
        self.rect = rect
        self.aspect = aspect
    }
}

public struct AdjustImageParameters: Equatable, Sendable {
    public var exposure: Double
    public var contrast: Double
    public var saturation: Double
    public var sharpness: Double
    public var rotation: Int
    public var flipHorizontal: Bool
    public var flipVertical: Bool

    public init(exposure: Double = 0, contrast: Double = 1, saturation: Double = 1, sharpness: Double = 0, rotation: Int = 0, flipHorizontal: Bool = false, flipVertical: Bool = false) {
        self.exposure = exposure
        self.contrast = contrast
        self.saturation = saturation
        self.sharpness = sharpness
        self.rotation = rotation
        self.flipHorizontal = flipHorizontal
        self.flipVertical = flipVertical
    }
}

public enum AnnotationMark: Equatable, Sendable {
    case pen(points: [FWPoint], width: Double)
    case text(String, at: FWPoint, size: Double)
    case rectangle(FWRect, width: Double)
    case arrow(from: FWPoint, to: FWPoint)
}

public struct AnnotateParameters: Equatable, Sendable {
    public var marks: [AnnotationMark]

    public init(marks: [AnnotationMark]) {
        self.marks = marks
    }
}

public struct RedactParameters: Equatable, Sendable {
    public var boxes: [RedactBox]

    public init(boxes: [RedactBox]) {
        self.boxes = boxes
    }
}

public struct TrimParameters: Equatable, Sendable {
    public var start: Double
    public var end: Double

    public init(start: Double, end: Double) {
        self.start = start
        self.end = end
    }
}

public struct CropVideoParameters: Equatable, Sendable {
    public var rect: FWRect

    public init(rect: FWRect) {
        self.rect = rect
    }
}

public enum SpeedRate: Equatable, Sendable {
    case preset(Double)
    case custom(Double)

    public var value: Double {
        switch self {
        case .preset(let rate), .custom(let rate):
            return rate
        }
    }

    public static let presets: [Double] = [0.25, 0.5, 1.5, 2]
}

public struct SpeedParameters: Equatable, Sendable {
    public var rate: SpeedRate

    public init(rate: SpeedRate) {
        self.rate = rate
    }
}

public enum SplitVideoMode: Equatable, Sendable {
    case playhead(Double)
    case equalParts(Int)
}

public struct SplitVideoParameters: Equatable, Sendable {
    public var mode: SplitVideoMode

    public init(mode: SplitVideoMode) {
        self.mode = mode
    }
}

public struct OrderedInputs: Equatable, Sendable {
    public var files: [FileInput]

    public init(files: [FileInput]) {
        self.files = files
    }
}

public enum SnapshotMode: Equatable, Sendable {
    case every(seconds: Double)
    case count(Int)
}

public struct SnapshotParameters: Equatable, Sendable {
    public var mode: SnapshotMode

    public init(mode: SnapshotMode) {
        self.mode = mode
    }
}

public struct BleepParameters: Equatable, Sendable {
    public var ranges: [TimeRange]
    public var word: String
    public var toneHz: Double

    public init(ranges: [TimeRange], word: String = "", toneHz: Double = 1000) {
        self.ranges = ranges
        self.word = word
        self.toneHz = toneHz
    }
}

public enum GPSEdit: Equatable, Sendable {
    case unchanged
    case clear
    case set(latitude: Double, longitude: Double)
}

public struct MetadataEdit: Equatable, Sendable {
    public var title: String
    public var author: String
    public var description: String
    public var creationDate: String
    public var gps: GPSEdit
    public var readOnlyTags: [String: String]

    public init(title: String = "", author: String = "", description: String = "", creationDate: String = "", gps: GPSEdit = .unchanged, readOnlyTags: [String: String] = [:]) {
        self.title = title
        self.author = author
        self.description = description
        self.creationDate = creationDate
        self.gps = gps
        self.readOnlyTags = readOnlyTags
    }
}

public enum SplitPDFMode: Equatable, Sendable {
    case ranges(String)
    case eachPage
}

public struct SplitPDFParameters: Equatable, Sendable {
    public var mode: SplitPDFMode

    public init(mode: SplitPDFMode) {
        self.mode = mode
    }
}

public struct PDFPageEdit: Equatable, Sendable, Identifiable {
    public var id: Int
    public var rotation: Int
    public var deleted: Bool

    public init(id: Int, rotation: Int = 0, deleted: Bool = false) {
        self.id = id
        self.rotation = rotation
        self.deleted = deleted
    }
}

public struct ReorganizeParameters: Equatable, Sendable {
    public var pages: [PDFPageEdit]

    public init(pages: [PDFPageEdit]) {
        self.pages = pages
    }
}

public enum PDFFitMode: String, CaseIterable, Equatable, Sendable {
    case fit
    case fill

    public var title: String {
        switch self {
        case .fit: return "Fit"
        case .fill: return "Fill"
        }
    }
}

public struct ImagesToPDFParameters: Equatable, Sendable {
    public var mode: PDFFitMode

    public init(mode: PDFFitMode = .fit) {
        self.mode = mode
    }
}

public enum CollageLayout: String, CaseIterable, Equatable, Sendable {
    case grid2x2
    case grid3x3
    case horizontal
    case vertical

    public var title: String {
        switch self {
        case .grid2x2: return "2×2"
        case .grid3x3: return "3×3"
        case .horizontal: return "Horizontal"
        case .vertical: return "Vertical"
        }
    }
}

public struct CollageParameters: Equatable, Sendable {
    public var layout: CollageLayout
    public var gap: Double
    public var background: RGBA

    public init(layout: CollageLayout = .horizontal, gap: Double = 8, background: RGBA = .white) {
        self.layout = layout
        self.gap = gap
        self.background = background
    }
}

public struct ReadQRParameters: Equatable, Sendable {
    public var saveAsText: Bool

    public init(saveAsText: Bool = false) {
        self.saveAsText = saveAsText
    }
}

public enum ArchiveFormat: String, CaseIterable, Equatable, Sendable {
    case zip
    case tar
    case tarGz
    case gz

    public var title: String {
        switch self {
        case .zip: return "zip"
        case .tar: return "tar"
        case .tarGz: return "tar.gz"
        case .gz: return "gz"
        }
    }

    public var fileExtension: String {
        switch self {
        case .zip: return "zip"
        case .tar: return "tar"
        case .tarGz: return "tar.gz"
        case .gz: return "gz"
        }
    }
}

public struct PackParameters: Equatable, Sendable {
    public var format: ArchiveFormat

    public init(format: ArchiveFormat = .zip) {
        self.format = format
    }
}

public enum ToolParameters: Equatable, Sendable {
    case compress(CompressParameters)
    case cropImage(CropImageParameters)
    case adjustImage(AdjustImageParameters)
    case annotate(AnnotateParameters)
    case redact(RedactParameters)
    case trimVideo(TrimParameters)
    case cropVideo(CropVideoParameters)
    case speed(SpeedParameters)
    case splitVideo(SplitVideoParameters)
    case joinVideos(OrderedInputs)
    case snapshots(SnapshotParameters)
    case normalize
    case trimAudio(TrimParameters)
    case bleep(BleepParameters)
    case channels(ChannelMode)
    case editMetadata(MetadataEdit)
    case stripMetadata
    case mergePDFs(OrderedInputs)
    case splitPDF(SplitPDFParameters)
    case reorganizePDF(ReorganizeParameters)
    case imagesToPDF(ImagesToPDFParameters)
    case collage(CollageParameters)
    case readQR(ReadQRParameters)
    case extractArchive
    case packArchive(PackParameters)
    case ocrPDF(OCRParameters)
    case signPDF(SignPDFParameters)
    case protectPDF(ProtectPDFParameters)
    case unlockPDF(UnlockPDFParameters)
}

extension ToolParameters {
    /// Drops password bytes from this value. Other settings stay as they are.
    public func scrubbed() -> ToolParameters {
        switch self {
        case .protectPDF(var value):
            PasswordMemory.clear(&value.password)
            PasswordMemory.clear(&value.confirm)
            PasswordMemory.clear(&value.ownerPassword)
            return .protectPDF(value)
        case .unlockPDF(var value):
            PasswordMemory.clear(&value.password)
            return .unlockPDF(value)
        default:
            return self
        }
    }
}

public struct ToolRunRequest: Sendable {
    public var tool: ToolID
    public var files: [FileInput]
    public var parameters: ToolParameters
    public var settings: FileWheelSettings

    public init(tool: ToolID, files: [FileInput], parameters: ToolParameters, settings: FileWheelSettings = .default) {
        self.tool = tool
        self.files = files
        self.parameters = parameters
        self.settings = settings
    }
}

public enum ToolParameterDefaults {
    public static func make(tool: ToolID, files: [FileInput], settings: FileWheelSettings = .default, channel: ChannelMode? = nil, pdfAccess: PDFLockAction? = nil) -> ToolParameters {
        switch tool {
        case .compress:
            return .compress(CompressParameters(mode: .quality(settings.jpegQuality), videoCodec: settings.videoCodec, maxDimension: settings.videoLongEdge))
        case .cropImage:
            return .cropImage(CropImageParameters(rect: FWRect(x: 0, y: 0, width: 32, height: 32)))
        case .adjustImage:
            return .adjustImage(AdjustImageParameters())
        case .annotate:
            return .annotate(AnnotateParameters(marks: []))
        case .redact:
            return .redact(RedactParameters(boxes: []))
        case .trimVideo, .trimAudio:
            return tool == .trimVideo ? .trimVideo(TrimParameters(start: 0, end: 1)) : .trimAudio(TrimParameters(start: 0, end: 1))
        case .cropVideo:
            return .cropVideo(CropVideoParameters(rect: FWRect(x: 0, y: 0, width: 16, height: 16)))
        case .speed:
            return .speed(SpeedParameters(rate: .preset(1.5)))
        case .splitVideo:
            return .splitVideo(SplitVideoParameters(mode: .equalParts(2)))
        case .joinVideos:
            return .joinVideos(OrderedInputs(files: files))
        case .snapshots:
            return .snapshots(SnapshotParameters(mode: .count(2)))
        case .normalizeAudio:
            return .normalize
        case .bleep:
            return .bleep(BleepParameters(ranges: []))
        case .channels:
            return .channels(channel ?? .mono)
        case .editMetadata:
            return .editMetadata(MetadataEdit())
        case .stripMetadata:
            return .stripMetadata
        case .mergePDFs:
            return .mergePDFs(OrderedInputs(files: files))
        case .splitPDF:
            return .splitPDF(SplitPDFParameters(mode: .eachPage))
        case .reorganizePDF:
            return .reorganizePDF(ReorganizeParameters(pages: []))
        case .imagesToPDF:
            return .imagesToPDF(ImagesToPDFParameters(mode: .fit))
        case .collage:
            return .collage(CollageParameters())
        case .readQR:
            return .readQR(ReadQRParameters())
        case .extractArchive:
            return .extractArchive
        case .packArchive:
            return .packArchive(PackParameters())
        case .ocrPDF:
            return .ocrPDF(OCRParameters())
        case .signPDF:
            return .signPDF(SignPDFParameters())
        case .protectPDF:
            if pdfAccess == .unlock {
                return .unlockPDF(UnlockPDFParameters())
            }
            return .protectPDF(ProtectPDFParameters())
        }
    }
}

public enum ToolValidation {
    public static func validate(_ request: ToolRunRequest) throws {
        guard ToolCatalog.isShown(request.tool, for: request.files) || request.tool == .joinVideos || request.tool == .mergePDFs else {
            throw ToolError.message("\(request.tool.title) does not apply to this selection.")
        }
        switch request.parameters {
        case .compress(let parameters):
            if case .target(let bytes) = parameters.mode, bytes <= 0 {
                throw ToolError.message("Enter a target size.")
            }
            if case .quality(let quality) = parameters.mode, quality <= 0 || quality > 1 {
                throw ToolError.message("Quality must be between 0 and 1.")
            }
        case .cropImage(let parameters):
            if parameters.rect.isEmpty { throw ToolError.message("Draw a crop rectangle.") }
        case .annotate(let parameters):
            if parameters.marks.isEmpty { throw ToolError.message("Add a mark before exporting.") }
        case .redact(let parameters):
            if parameters.boxes.isEmpty { throw ToolError.message("Draw at least one box.") }
        case .trimVideo(let parameters), .trimAudio(let parameters):
            if parameters.end <= parameters.start { throw ToolError.message("The out point has to be after the in point.") }
        case .speed(let parameters):
            if parameters.rate.value <= 0 { throw ToolError.message("Speed has to be greater than zero.") }
        case .splitVideo(let parameters):
            if case .equalParts(let count) = parameters.mode, count < 2 {
                throw ToolError.message("Split into at least two parts.")
            }
        case .bleep(let parameters):
            if parameters.ranges.isEmpty && parameters.word.trimmingCharacters(in: .whitespaces).isEmpty {
                throw ToolError.message("Mark at least one range.")
            }
        case .packArchive(let parameters):
            if parameters.format == .gz && (request.files.count != 1 || request.files[0].isDirectory) {
                throw ToolError.message("gz can only pack a single file.")
            }
        case .signPDF(let parameters):
            if parameters.imageJPEG.isEmpty || parameters.pixelWidth <= 0 || parameters.pixelHeight <= 0 {
                throw ToolError.message("Choose a signature.")
            }
            if parameters.placement == nil {
                throw ToolError.message("Click the page to place the signature.")
            }
        case .protectPDF(let parameters):
            var plan = try PDFProtectionPlan.make(
                password: parameters.password,
                confirm: parameters.confirm,
                ownerPassword: parameters.ownerPassword,
                allowPrinting: parameters.allowPrinting,
                allowCopying: parameters.allowCopying
            )
            PasswordMemory.clear(&plan.userPassword)
            PasswordMemory.clear(&plan.ownerPassword)
        case .unlockPDF(let parameters):
            if parameters.password.isEmpty {
                throw ToolError.message(PDFProtectValidation.enterCurrent)
            }
        default:
            break
        }
    }
}
