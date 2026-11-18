import CoreGraphics
import Foundation

/// PDF, text, and subtitle conversions from section 7.4.
@MainActor
enum DocumentEngine {
    static func convert(
        source: URL,
        entry: Phase3Entry,
        destinationDirectory: URL,
        pageSizeName: String,
        reserved: inout Set<URL>
    ) async throws -> [URL] {
        try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        let base = Phase3Naming.sourceBaseName(for: source)
        switch entry.id {
        case "pdf.docx":
            return [try writePDFDocx(source: source, base: base, directory: destinationDirectory, reserved: &reserved)]
        case "pdf.jpg":
            return try writePDFImages(source: source, base: base, directory: destinationDirectory, format: .jpeg, reserved: &reserved)
        case "pdf.png":
            return try writePDFImages(source: source, base: base, directory: destinationDirectory, format: .png, reserved: &reserved)
        case "pdf.txt":
            return [try writePDFText(source: source, base: base, directory: destinationDirectory, reserved: &reserved)]
        case "txt.pdf":
            let text = try DocumentTextExtractor.plainText(at: source)
            return try TextRenderEngine.render(
                text: text,
                pageSize: DocumentPageLayout.size(named: pageSizeName),
                format: .pdf,
                base: base,
                destinationDirectory: destinationDirectory,
                source: source,
                reserved: &reserved
            )
        case "txt.jpg":
            let text = try DocumentTextExtractor.plainText(at: source)
            return try TextRenderEngine.render(
                text: text,
                pageSize: DocumentPageLayout.size(named: pageSizeName),
                format: .jpeg,
                base: base,
                destinationDirectory: destinationDirectory,
                source: source,
                reserved: &reserved
            )
        case "txt.png":
            let text = try DocumentTextExtractor.plainText(at: source)
            return try TextRenderEngine.render(
                text: text,
                pageSize: DocumentPageLayout.size(named: pageSizeName),
                format: .png,
                base: base,
                destinationDirectory: destinationDirectory,
                source: source,
                reserved: &reserved
            )
        case "txt.srt":
            let text = try DocumentTextExtractor.plainText(at: source)
            let written = SubtitleCodec.writeSRT(SubtitleCodec.cuesFromPlainText(text))
            return [try writeText(written, base: base, pathExtension: "srt", directory: destinationDirectory, source: source, reserved: &reserved)]
        case "txt.vtt":
            let text = try DocumentTextExtractor.plainText(at: source)
            let written = SubtitleCodec.writeVTT(SubtitleCodec.cuesFromPlainText(text))
            return [try writeText(written, base: base, pathExtension: "vtt", directory: destinationDirectory, source: source, reserved: &reserved)]
        case "srt.vtt":
            let cues = try SubtitleCodec.cues(from: DocumentTextExtractor.plainText(at: source), format: .srt)
            return [try writeText(SubtitleCodec.writeVTT(cues), base: base, pathExtension: "vtt", directory: destinationDirectory, source: source, reserved: &reserved)]
        case "srt.txt":
            let cues = try SubtitleCodec.cues(from: DocumentTextExtractor.plainText(at: source), format: .srt)
            return [try writeText(SubtitleCodec.plainText(cues), base: base, pathExtension: "txt", directory: destinationDirectory, source: source, reserved: &reserved)]
        case "vtt.srt":
            let cues = try SubtitleCodec.cues(from: DocumentTextExtractor.plainText(at: source), format: .vtt)
            return [try writeText(SubtitleCodec.writeSRT(cues), base: base, pathExtension: "srt", directory: destinationDirectory, source: source, reserved: &reserved)]
        case "vtt.txt":
            let cues = try SubtitleCodec.cues(from: DocumentTextExtractor.plainText(at: source), format: .vtt)
            return [try writeText(SubtitleCodec.plainText(cues), base: base, pathExtension: "txt", directory: destinationDirectory, source: source, reserved: &reserved)]
        default:
            throw FileWheelError("This conversion is not available.")
        }
    }

    private static func writePDFText(
        source: URL,
        base: String,
        directory: URL,
        reserved: inout Set<URL>
    ) throws -> URL {
        let document = try PDFEngine.open(url: source)
        let text = PageText.join(PDFEngine.pageStrings(document))
        return try writeText(text, base: base, pathExtension: "txt", directory: directory, source: source, reserved: &reserved)
    }

    private static func writePDFDocx(
        source: URL,
        base: String,
        directory: URL,
        reserved: inout Set<URL>
    ) throws -> URL {
        let document = try PDFEngine.open(url: source)
        var blocks: [OOXMLBlock] = []
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            if index > 0 { blocks.append(.pageBreak) }
            let pageString = page.string ?? ""
            if pageString.count < PageText.shortPageLimit {
                let jpeg = try PDFEngine.jpegData(for: page, dpi: DocumentPageLayout.pdfRasterDPI)
                blocks.append(.image(OOXMLImage(
                    filename: String(format: "page-%03d.jpg", index + 1),
                    data: jpeg.data,
                    pixelWidth: jpeg.pixelWidth,
                    pixelHeight: jpeg.pixelHeight
                )))
            } else {
                let paragraphs = PDFEngine.blocks(on: page)
                if paragraphs.isEmpty {
                    blocks.append(.paragraph(pageString))
                } else {
                    paragraphs.forEach { blocks.append(.paragraph($0.text)) }
                }
            }
        }
        let url = Phase3Naming.uniqueFileURL(
            directory: directory,
            base: base,
            pathExtension: "docx",
            source: source,
            reserved: &reserved
        )
        let temp = directory.appendingPathComponent(".filewheel-\(UUID().uuidString).docx")
        do {
            try OOXMLWriter.write(blocks: blocks, to: temp)
            try OutputPublisher.publish(temp: temp, to: url)
        } catch {
            OutputPublisher.removeQuietly(temp)
            throw error
        }
        return url
    }

    private static func writePDFImages(
        source: URL,
        base: String,
        directory: URL,
        format: TextPageFormat,
        reserved: inout Set<URL>
    ) throws -> [URL] {
        let document = try PDFEngine.open(url: source)
        let ext = format == .png ? "png" : "jpg"
        if document.pageCount == 1 {
            let filename = Phase3Naming.pageFileName(base: base, page: 1, pathExtension: ext)
            let url = Phase3Naming.uniqueFileURL(
                directory: directory,
                base: (filename as NSString).deletingPathExtension,
                pathExtension: ext,
                source: source,
                reserved: &reserved
            )
            guard let page = document.page(at: 0), let image = PDFEngine.render(page, dpi: DocumentPageLayout.pdfRasterDPI) else {
                throw FileWheelError(FileWheelMessages.pdfUnreadable)
            }
            try publishImage(image, format: format, to: url, directory: directory)
            return [url]
        }
        let folder = Phase3Naming.uniqueFolderURL(
            directory: directory,
            name: "\(base)-pages",
            source: source,
            reserved: &reserved
        )
        let temp = directory.appendingPathComponent(".filewheel-\(UUID().uuidString)-pages")
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        do {
            for index in 0..<document.pageCount {
                guard let page = document.page(at: index), let image = PDFEngine.render(page, dpi: DocumentPageLayout.pdfRasterDPI) else {
                    throw FileWheelError(FileWheelMessages.pdfUnreadable)
                }
                let url = temp.appendingPathComponent(Phase3Naming.pageFileName(base: base, page: index + 1, pathExtension: ext))
                try write(image, format: format, to: url)
            }
            try Task.checkCancellation()
            try OutputPublisher.publish(temp: temp, to: folder)
        } catch {
            OutputPublisher.removeQuietly(temp)
            OutputPublisher.removeQuietly(folder)
            reserved.remove(folder.standardizedFileURL)
            throw error
        }
        return [folder]
    }

    private static func publishImage(_ image: CGImage, format: TextPageFormat, to finalURL: URL, directory: URL) throws {
        let temp = directory.appendingPathComponent(".filewheel-\(UUID().uuidString).img")
        do {
            try write(image, format: format, to: temp)
            try OutputPublisher.publish(temp: temp, to: finalURL)
        } catch {
            OutputPublisher.removeQuietly(temp)
            OutputPublisher.removeQuietly(finalURL)
            throw error
        }
    }

    private static func write(_ image: CGImage, format: TextPageFormat, to url: URL) throws {
        switch format {
        case .png: try ImageEncoder.writePNG(image, to: url)
        case .jpeg: try ImageEncoder.writeJPEG(image, to: url, quality: 0.9)
        case .pdf: break
        }
    }

    private static func writeText(
        _ text: String,
        base: String,
        pathExtension: String,
        directory: URL,
        source: URL,
        reserved: inout Set<URL>
    ) throws -> URL {
        let url = Phase3Naming.uniqueFileURL(
            directory: directory,
            base: base,
            pathExtension: pathExtension,
            source: source,
            reserved: &reserved
        )
        let temp = directory.appendingPathComponent(".filewheel-\(UUID().uuidString).txt")
        do {
            try text.write(to: temp, atomically: true, encoding: .utf8)
            try OutputPublisher.publish(temp: temp, to: url)
        } catch {
            OutputPublisher.removeQuietly(temp)
            throw error
        }
        return url
    }
}
