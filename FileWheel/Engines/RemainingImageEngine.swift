import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

extension ImageIOCapabilities {
    public static func current() -> ImageIOCapabilities {
        let identifiers = Set((CGImageDestinationCopyTypeIdentifiers() as? [String]) ?? [])
        func has(_ type: UTType?) -> Bool {
            guard let type else { return false }
            return identifiers.contains(type.identifier)
        }
        return ImageIOCapabilities(
            encodesJPEG: has(.jpeg),
            encodesPNG: has(.png),
            encodesGIF: has(.gif),
            encodesTIFF: has(.tiff),
            encodesBMP: has(.bmp),
            encodesHEIC: has(.heic),
            encodesWebP: has(.webP),
            encodesAVIF: has(UTType("public.avif"))
        )
    }
}

public struct RemainingImageEngine: Sendable {
    public var ffmpeg: FFmpegEngine
    public var imageIO: ImageIOCapabilities

    public init(ffmpeg: FFmpegEngine, imageIO: ImageIOCapabilities) {
        self.ffmpeg = ffmpeg
        self.imageIO = imageIO
    }

    public func convert(_ job: EngineJob) async throws {
        if job.cancel.isCancelled {
            throw ConversionError.cancelled
        }
        switch job.entry.engine {
        case .svgWrap:
            try SVGDocument.wrap(source: job.source, destination: job.tempOutput)
        case .svgRasterize:
            let image = try await SVGDocument.rasterize(url: job.source, dpi: job.options.resolvedSVGDPI)
            try await write(image, job: job)
        case .imageIOThenFFmpeg:
            if let image = StillImage.read(job.source) {
                try await write(image, job: job)
            } else {
                try await ffmpegStill(source: job.source, job: job)
            }
        default:
            throw ConversionError.failed("This image engine does not handle \(job.entry.source) to \(job.entry.target)")
        }
    }

    private func write(_ image: CGImage, job: EngineJob) async throws {
        if job.entry.target == "svg" {
            try SVGDocument.wrap(image: image, destination: job.tempOutput)
            return
        }
        if imageIO.encodes(job.entry.target), let type = StillImage.utType(for: job.entry.target) {
            try StillImage.write(image, to: job.tempOutput, type: type, quality: quality(for: job))
            return
        }
        let png = job.tempOutput
            .deletingLastPathComponent()
            .appendingPathComponent(".\(UUID().uuidString).filewheel.png")
        try StillImage.write(image, to: png, type: .png, quality: nil)
        defer { try? FileManager.default.removeItem(at: png) }
        try await ffmpegStill(source: png, job: job)
    }

    private func ffmpegStill(source: URL, job: EngineJob) async throws {
        let entry = CatalogEntry(
            source: "png",
            target: job.entry.target,
            kind: .image,
            label: job.entry.label,
            engine: .ffmpeg
        )
        let still = EngineJob(
            source: source,
            tempOutput: job.tempOutput,
            entry: entry,
            options: job.options,
            cancel: job.cancel
        )
        try await ffmpeg.convert(still)
    }

    private func quality(for job: EngineJob) -> Double? {
        switch job.entry.target {
        case "jpg", "webp", "heic", "avif":
            return job.options.jpegQuality
        default:
            return nil
        }
    }
}

enum StillImage {
    static func utType(for target: String) -> UTType? {
        switch target {
        case "jpg": return .jpeg
        case "png": return .png
        case "gif": return .gif
        case "tif": return .tiff
        case "bmp": return .bmp
        case "heic": return .heic
        case "webp": return .webP
        case "avif": return UTType("public.avif")
        default: return nil
        }
    }

    static func read(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    static func write(_ image: CGImage, to url: URL, type: UTType, quality: Double?) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else {
            throw ConversionError.failed("Could not create a \(type.identifier) file")
        }
        var properties: [CFString: Any] = [:]
        if let quality {
            properties[kCGImageDestinationLossyCompressionQuality] = quality
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw ConversionError.failed("Could not write \(url.pathExtension)")
        }
    }

    static func pngData(from image: CGImage) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw ConversionError.failed("Could not encode PNG")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw ConversionError.failed("Could not encode PNG")
        }
        return data as Data
    }
}

enum SVGDocument {
    static func wrap(source: URL, destination: URL) throws {
        let ext = MediaFormat.normalize(source.pathExtension)
        if ["png", "jpg", "jpeg", "gif"].contains(ext) {
            let data = try Data(contentsOf: source)
            let mime: String
            switch ext {
            case "jpg", "jpeg": mime = "image/jpeg"
            case "gif": mime = "image/gif"
            default: mime = "image/png"
            }
            let image = StillImage.read(source)
            let width = image.map { $0.width } ?? 1
            let height = image.map { $0.height } ?? 1
            try writeWrapped(payload: data, mime: mime, width: width, height: height, to: destination)
            return
        }
        guard let image = StillImage.read(source) else {
            throw ConversionError.failed("Could not read the image to wrap")
        }
        try wrap(image: image, destination: destination)
    }

    static func wrap(image: CGImage, destination: URL) throws {
        let png = try StillImage.pngData(from: image)
        try writeWrapped(payload: png, mime: "image/png", width: image.width, height: image.height, to: destination)
    }

    static func rasterize(url: URL, dpi: Int) async throws -> CGImage {
        try await MainActor.run {
            try rasterizeOnMain(url: url, dpi: dpi)
        }
    }

    @MainActor
    private static func rasterizeOnMain(url: URL, dpi: Int) throws -> CGImage {
        guard let image = NSImage(contentsOf: url), image.isValid else {
            throw ConversionError.failed("Could not read SVG")
        }
        var points = image.size
        if points.width < 1 || points.height < 1 {
            points = NSSize(width: 256, height: 256)
        }
        let scale = CGFloat(dpi) / 72
        let width = max(1, Int((points.width * scale).rounded()))
        let height = max(1, Int((points.height * scale).rounded()))
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            throw ConversionError.failed("Could not allocate an SVG bitmap")
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.clear.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        image.draw(in: NSRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        NSGraphicsContext.restoreGraphicsState()
        guard let rendered = rep.cgImage else {
            throw ConversionError.failed("SVG rasterize produced no image")
        }
        return rendered
    }

    private static func writeWrapped(payload: Data, mime: String, width: Int, height: Int, to destination: URL) throws {
        let encoded = payload.base64EncodedString()
        let svg = """
        <?xml version="1.0" encoding="UTF-8"?>
        <svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="\(width)" height="\(height)" viewBox="0 0 \(width) \(height)">
          <image width="\(width)" height="\(height)" href="data:\(mime);base64,\(encoded)" xlink:href="data:\(mime);base64,\(encoded)"/>
        </svg>
        """
        guard let data = svg.data(using: .utf8) else {
            throw ConversionError.failed("Could not encode SVG")
        }
        try data.write(to: destination)
    }
}
