import Foundation

public struct SimplePDF: Equatable, Sendable {
    public struct TextObject: Equatable, Sendable {
        public var text: String
        public var x: Double
        public var y: Double
        public var size: Double
        /// Rendering mode 3. The text is extractable and is not painted.
        public var invisible: Bool

        public init(text: String, x: Double, y: Double, size: Double = 12, invisible: Bool = false) {
            self.text = text
            self.x = x
            self.y = y
            self.size = size
            self.invisible = invisible
        }

        public func rect() -> FWRect {
            FWRect(x: x, y: y, width: max(1, Double(text.count) * size * 0.5), height: size)
        }
    }

    public struct ImageObject: Equatable, Sendable {
        public var jpeg: Data
        public var rect: FWRect
        public var pixelWidth: Int
        public var pixelHeight: Int
        /// Raw 8-bit mask, one byte per pixel. Zero is transparent. Nil keeps the image opaque.
        public var alpha: Data?

        public init(jpeg: Data, rect: FWRect, pixelWidth: Int, pixelHeight: Int, alpha: Data? = nil) {
            self.jpeg = jpeg
            self.rect = rect
            self.pixelWidth = pixelWidth
            self.pixelHeight = pixelHeight
            self.alpha = alpha
        }
    }

    public struct Page: Equatable, Sendable {
        public var width: Double
        public var height: Double
        public var rotation: Int
        public var texts: [TextObject]
        public var fills: [FWRect]
        public var images: [ImageObject]

        public init(width: Double = PageSize.usLetter.width, height: Double = PageSize.usLetter.height, rotation: Int = 0, texts: [TextObject] = [], fills: [FWRect] = [], images: [ImageObject] = []) {
            self.width = width
            self.height = height
            self.rotation = rotation
            self.texts = texts
            self.fills = fills
            self.images = images
        }

        public func spans() -> [TextSpan] {
            texts.map { TextSpan(text: $0.text, rect: $0.rect()) }
        }
    }

    public var pages: [Page]
    public var title: String
    public var author: String
    public var subject: String
    public var gps: String?

    public init(pages: [Page], title: String = "", author: String = "", subject: String = "", gps: String? = nil) {
        self.pages = pages
        self.title = title
        self.author = author
        self.subject = subject
        self.gps = gps
    }

    public func extractableText() -> String {
        pages.map { page in
            page.texts.map(\.text).joined(separator: "\n")
        }.joined(separator: "\u{0C}")
    }

    public func redacting(_ boxes: [RedactBox]) -> SimplePDF {
        var copy = self
        for index in copy.pages.indices {
            let rects = boxes.filter { $0.pageIndex == index }.map(\.rect)
            guard !rects.isEmpty else { continue }
            copy.pages[index].texts.removeAll { text in
                rects.contains { text.rect().intersects($0) }
            }
            copy.pages[index].fills.append(contentsOf: rects)
        }
        return copy
    }

    public func data() -> Data {
        var builder = PDFBuilder()
        var imageIDs: [[Int]] = Array(repeating: [], count: pages.count)
        for (pageIndex, page) in pages.enumerated() {
            for image in page.images {
                var maskRef = ""
                if let alpha = image.alpha, image.pixelWidth > 0, alpha.count == image.pixelWidth * image.pixelHeight {
                    let maskID = builder.addStream(dictionary: "<< /Type /XObject /Subtype /Image /Width \(image.pixelWidth) /Height \(image.pixelHeight) /ColorSpace /DeviceGray /BitsPerComponent 8 /Length \(alpha.count) >>", stream: alpha)
                    maskRef = " /SMask \(maskID) 0 R"
                }
                let dictionary = "<< /Type /XObject /Subtype /Image /Width \(image.pixelWidth) /Height \(image.pixelHeight) /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /DCTDecode /Length \(image.jpeg.count)\(maskRef) >>"
                let id = builder.addStream(dictionary: dictionary, stream: image.jpeg)
                imageIDs[pageIndex].append(id)
            }
        }
        let fontID = builder.add("<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>")
        var contentIDs: [Int] = []
        for (pageIndex, page) in pages.enumerated() {
            let stream = contentStream(page, imageIDs: imageIDs[pageIndex])
            let id = builder.addStream(dictionary: "<< /Length \(stream.count) >>", stream: stream)
            contentIDs.append(id)
        }
        var pageIDs: [Int] = []
        let pagesID = builder.reserve()
        for (pageIndex, page) in pages.enumerated() {
            var xobjects = ""
            if !imageIDs[pageIndex].isEmpty {
                let pairs = imageIDs[pageIndex].enumerated().map { "/Im\($0.offset) \($0.element) 0 R" }.joined(separator: " ")
                xobjects = " /XObject << \(pairs) >>"
            }
            let id = builder.add("<< /Type /Page /Parent \(pagesID) 0 R /MediaBox [0 0 \(format(page.width)) \(format(page.height))] /Rotate \(normalized(page.rotation)) /Contents \(contentIDs[pageIndex]) 0 R /Resources << /Font << /F1 \(fontID) 0 R >>\(xobjects) >> >>")
            pageIDs.append(id)
        }
        let kids = pageIDs.map { "\($0) 0 R" }.joined(separator: " ")
        builder.fill(pagesID, "<< /Type /Pages /Count \(pageIDs.count) /Kids [\(kids)] >>")
        let catalogID = builder.add("<< /Type /Catalog /Pages \(pagesID) 0 R >>")
        var info = "<< "
        info += "/Title \(pdfString(title)) /Author \(pdfString(author)) /Subject \(pdfString(subject))"
        if let gps, !gps.isEmpty {
            info += " /FileWheelGPS \(pdfString(gps))"
        }
        info += " >>"
        let infoID = builder.add(info)
        return builder.finish(root: catalogID, info: infoID)
    }

    public static func read(_ data: Data) throws -> SimplePDF {
        if data.range(of: Data("/Encrypt".utf8)) != nil {
            throw ToolError.passwordProtected
        }
        let objects = try PDFScanner.objects(in: data)
        guard let catalog = objects.values.first(where: { $0.dictionary.contains("/Type /Catalog") || $0.dictionary.contains("/Type/Catalog") }) else {
            throw ToolError.message("Could not read this PDF.")
        }
        guard let pagesRef = PDFScanner.int(after: "/Pages", in: catalog.dictionary), let pages = objects[pagesRef] else {
            throw ToolError.message("Could not read this PDF.")
        }
        let kids = PDFScanner.refs(inKids: pages.dictionary)
        var parsedPages: [Page] = []
        for kid in kids {
            guard let page = objects[kid] else { continue }
            let box = PDFScanner.mediaBox(page.dictionary) ?? PageSize.usLetter
            let rotation = PDFScanner.int(after: "/Rotate", in: page.dictionary) ?? 0
            var texts: [TextObject] = []
            var fills: [FWRect] = []
            var images: [ImageObject] = []
            if let contentsID = PDFScanner.int(after: "/Contents", in: page.dictionary), let contents = objects[contentsID]?.stream {
                let parsed = PDFScanner.parseContent(contents, pageHeight: box.height)
                texts = parsed.texts
                fills = parsed.fills
                for (name, rect) in parsed.images {
                    if let imageID = PDFScanner.xobjectID(named: name, in: page.dictionary), let image = objects[imageID], let stream = image.stream {
                        let width = PDFScanner.int(after: "/Width", in: image.dictionary) ?? 1
                        let height = PDFScanner.int(after: "/Height", in: image.dictionary) ?? 1
                        images.append(ImageObject(jpeg: stream, rect: rect, pixelWidth: width, pixelHeight: height))
                    }
                }
            }
            parsedPages.append(Page(width: box.width, height: box.height, rotation: rotation, texts: texts, fills: fills, images: images))
        }
        var title = ""
        var author = ""
        var subject = ""
        var gps: String?
        if let info = objects.values.first(where: { $0.dictionary.contains("/Title") || $0.dictionary.contains("/FileWheelGPS") || $0.dictionary.contains("/Author") }) {
            title = PDFScanner.string(named: "/Title", in: info.dictionary) ?? ""
            author = PDFScanner.string(named: "/Author", in: info.dictionary) ?? ""
            subject = PDFScanner.string(named: "/Subject", in: info.dictionary) ?? ""
            gps = PDFScanner.string(named: "/FileWheelGPS", in: info.dictionary)
        }
        return SimplePDF(pages: parsedPages, title: title, author: author, subject: subject, gps: gps)
    }

    private func contentStream(_ page: Page, imageIDs: [Int]) -> Data {
        var lines: [String] = []
        for text in page.texts {
            let pdfY = page.height - text.y - text.size
            lines.append("BT")
            lines.append("/F1 \(format(text.size)) Tf")
            if text.invisible {
                lines.append("3 Tr")
            }
            lines.append("1 0 0 1 \(format(text.x)) \(format(pdfY)) Tm")
            lines.append("\(pdfString(text.text)) Tj")
            if text.invisible {
                lines.append("0 Tr")
            }
            lines.append("ET")
        }
        for fill in page.fills {
            let pdfY = page.height - fill.y - fill.height
            lines.append("0 g")
            lines.append("\(format(fill.x)) \(format(pdfY)) \(format(fill.width)) \(format(fill.height)) re")
            lines.append("f")
        }
        for (index, image) in page.images.enumerated() where index < imageIDs.count {
            let pdfY = page.height - image.rect.y - image.rect.height
            lines.append("q")
            lines.append("\(format(image.rect.width)) 0 0 \(format(image.rect.height)) \(format(image.rect.x)) \(format(pdfY)) cm")
            lines.append("/Im\(index) Do")
            lines.append("Q")
        }
        return Data(lines.joined(separator: "\n").utf8)
    }

    private func format(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    private func normalized(_ rotation: Int) -> Int {
        let value = ((rotation % 360) + 360) % 360
        return [0, 90, 180, 270].contains(value) ? value : 0
    }

    private func pdfString(_ text: String) -> String {
        let escaped = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "(", with: "\\(")
            .replacingOccurrences(of: ")", with: "\\)")
        return "(\(escaped))"
    }
}

public struct RedactBox: Equatable, Sendable {
    public var pageIndex: Int
    public var rect: FWRect

    public init(pageIndex: Int, rect: FWRect) {
        self.pageIndex = pageIndex
        self.rect = rect
    }
}

private struct PDFObject {
    var dictionary: String
    var stream: Data?
}

private struct PDFBuilder {
    private var chunks: [Data?] = []

    mutating func reserve() -> Int {
        chunks.append(nil)
        return chunks.count
    }

    @discardableResult
    mutating func add(_ dictionary: String) -> Int {
        chunks.append(Data("<<placeholder>>".utf8))
        let id = chunks.count
        fill(id, dictionary)
        return id
    }

    mutating func fill(_ id: Int, _ dictionary: String) {
        chunks[id - 1] = Data("\(id) 0 obj\n\(dictionary)\nendobj\n".utf8)
    }

    mutating func addStream(dictionary: String, stream: Data) -> Int {
        var body = Data("\(chunks.count + 1) 0 obj\n\(dictionary)\nstream\n".utf8)
        body.append(stream)
        if !stream.hasSuffix(Data("\n".utf8)) {
            body.append(Data("\n".utf8))
        }
        body.append(Data("endstream\nendobj\n".utf8))
        chunks.append(body)
        return chunks.count
    }

    func finish(root: Int, info: Int) -> Data {
        var data = Data("%PDF-1.4\n%\u{E2}\u{E3}\u{CF}\u{D3}\n".utf8)
        var offsets: [Int] = []
        for chunk in chunks {
            offsets.append(data.count)
            data.append(chunk ?? Data())
        }
        let xref = data.count
        var table = "xref\n0 \(chunks.count + 1)\n0000000000 65535 f \n"
        for offset in offsets {
            table += String(format: "%010d 00000 n \n", offset)
        }
        data.append(Data(table.utf8))
        let trailer = "trailer\n<< /Size \(chunks.count + 1) /Root \(root) 0 R /Info \(info) 0 R >>\nstartxref\n\(xref)\n%%EOF\n"
        data.append(Data(trailer.utf8))
        return data
    }
}

private enum PDFScanner {
    static func objects(in data: Data) throws -> [Int: PDFObject] {
        let bytes = [UInt8](data)
        var cursor = 0
        var found: [Int: PDFObject] = [:]
        let objMarker = Array(" 0 obj\n".utf8)
        let streamMarker = Array("stream\n".utf8)
        let endMarker = Array("endobj".utf8)
        while let objAt = index(of: objMarker, in: bytes, from: cursor) {
            var numberStart = objAt
            while numberStart > 0 && bytes[numberStart - 1].isNumber {
                numberStart -= 1
            }
            let idText = String(bytes: bytes[numberStart..<objAt], encoding: .ascii)?.trimmingCharacters(in: .whitespaces) ?? ""
            guard let id = Int(idText) else { break }
            let body = objAt + objMarker.count
            if let streamAt = index(of: streamMarker, in: bytes, from: body),
               let endAt = index(of: endMarker, in: bytes, from: body),
               streamAt < endAt {
                let dict = String(decoding: bytes[body..<streamAt], as: UTF8.self)
                let length = int(after: "/Length", in: dict) ?? 0
                let streamStart = streamAt + streamMarker.count
                let streamEnd = min(bytes.count, streamStart + length)
                found[id] = PDFObject(dictionary: dict, stream: Data(bytes[streamStart..<streamEnd]))
                cursor = max(streamEnd, endAt + endMarker.count)
            } else if let endAt = index(of: endMarker, in: bytes, from: body) {
                let dict = String(decoding: bytes[body..<endAt], as: UTF8.self)
                found[id] = PDFObject(dictionary: dict, stream: nil)
                cursor = endAt + endMarker.count
            } else {
                break
            }
        }
        if found.isEmpty {
            throw ToolError.message("Could not read this PDF (no objects).")
        }
        return found
    }

    static func parseContent(_ data: Data, pageHeight: Double) -> (texts: [SimplePDF.TextObject], fills: [FWRect], images: [(String, FWRect)]) {
        let text = String(decoding: data, as: UTF8.self)
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var texts: [SimplePDF.TextObject] = []
        var fills: [FWRect] = []
        var images: [(String, FWRect)] = []
        var size = 12.0
        var renderMode = 0
        var cursor = 0
        while cursor < lines.count {
            let line = lines[cursor]
            if line.hasSuffix(" Tr"), let mode = Int(line.split(separator: " ").first.map(String.init) ?? "") {
                renderMode = mode
            }
            if line.contains(" Tf"), let value = Double(line.split(separator: " ").dropFirst().first.map(String.init) ?? "") {
                size = value
            }
            if line.contains(" Tm"), cursor + 1 < lines.count {
                let numbers = numbersIn(line)
                if numbers.count >= 6, let literal = stringLiteral(lines[cursor + 1]) {
                    let pdfY = numbers[5]
                    let top = pageHeight - pdfY - size
                    texts.append(SimplePDF.TextObject(text: literal, x: numbers[4], y: top, size: size, invisible: renderMode == 3))
                }
            }
            if line.contains(" re") {
                let numbers = numbersIn(line)
                if numbers.count >= 4 {
                    let top = pageHeight - numbers[1] - numbers[3]
                    fills.append(FWRect(x: numbers[0], y: top, width: numbers[2], height: numbers[3]))
                }
            }
            if line.contains(" cm"), cursor + 1 < lines.count, lines[cursor + 1].contains(" Do") {
                let numbers = numbersIn(line)
                let name = lines[cursor + 1].split(separator: " ").first.map { String($0.dropFirst()) } ?? ""
                if numbers.count >= 6 {
                    let top = pageHeight - numbers[5] - numbers[3]
                    images.append((name, FWRect(x: numbers[4], y: top, width: numbers[0], height: numbers[3])))
                }
            }
            cursor += 1
        }
        return (texts, fills, images)
    }

    static func int(after token: String, in text: String) -> Int? {
        guard let range = text.range(of: token) else { return nil }
        let rest = text[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        let digits = rest.prefix { $0.isNumber }
        return Int(digits)
    }

    static func refs(inKids text: String) -> [Int] {
        guard let start = text.range(of: "/Kids"), let bracket = text[start.upperBound...].firstIndex(of: "[") else { return [] }
        let tail = text[text.index(after: bracket)...]
        guard let end = tail.firstIndex(of: "]") else { return [] }
        let body = tail[..<end]
        var ids: [Int] = []
        let parts = body.split(separator: " ")
        var index = 0
        while index < parts.count {
            if let id = Int(parts[index]), index + 2 < parts.count, parts[index + 1] == "0", parts[index + 2] == "R" {
                ids.append(id)
                index += 3
            } else {
                index += 1
            }
        }
        return ids
    }

    static func mediaBox(_ text: String) -> FWSize? {
        guard let marker = text.range(of: "/MediaBox") else { return nil }
        let rest = text[marker.upperBound...]
        guard let open = rest.firstIndex(of: "["), let close = rest[open...].firstIndex(of: "]"), open < close else { return nil }
        let body = String(rest[rest.index(after: open)..<close])
        let numbers = body.split(whereSeparator: { $0 == " " || $0 == "\n" }).compactMap { Double($0) }
        guard numbers.count >= 4 else { return nil }
        return FWSize(width: numbers[2] - numbers[0], height: numbers[3] - numbers[1])
    }

    static func string(named token: String, in text: String) -> String? {
        guard let range = text.range(of: token + " (") ?? text.range(of: token + "(") else { return nil }
        let start = text.index(after: text[range.upperBound...].firstIndex(of: "(") ?? text.index(before: range.upperBound))
        var result = ""
        var escaped = false
        var index = start
        while index < text.endIndex {
            let character = text[index]
            if escaped {
                result.append(character)
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else if character == ")" {
                break
            } else {
                result.append(character)
            }
            index = text.index(after: index)
        }
        return result
    }

    static func xobjectID(named name: String, in text: String) -> Int? {
        let token = "/\(name)"
        guard let range = text.range(of: token) else { return nil }
        return int(after: token, in: String(text[range.lowerBound...]))
    }

    private static func numbersIn(_ line: String) -> [Double] {
        let cleaned = line.replacingOccurrences(of: "Tm", with: "").replacingOccurrences(of: "re", with: "").replacingOccurrences(of: "cm", with: "")
        return cleaned.split(separator: " ").compactMap { Double($0) }
    }

    private static func stringLiteral(_ line: String) -> String? {
        guard let open = line.firstIndex(of: "("), let close = line.lastIndex(of: ")"), open < close else { return nil }
        let body = String(line[line.index(after: open)..<close])
        return body.replacingOccurrences(of: "\\(", with: "(").replacingOccurrences(of: "\\)", with: ")").replacingOccurrences(of: "\\\\", with: "\\")
    }

    private static func index(of pattern: [UInt8], in bytes: [UInt8], from start: Int) -> Int? {
        guard !pattern.isEmpty, start < bytes.count else { return nil }
        var cursor = start
        while cursor + pattern.count <= bytes.count {
            if Array(bytes[cursor..<(cursor + pattern.count)]) == pattern {
                return cursor
            }
            cursor += 1
        }
        return nil
    }
}

private extension UInt8 {
    var isNumber: Bool { self >= 48 && self <= 57 }
}

private extension Data {
    func hasSuffix(_ other: Data) -> Bool {
        guard count >= other.count else { return false }
        return dropFirst(count - other.count) == other
    }
}
