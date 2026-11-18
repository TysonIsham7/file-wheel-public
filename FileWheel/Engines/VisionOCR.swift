import AppKit
import CoreGraphics
import Foundation
import ImageIO
import PDFKit
import Vision

/// On-device text recognition. The request is Vision's accurate, on-device recognizer.
/// Nothing in this type is uploaded.
public struct VisionTextRecognizer: TextRecognizing {
    public init() {}

    public func recognize(jpeg: Data, pixelWidth: Int, pixelHeight: Int, pageWidth: Double, pageHeight: Double, language: String) throws -> [RecognizedWord] {
        _ = (pixelWidth, pixelHeight)
        guard let source = CGImageSourceCreateWithData(jpeg as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return []
        }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        if language.isEmpty || language == OCRLanguage.automatic {
            request.automaticallyDetectsLanguage = true
        } else {
            request.recognitionLanguages = [language]
            request.automaticallyDetectsLanguage = false
        }
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            throw ToolError.message("Text recognition failed on this Mac.")
        }
        let width = pageWidth > 0 ? pageWidth : Double(image.width)
        let height = pageHeight > 0 ? pageHeight : Double(image.height)
        return (request.results ?? []).compactMap { observation in
            guard let text = observation.topCandidates(1).first?.string else { return nil }
            let box = observation.boundingBox
            let rect = FWRect(
                x: box.origin.x * width,
                y: (1 - box.origin.y - box.size.height) * height,
                width: box.size.width * width,
                height: max(1, box.size.height * height)
            )
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !rect.isEmpty else { return nil }
            return RecognizedWord(text: text, rect: rect)
        }
    }
}

enum OCRRecognition {
    static func words(
        recognizer: any TextRecognizing,
        jpeg: Data,
        pixelWidth: Int,
        pixelHeight: Int,
        pageWidth: Double,
        pageHeight: Double,
        language: String
    ) throws -> [RecognizedWord] {
        do {
            return try recognizer.recognize(
                jpeg: jpeg,
                pixelWidth: pixelWidth,
                pixelHeight: pixelHeight,
                pageWidth: pageWidth,
                pageHeight: pageHeight,
                language: language
            )
        } catch let error as ToolError {
            throw error
        } catch {
            throw ToolError.message("Text recognition failed on this Mac.")
        }
    }
}

enum OCRDocumentWriter {
    static func write(source: URL, destination: URL, parameters: OCRParameters, recognizer: any TextRecognizing) throws {
        guard let document = PDFDocument(url: source) else {
            throw ToolError.message("Could not read this PDF.")
        }
        if document.isLocked {
            throw ToolError.passwordProtected
        }
        let output = PDFDocument()
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            let existing = page.string ?? ""
            if !OCRTextLayer.shouldRecognize(extractableText: existing, force: parameters.forceOCR) {
                output.insert(page, at: output.pageCount)
                continue
            }
            let replacement = try recognize(page, existing: existing, parameters: parameters, recognizer: recognizer)
            guard let piece = PDFDocument(data: replacement), let newPage = piece.page(at: 0) else {
                throw ToolError.message("Could not write the searchable PDF.")
            }
            output.insert(newPage, at: output.pageCount)
        }
        guard output.pageCount > 0 else {
            throw ToolError.message("Could not read this PDF.")
        }
        try AtomicFileWrite.commit(destination: destination) { temp in
            guard output.write(to: temp) else {
                throw ToolError.message("Could not write the searchable PDF.")
            }
        }
    }

    private static func recognize(_ page: PDFPage, existing: String, parameters: OCRParameters, recognizer: any TextRecognizing) throws -> Data {
        guard let image = PDFEngine.render(page, dpi: 144) else {
            throw ToolError.message("Could not render this page.")
        }
        let jpeg: Data
        do {
            jpeg = try ImageEncoder.jpegData(image, quality: 0.85)
        } catch {
            throw ToolError.message("Could not render this page.")
        }
        let bounds = page.bounds(for: .mediaBox)
        let pageWidth = Double(bounds.width)
        let pageHeight = Double(bounds.height)
        let words = try OCRRecognition.words(
            recognizer: recognizer,
            jpeg: jpeg,
            pixelWidth: image.width,
            pixelHeight: image.height,
            pageWidth: pageWidth,
            pageHeight: pageHeight,
            language: parameters.language
        )
        let picture = SimplePDF.ImageObject(
            jpeg: jpeg,
            rect: FWRect(x: 0, y: 0, width: pageWidth, height: pageHeight),
            pixelWidth: image.width,
            pixelHeight: image.height
        )
        let spec = OCRPageSpec(
            width: pageWidth,
            height: pageHeight,
            extractableText: existing,
            keptImages: [picture],
            recognized: words,
            force: parameters.forceOCR
        )
        return OCRTextLayer.document(pages: [spec]).data()
    }
}

enum PDFSignatureWriter {
    /// Returns true when PDFKit opened the file and the signed copy was written.
    static func write(source: URL, destination: URL, parameters: SignPDFParameters) throws -> Bool {
        guard let placement = parameters.placement else { return false }
        guard let document = PDFDocument(url: source), document.pageCount > 0 else { return false }
        if document.isLocked {
            throw ToolError.passwordProtected
        }
        guard parameters.pageIndex >= 0, parameters.pageIndex < document.pageCount else {
            throw ToolError.message("That page is not in this PDF.")
        }
        let output = PDFDocument()
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            if index != parameters.pageIndex {
                output.insert(page, at: output.pageCount)
                continue
            }
            let replacement = try flatten(page, placement: placement, parameters: parameters)
            guard let piece = PDFDocument(data: replacement), let newPage = piece.page(at: 0) else {
                throw ToolError.message("Could not place the signature.")
            }
            output.insert(newPage, at: output.pageCount)
        }
        try AtomicFileWrite.commit(destination: destination) { temp in
            guard output.write(to: temp) else {
                throw ToolError.message("Could not write the signed PDF.")
            }
        }
        return true
    }

    private static func flatten(_ page: PDFPage, placement: SignatureTransform, parameters: SignPDFParameters) throws -> Data {
        guard let image = PDFEngine.render(page, dpi: 144) else {
            throw ToolError.message("Could not render this page.")
        }
        let jpeg: Data
        do {
            jpeg = try ImageEncoder.jpegData(image, quality: 0.85)
        } catch {
            throw ToolError.message("Could not render this page.")
        }
        let bounds = page.bounds(for: .mediaBox)
        let background = SimplePDF.ImageObject(
            jpeg: jpeg,
            rect: FWRect(x: 0, y: 0, width: Double(bounds.width), height: Double(bounds.height)),
            pixelWidth: image.width,
            pixelHeight: image.height
        )
        let signature = SimplePDF.ImageObject(
            jpeg: parameters.imageJPEG,
            rect: placement.rect(),
            pixelWidth: parameters.pixelWidth,
            pixelHeight: parameters.pixelHeight,
            alpha: parameters.alpha
        )
        let texts = SignatureComposer.texts(placement: placement, pageHeight: Double(bounds.height), text: parameters.text, date: parameters.date)
        let simple = SimplePDF(pages: [
            SimplePDF.Page(width: Double(bounds.width), height: Double(bounds.height), texts: texts, images: [background, signature])
        ])
        return simple.data()
    }
}
