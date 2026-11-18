import Foundation

/// Text File Wheel is willing to speak or write. PDF page strings are produced by `PDFEngine`.
enum DocumentTextExtractor {
    static func plainText(at url: URL) throws -> String {
        if let text = try? String(contentsOf: url, encoding: .utf8) { return text }
        if let text = try? String(contentsOf: url, encoding: .utf16) { return text }
        throw FileWheelError(FileWheelMessages.textUnreadable)
    }

    static func paragraphs(inDocumentXML xml: Data) throws -> [String] {
        let parser = DocxParagraphParser()
        guard parser.parse(xml) else {
            throw FileWheelError(FileWheelMessages.docxUnreadable)
        }
        return parser.paragraphs
    }

    /// Paragraph text from `word/document.xml`, in order.
    static func docxParagraphs(at url: URL) throws -> [String] {
        let xml = try docxDocumentXML(at: url)
        return try paragraphs(inDocumentXML: xml)
    }

    static func docxDocumentXML(at url: URL) throws -> Data {
        // Real Word files are deflated ZIPs. ZIPFoundation reads both store and deflate.
        // The symbol is resolved in DocumentText+Zip.swift so this file stays Foundation-only.
        try DocxPackage.readDocumentXML(at: url)
    }
}

/// Collects `w:t` text inside each `w:p`, in document order.
final class DocxParagraphParser: NSObject, XMLParserDelegate {
    private(set) var paragraphs: [String] = []
    private var inParagraph = false
    private var inText = false
    private var current = ""
    private var textBuffer = ""

    func parse(_ data: Data) -> Bool {
        let parser = XMLParser(data: data)
        parser.delegate = self
        return parser.parse()
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let name = localName(elementName)
        if name == "p" {
            inParagraph = true
            current = ""
        } else if inParagraph && name == "t" {
            inText = true
            textBuffer = ""
        } else if inParagraph && name == "tab" {
            current += "\t"
        } else if inParagraph && name == "br" {
            current += "\n"
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inText { textBuffer += string }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let name = localName(elementName)
        if name == "t" {
            current += textBuffer
            textBuffer = ""
            inText = false
        } else if name == "p" {
            paragraphs.append(current)
            current = ""
            inParagraph = false
        }
    }

    private func localName(_ elementName: String) -> String {
        if let colon = elementName.lastIndex(of: ":") {
            return String(elementName[elementName.index(after: colon)...])
        }
        return elementName
    }
}

enum PageText {
    static let shortPageLimit = 20

    static func join(_ pages: [String]) -> String {
        pages.joined(separator: "\u{000C}")
    }

    static func allPagesLackExtractableText(_ pages: [String]) -> Bool {
        !pages.isEmpty && pages.allSatisfy { $0.count < shortPageLimit }
    }
}
