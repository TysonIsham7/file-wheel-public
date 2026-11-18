import Foundation

struct OOXMLImage {
    var filename: String
    var data: Data
    var pixelWidth: Int
    var pixelHeight: Int
}

enum OOXMLBlock {
    case paragraph(String)
    case image(OOXMLImage)
    case pageBreak
}

/// Hand-built Word package. Phase 1 calls `imageDocument` for image → DOCX.
/// PDF → DOCX uses one paragraph per text block, and a page image when a page has under 20 characters.
enum OOXMLWriter {
    static func imageDocument(images: [OOXMLImage]) -> [OOXMLBlock] {
        var blocks: [OOXMLBlock] = []
        for (index, image) in images.enumerated() {
            if index > 0 { blocks.append(.pageBreak) }
            blocks.append(.image(image))
        }
        return blocks
    }

    static func packageData(blocks: [OOXMLBlock]) throws -> Data {
        let files = try packageFiles(blocks: blocks)
        let items = files.map { path, data in
            StoredZip.Item(path: path, data: data, modified: .now())
        }
        return try StoredZip.data(items: items)
    }

    static func write(blocks: [OOXMLBlock], to url: URL) throws {
        let data = try packageData(blocks: blocks)
        try data.write(to: url, options: .atomic)
    }

    static func packageFiles(blocks: [OOXMLBlock]) throws -> [String: Data] {
        let images = blocks.compactMap { block -> OOXMLImage? in
            if case .image(let image) = block { return image }
            return nil
        }
        var files: [String: Data] = [:]
        files["[Content_Types].xml"] = Data(contentTypes(images: images).utf8)
        files["_rels/.rels"] = Data(rootRels.utf8)
        files["word/styles.xml"] = Data(stylesXML.utf8)
        files["word/document.xml"] = Data(documentXML(blocks: blocks).utf8)
        files["word/_rels/document.xml.rels"] = Data(documentRels(images: images).utf8)
        for image in images {
            files["word/media/\(image.filename)"] = image.data
        }
        return files
    }

    static func documentXML(blocks: [OOXMLBlock]) -> String {
        var body = ""
        var imageIndex = 0
        for block in blocks {
            switch block {
            case .paragraph(let text):
                body += paragraphXML(text)
            case .pageBreak:
                body += "<w:p><w:r><w:br w:type=\"page\"/></w:r></w:p>"
            case .image(let image):
                imageIndex += 1
                body += imageParagraphXML(image, relationship: "rIdImage\(imageIndex)", drawingID: imageIndex)
            }
        }
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>\
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" \
        xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" \
        xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" \
        xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" \
        xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture">\
        <w:body>\(body)\(sectionXML)</w:body></w:document>
        """
    }

    private static func paragraphXML(_ text: String) -> String {
        let safe = xmlText(text)
        if safe.isEmpty { return "" }
        let lines = safe.components(separatedBy: "\n")
        var runs = ""
        for (index, line) in lines.enumerated() {
            if index > 0 { runs += "<w:br/>" }
            runs += "<w:t xml:space=\"preserve\">\(line)</w:t>"
        }
        return "<w:p><w:r>\(runs)</w:r></w:p>"
    }

    private static func imageParagraphXML(_ image: OOXMLImage, relationship: String, drawingID: Int) -> String {
        let (cx, cy) = extent(pixelWidth: image.pixelWidth, pixelHeight: image.pixelHeight)
        let name = xmlAttribute(image.filename)
        return """
        <w:p><w:r><w:drawing><wp:inline distT="0" distB="0" distL="0" distR="0">\
        <wp:extent cx="\(cx)" cy="\(cy)"/>\
        <wp:docPr id="\(drawingID)" name="\(name)"/>\
        <a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture">\
        <pic:pic><pic:nvPicPr><pic:cNvPr id="\(drawingID)" name="\(name)"/><pic:cNvPicPr/></pic:nvPicPr>\
        <pic:blipFill><a:blip r:embed="\(relationship)"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill>\
        <pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="\(cx)" cy="\(cy)"/></a:xfrm>\
        <a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr></pic:pic>\
        </a:graphicData></a:graphic></wp:inline></w:drawing></w:r></w:p>
        """
    }

    /// Fit the bitmap inside a 6.5 by 9 inch content box. Units are EMUs.
    static func extent(pixelWidth: Int, pixelHeight: Int) -> (Int, Int) {
        let maxCX = Int(6.5 * 914_400)
        let maxCY = Int(9.0 * 914_400)
        let width = max(pixelWidth, 1)
        let height = max(pixelHeight, 1)
        var cx = maxCX
        var cy = Int(Double(cx) * Double(height) / Double(width))
        if cy > maxCY {
            cy = maxCY
            cx = Int(Double(cy) * Double(width) / Double(height))
        }
        return (max(cx, 1), max(cy, 1))
    }

    private static let sectionXML = """
    <w:sectPr><w:pgSz w:w="12240" w:h="15840"/>\
    <w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="720" w:footer="720" w:gutter="0"/>\
    </w:sectPr>
    """

    private static func contentTypes(images: [OOXMLImage]) -> String {
        var defaults = """
        <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>\
        <Default Extension="xml" ContentType="application/xml"/>
        """
        let extensions = Set(images.map { ($0.filename as NSString).pathExtension.lowercased() })
        if extensions.contains("jpg") || extensions.contains("jpeg") {
            defaults += #"<Default Extension="jpeg" ContentType="image/jpeg"/>"#
            defaults += #"<Default Extension="jpg" ContentType="image/jpeg"/>"#
        }
        if extensions.contains("png") {
            defaults += #"<Default Extension="png" ContentType="image/png"/>"#
        }
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>\
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">\
        \(defaults)\
        <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>\
        <Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>\
        </Types>
        """
    }

    private static func documentRels(images: [OOXMLImage]) -> String {
        var relationships = """
        <Relationship Id="rIdStyles" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
        """
        for (index, image) in images.enumerated() {
            relationships += #"<Relationship Id="rIdImage\#(index + 1)" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="media/\#(xmlAttribute(image.filename))"/>"#
        }
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>\
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\
        \(relationships)</Relationships>
        """
    }

    private static let rootRels = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>\
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\
    <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>\
    </Relationships>
    """

    private static let stylesXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>\
    <w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">\
    <w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/>\
    <w:rPr><w:sz w:val="24"/></w:rPr></w:style></w:styles>
    """

    static func xmlText(_ text: String) -> String {
        let filtered = text.unicodeScalars.filter { scalar in
            let value = scalar.value
            return value == 0x9 || value == 0xA || value == 0xD || value >= 0x20
        }
        return xmlAttribute(String(String.UnicodeScalarView(filtered)))
    }

    static func xmlAttribute(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
