import AppKit
import CoreText
import Foundation

enum DocumentPageLayout {
    static let letter = CGSize(width: 612, height: 792)
    static let margin: CGFloat = 72
    static let bodyPointSize: CGFloat = 12
    static let pdfRasterDPI: CGFloat = 300

    static func size(named name: String) -> CGSize {
        switch name {
        case "letter": return letter
        default: return letter
        }
    }
}

enum TextPaginator {
    static func pages(text: String, pageSize: CGSize) -> [NSAttributedString] {
        let font = NSFont.systemFont(ofSize: DocumentPageLayout.bodyPointSize)
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byWordWrapping
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.black,
            .paragraphStyle: style,
        ]
        let attributed = NSAttributedString(string: text, attributes: attributes)
        if attributed.length == 0 {
            return [attributed]
        }
        let content = CGSize(
            width: pageSize.width - DocumentPageLayout.margin * 2,
            height: pageSize.height - DocumentPageLayout.margin * 2
        )
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        var location = 0
        var pages: [NSAttributedString] = []
        while location < attributed.length {
            let path = CGPath(rect: CGRect(origin: .zero, size: content), transform: nil)
            let frame = CTFramesetterCreateFrame(
                framesetter,
                CFRange(location: location, length: 0),
                path,
                nil
            )
            let visible = CTFrameGetVisibleStringRange(frame)
            if visible.length == 0 { break }
            let range = NSRange(location: visible.location, length: visible.length)
            pages.append(attributed.attributedSubstring(from: range))
            location += visible.length
        }
        return pages.isEmpty ? [attributed] : pages
    }

    static func draw(_ page: NSAttributedString, in context: CGContext, pageSize: CGSize) {
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(origin: .zero, size: pageSize))
        let content = CGRect(
            x: DocumentPageLayout.margin,
            y: DocumentPageLayout.margin,
            width: pageSize.width - DocumentPageLayout.margin * 2,
            height: pageSize.height - DocumentPageLayout.margin * 2
        )
        NSGraphicsContext.saveGraphicsState()
        let graphics = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.current = graphics
        context.saveGState()
        context.translateBy(x: content.minX, y: content.minY)
        context.textMatrix = .identity
        context.translateBy(x: 0, y: content.height)
        context.scaleBy(x: 1, y: -1)
        let path = CGPath(rect: CGRect(origin: .zero, size: content.size), transform: nil)
        let framesetter = CTFramesetterCreateWithAttributedString(page)
        let frame = CTFramesetterCreateFrame(
            framesetter,
            CFRange(location: 0, length: page.length),
            path,
            nil
        )
        CTFrameDraw(frame, context)
        context.restoreGState()
        NSGraphicsContext.restoreGraphicsState()
    }
}

@MainActor
enum TextRenderEngine {
    static func render(
        text: String,
        pageSize: CGSize,
        format: TextPageFormat,
        base: String,
        destinationDirectory: URL,
        source: URL,
        reserved: inout Set<URL>
    ) throws -> [URL] {
        let pages = TextPaginator.pages(text: text, pageSize: pageSize)
        switch format {
        case .pdf:
            let url = Phase3Naming.uniqueFileURL(
                directory: destinationDirectory,
                base: base,
                pathExtension: "pdf",
                source: source,
                reserved: &reserved
            )
            let temp = destinationDirectory.appendingPathComponent(".filewheel-\(UUID().uuidString).pdf")
            try writePDF(pages, pageSize: pageSize, to: temp)
            do {
                try OutputPublisher.publish(temp: temp, to: url)
            } catch {
                OutputPublisher.removeQuietly(temp)
                throw error
            }
            return [url]
        case .jpeg, .png:
            return try writeImages(
                pages,
                pageSize: pageSize,
                format: format,
                base: base,
                destinationDirectory: destinationDirectory,
                source: source,
                reserved: &reserved
            )
        }
    }

    private static func writePDF(_ pages: [NSAttributedString], pageSize: CGSize, to url: URL) throws {
        var media = CGRect(origin: .zero, size: pageSize)
        guard let consumer = CGDataConsumer(url: url as CFURL),
              let context = CGContext(consumer: consumer, mediaBox: &media, nil) else {
            throw FileWheelError("The PDF could not be written.")
        }
        for page in pages {
            context.beginPDFPage(nil)
            TextPaginator.draw(page, in: context, pageSize: pageSize)
            context.endPDFPage()
        }
        context.closePDF()
    }

    private static func writeImages(
        _ pages: [NSAttributedString],
        pageSize: CGSize,
        format: TextPageFormat,
        base: String,
        destinationDirectory: URL,
        source: URL,
        reserved: inout Set<URL>
    ) throws -> [URL] {
        let ext = format == .jpeg ? "jpg" : "png"
        if pages.count <= 1 {
            let url = Phase3Naming.uniqueFileURL(
                directory: destinationDirectory,
                base: base,
                pathExtension: ext,
                source: source,
                reserved: &reserved
            )
            let image = try bitmap(pages.first ?? NSAttributedString(), pageSize: pageSize)
            let temp = destinationDirectory.appendingPathComponent(".filewheel-\(UUID().uuidString).img")
            do {
                try write(image, format: format, to: temp)
                try OutputPublisher.publish(temp: temp, to: url)
            } catch {
                OutputPublisher.removeQuietly(temp)
                OutputPublisher.removeQuietly(url)
                throw error
            }
            return [url]
        }
        let folder = Phase3Naming.uniqueFolderURL(
            directory: destinationDirectory,
            name: "\(base)-pages",
            source: source,
            reserved: &reserved
        )
        let tempFolder = destinationDirectory.appendingPathComponent(".filewheel-\(UUID().uuidString)-pages")
        try FileManager.default.createDirectory(at: tempFolder, withIntermediateDirectories: true)
        do {
            for (index, page) in pages.enumerated() {
                let filename = Phase3Naming.pageFileName(base: base, page: index + 1, pathExtension: ext)
                let image = try bitmap(page, pageSize: pageSize)
                try write(image, format: format, to: tempFolder.appendingPathComponent(filename))
            }
            try OutputPublisher.publish(temp: tempFolder, to: folder)
        } catch {
            OutputPublisher.removeQuietly(tempFolder)
            OutputPublisher.removeQuietly(folder)
            reserved.remove(folder.standardizedFileURL)
            throw error
        }
        return [folder]
    }

    private static func bitmap(_ page: NSAttributedString, pageSize: CGSize) throws -> CGImage {
        let scale: CGFloat = 2
        let width = Int((pageSize.width * scale).rounded())
        let height = Int((pageSize.height * scale).rounded())
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw FileWheelError("The page could not be drawn.")
        }
        context.scaleBy(x: scale, y: scale)
        TextPaginator.draw(page, in: context, pageSize: pageSize)
        guard let image = context.makeImage() else {
            throw FileWheelError("The page could not be drawn.")
        }
        return image
    }

    private static func write(_ image: CGImage, format: TextPageFormat, to url: URL) throws {
        switch format {
        case .jpeg: try ImageEncoder.writeJPEG(image, to: url, quality: 0.9)
        case .png: try ImageEncoder.writePNG(image, to: url)
        case .pdf: break
        }
    }
}

enum TextPageFormat {
    case pdf
    case jpeg
    case png
}
