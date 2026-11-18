import AppKit
import CoreGraphics
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers

struct PDFTextBlock: Equatable {
    var text: String
}

/// PDFKit: page render, text extract, and the text-ish PDF → DOCX blocks.
enum PDFEngine {
    static func open(url: URL) throws -> PDFDocument {
        guard let document = PDFDocument(url: url) else {
            throw FileWheelError(FileWheelMessages.pdfUnreadable)
        }
        // A locked document needs a password. Restriction-only files that PDFKit
        // already opened (isEncrypted && !isLocked) still convert.
        if document.isLocked {
            throw FileWheelError(FileWheelMessages.passwordProtectedPDF)
        }
        if document.pageCount == 0 {
            throw FileWheelError(FileWheelMessages.pdfUnreadable)
        }
        return document
    }

    static func pageStrings(_ document: PDFDocument) -> [String] {
        (0..<document.pageCount).map { index in
            document.page(at: index)?.string ?? ""
        }
    }

    static func blocks(on page: PDFPage) -> [PDFTextBlock] {
        let bounds = page.bounds(for: .mediaBox)
        if let selection = page.selection(for: bounds) {
            let lines = selection.selectionsByLine().compactMap { line -> LineBox? in
                let text = (line.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if text.isEmpty { return nil }
                return LineBox(text: text, bounds: line.bounds(for: page))
            }
            let paragraphs = paragraphsForLines(lines.map { (text: $0.text, bounds: $0.bounds) })
            if !paragraphs.isEmpty {
                return paragraphs.map { PDFTextBlock(text: $0) }
            }
        }
        return fallbackBlocks(page.string ?? "")
    }

    static func render(_ page: PDFPage, dpi: CGFloat) -> CGImage? {
        let bounds = page.bounds(for: .mediaBox)
        let scale = dpi / 72
        let pixelSize = CGSize(width: max(bounds.width * scale, 1), height: max(bounds.height * scale, 1))
        let thumbnail = page.thumbnail(of: pixelSize, for: .mediaBox)
        var proposed = CGRect(origin: .zero, size: thumbnail.size)
        return thumbnail.cgImage(forProposedRect: &proposed, context: nil, hints: nil)
    }

    static func jpegData(for page: PDFPage, dpi: CGFloat) throws -> (data: Data, pixelWidth: Int, pixelHeight: Int) {
        guard let image = render(page, dpi: dpi) else {
            throw FileWheelError(FileWheelMessages.pdfUnreadable)
        }
        let data = try ImageEncoder.jpegData(image, quality: 0.85)
        return (data, image.width, image.height)
    }

    private struct LineBox {
        var text: String
        var bounds: CGRect
    }

    /// Left-to-right columns, then top-to-bottom. A wide vertical gap starts a new paragraph.
    static func paragraphsForLines(_ lines: [(text: String, bounds: CGRect)]) -> [String] {
        let boxes = lines.map { LineBox(text: $0.text, bounds: $0.bounds) }
        let columns = columnsByHorizontalGap(boxes)
        var paragraphs: [String] = []
        for column in columns {
            let ordered = column.sorted { $0.bounds.midY > $1.bounds.midY }
            var group: [String] = []
            var previous: LineBox?
            func flush() {
                let text = group.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty { paragraphs.append(text) }
                group = []
            }
            for line in ordered {
                if let previous, previous.bounds.minY - line.bounds.maxY > 8 {
                    flush()
                }
                group.append(line.text)
                previous = line
            }
            flush()
        }
        return paragraphs
    }

    private static func columnsByHorizontalGap(_ lines: [LineBox]) -> [[LineBox]] {
        let sorted = lines.sorted { $0.bounds.minX < $1.bounds.minX }
        guard let first = sorted.first else { return [] }
        var columns: [[LineBox]] = []
        var current: [LineBox] = [first]
        var maxX = first.bounds.maxX
        for line in sorted.dropFirst() {
            if line.bounds.minX > maxX + 36 {
                columns.append(current)
                current = [line]
                maxX = line.bounds.maxX
            } else {
                current.append(line)
                maxX = max(maxX, line.bounds.maxX)
            }
        }
        columns.append(current)
        return columns
    }

    private static func fallbackBlocks(_ pageString: String) -> [PDFTextBlock] {
        let normalized = pageString.replacingOccurrences(of: "\r\n", with: "\n")
        var blocks: [PDFTextBlock] = []
        var current: [String] = []
        func flush() {
            let text = current.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { blocks.append(PDFTextBlock(text: text)) }
            current = []
        }
        for line in normalized.components(separatedBy: "\n") {
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                flush()
            } else {
                current.append(line.trimmingCharacters(in: .whitespaces))
            }
        }
        flush()
        return blocks
    }
}

enum ImageEncoder {
    static func writePNG(_ image: CGImage, to url: URL) throws {
        try write(image, to: url, type: .png, properties: nil)
    }

    static func writeJPEG(_ image: CGImage, to url: URL, quality: CGFloat) throws {
        try write(image, to: url, type: .jpeg, properties: [kCGImageDestinationLossyCompressionQuality: quality])
    }

    static func jpegData(_ image: CGImage, quality: CGFloat) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw FileWheelError(FileWheelMessages.pdfUnreadable)
        }
        let properties = [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
        CGImageDestinationAddImage(destination, image, properties)
        guard CGImageDestinationFinalize(destination) else {
            throw FileWheelError(FileWheelMessages.pdfUnreadable)
        }
        return data as Data
    }

    private static func write(_ image: CGImage, to url: URL, type: UTType, properties: [CFString: Any]?) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else {
            throw FileWheelError("The image could not be written.")
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary?)
        guard CGImageDestinationFinalize(destination) else {
            throw FileWheelError("The image could not be written.")
        }
    }
}
