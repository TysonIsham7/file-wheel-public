import Foundation

public struct RecognizedWord: Equatable, Sendable {
    public var text: String
    /// Top-left origin, in page points.
    public var rect: FWRect

    public init(text: String, rect: FWRect) {
        self.text = text
        self.rect = rect
    }
}

public enum OCRLanguage {
    public static let automatic = "auto"

    public struct Choice: Equatable, Sendable, Identifiable {
        public var id: String
        public var title: String

        public init(id: String, title: String) {
            self.id = id
            self.title = title
        }
    }

    public static let choices: [Choice] = [
        Choice(id: automatic, title: "Auto-detect"),
        Choice(id: "en-US", title: "English"),
        Choice(id: "fr-FR", title: "French"),
        Choice(id: "de-DE", title: "German"),
        Choice(id: "es-ES", title: "Spanish"),
        Choice(id: "it-IT", title: "Italian"),
        Choice(id: "pt-BR", title: "Portuguese"),
        Choice(id: "nl-NL", title: "Dutch"),
        Choice(id: "zh-Hans", title: "Chinese (Simplified)"),
        Choice(id: "zh-Hant", title: "Chinese (Traditional)"),
        Choice(id: "ja-JP", title: "Japanese"),
        Choice(id: "ko-KR", title: "Korean")
    ]
}

public struct OCRParameters: Equatable, Sendable {
    public var language: String
    public var forceOCR: Bool

    public init(language: String = OCRLanguage.automatic, forceOCR: Bool = false) {
        self.language = language
        self.forceOCR = forceOCR
    }
}

/// One page handed to the text-layer writer.
/// Coordinates use a top-left origin, in PDF points.
public struct OCRPageSpec: Equatable, Sendable {
    public var width: Double
    public var height: Double
    public var rotation: Int
    public var extractableText: String
    public var existingObjects: [SimplePDF.TextObject]
    public var keptImages: [SimplePDF.ImageObject]
    public var recognized: [RecognizedWord]
    public var force: Bool

    public init(
        width: Double,
        height: Double,
        rotation: Int = 0,
        extractableText: String,
        existingObjects: [SimplePDF.TextObject] = [],
        keptImages: [SimplePDF.ImageObject] = [],
        recognized: [RecognizedWord] = [],
        force: Bool = false
    ) {
        self.width = width
        self.height = height
        self.rotation = rotation
        self.extractableText = extractableText
        self.existingObjects = existingObjects
        self.keptImages = keptImages
        self.recognized = recognized
        self.force = force
    }
}

/// Builds a PDF whose pages keep their images and gain an invisible text layer.
public enum OCRTextLayer {
    /// Pages with more extractable characters than this are left unchanged unless Force OCR is on.
    public static let existingTextLimit = 20

    public static func shouldRecognize(extractableText: String, force: Bool) -> Bool {
        if force { return true }
        return extractableText.count <= existingTextLimit
    }

    public static func document(pages specs: [OCRPageSpec]) -> SimplePDF {
        SimplePDF(pages: specs.map(page(from:)))
    }

    public static func page(from spec: OCRPageSpec) -> SimplePDF.Page {
        if shouldRecognize(extractableText: spec.extractableText, force: spec.force) {
            let texts = spec.recognized.compactMap { word -> SimplePDF.TextObject? in
                let cleaned = word.text
                    .replacingOccurrences(of: "\n", with: " ")
                    .replacingOccurrences(of: "\r", with: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !cleaned.isEmpty, !word.rect.isEmpty else { return nil }
                let size = min(max(4, word.rect.height * 0.8), max(4, word.rect.height))
                return SimplePDF.TextObject(text: cleaned, x: word.rect.x, y: word.rect.y, size: size, invisible: true)
            }
            // An empty recognition pass leaves a short existing layer in place.
            let layer = texts.isEmpty ? spec.existingObjects : texts
            return SimplePDF.Page(width: spec.width, height: spec.height, rotation: spec.rotation, texts: layer, images: spec.keptImages)
        }
        return SimplePDF.Page(
            width: spec.width,
            height: spec.height,
            rotation: spec.rotation,
            texts: spec.existingObjects,
            images: spec.keptImages
        )
    }
}

public enum OCRAssembly {
    public static func extractableText(of page: SimplePDF.Page) -> String {
        page.texts.map(\.text).joined(separator: "\n")
    }

    /// True when every page can be recognized from an image already stored in the file.
    /// Pages that already have text are copied by PDFKit instead, so this path is not used for them.
    public static func canBuildFromEmbeddedImages(_ document: SimplePDF, force: Bool) -> Bool {
        !document.pages.isEmpty && document.pages.allSatisfy { page in
            shouldRecognize(page, force: force) && !page.images.isEmpty
        }
    }

    public static func shouldRecognize(_ page: SimplePDF.Page, force: Bool) -> Bool {
        OCRTextLayer.shouldRecognize(extractableText: extractableText(of: page), force: force)
    }

    /// `recognize` returns words in the image's own rectangle, top-left origin.
    public static func specs(
        document: SimplePDF,
        force: Bool,
        recognize: (SimplePDF.ImageObject) throws -> [RecognizedWord]
    ) throws -> [OCRPageSpec] {
        try document.pages.map { page in
            let text = extractableText(of: page)
            let needs = OCRTextLayer.shouldRecognize(extractableText: text, force: force)
            var words: [RecognizedWord] = []
            if needs, let image = largestImage(on: page) {
                words = try recognize(image).map { word in
                    RecognizedWord(
                        text: word.text,
                        rect: FWRect(
                            x: image.rect.x + word.rect.x,
                            y: image.rect.y + word.rect.y,
                            width: word.rect.width,
                            height: word.rect.height
                        )
                    )
                }
            }
            return OCRPageSpec(
                width: page.width,
                height: page.height,
                rotation: page.rotation,
                extractableText: text,
                existingObjects: page.texts,
                keptImages: page.images,
                recognized: words,
                force: force
            )
        }
    }

    public static func largestImage(on page: SimplePDF.Page) -> SimplePDF.ImageObject? {
        page.images.max { lhs, rhs in
            lhs.rect.width * lhs.rect.height < rhs.rect.width * rhs.rect.height
        }
    }
}

public protocol TextRecognizing: Sendable {
    func recognize(jpeg: Data, pixelWidth: Int, pixelHeight: Int, pageWidth: Double, pageHeight: Double, language: String) throws -> [RecognizedWord]
}

public struct FixedTextRecognizer: TextRecognizing {
    public var words: [RecognizedWord]

    public init(words: [RecognizedWord]) {
        self.words = words
    }

    public func recognize(jpeg: Data, pixelWidth: Int, pixelHeight: Int, pageWidth: Double, pageHeight: Double, language: String) throws -> [RecognizedWord] {
        _ = (jpeg, pixelWidth, pixelHeight, pageWidth, pageHeight, language)
        return words
    }
}

public struct EmptyTextRecognizer: TextRecognizing {
    public init() {}

    public func recognize(jpeg: Data, pixelWidth: Int, pixelHeight: Int, pageWidth: Double, pageHeight: Double, language: String) throws -> [RecognizedWord] {
        _ = (jpeg, pixelWidth, pixelHeight, pageWidth, pageHeight, language)
        return []
    }
}
