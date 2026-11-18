import AppKit
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

public struct SignatureTransform: Equatable, Sendable {
    public var center: FWPoint
    public var baseSize: FWSize
    public var scale: Double

    public init(center: FWPoint, baseSize: FWSize, scale: Double = 1) {
        self.center = center
        self.baseSize = baseSize
        self.scale = scale
    }

    public var size: FWSize {
        FWSize(width: baseSize.width * scale, height: baseSize.height * scale)
    }

    public func rect() -> FWRect {
        let drawn = size
        return FWRect(x: center.x - drawn.width / 2, y: center.y - drawn.height / 2, width: drawn.width, height: drawn.height)
    }

    public static func placing(click: FWPoint, baseSize: FWSize, page: FWSize) -> SignatureTransform {
        placing(center: click, baseSize: baseSize, scale: 1, page: page)
    }

    public static func placing(center: FWPoint, baseSize: FWSize, scale: Double, page: FWSize) -> SignatureTransform {
        let safeScale = min(4, max(0.15, scale))
        var drawn = FWSize(width: max(1, baseSize.width) * safeScale, height: max(1, baseSize.height) * safeScale)
        drawn = fitted(size: drawn, page: page)
        let resolvedScale = baseSize.width > 0 ? drawn.width / baseSize.width : safeScale
        let halfW = drawn.width / 2
        let halfH = drawn.height / 2
        let clamped = FWPoint(
            x: min(max(center.x, halfW), max(halfW, page.width - halfW)),
            y: min(max(center.y, halfH), max(halfH, page.height - halfH))
        )
        return SignatureTransform(center: clamped, baseSize: baseSize, scale: resolvedScale)
    }

    public func scaled(to scale: Double, page: FWSize) -> SignatureTransform {
        SignatureTransform.placing(center: center, baseSize: baseSize, scale: scale, page: page)
    }

    public func replacingBaseSize(_ baseSize: FWSize, page: FWSize) -> SignatureTransform {
        SignatureTransform.placing(center: center, baseSize: baseSize, scale: scale, page: page)
    }

    public static func fitted(size: FWSize, page: FWSize) -> FWSize {
        guard size.width > 0, size.height > 0, page.width > 0, page.height > 0 else {
            return FWSize(width: 0, height: 0)
        }
        let scale = min(1, page.width / size.width, page.height / size.height)
        return FWSize(width: size.width * scale, height: size.height * scale)
    }
}

public struct SignatureStroke: Equatable, Sendable {
    public var points: [FWPoint]

    public init(points: [FWPoint]) {
        self.points = points
    }
}

public enum SignaturePlacementMath {
    public static func pagePoint(viewPoint: FWPoint, viewSize: FWSize, pageSize: FWSize) -> FWPoint {
        guard viewSize.width > 0, viewSize.height > 0, pageSize.width > 0, pageSize.height > 0 else {
            return FWPoint(x: 0, y: 0)
        }
        return FWPoint(
            x: min(max(0, viewPoint.x / viewSize.width * pageSize.width), pageSize.width),
            y: min(max(0, viewPoint.y / viewSize.height * pageSize.height), pageSize.height)
        )
    }

    public static func viewRect(_ rect: FWRect, page: FWSize, view: FWSize) -> FWRect {
        guard page.width > 0, page.height > 0 else { return FWRect(x: 0, y: 0, width: 0, height: 0) }
        let scaleX = view.width / page.width
        let scaleY = view.height / page.height
        return FWRect(x: rect.x * scaleX, y: rect.y * scaleY, width: rect.width * scaleX, height: rect.height * scaleY)
    }

    /// The caption sits under the signature, or above it when the signature is already at the bottom edge.
    public static func captionOrigin(signature: FWRect, pageHeight: Double, lineHeight: Double = 14) -> FWPoint {
        let below = signature.maxY + 6
        if below + lineHeight <= pageHeight {
            return FWPoint(x: signature.x, y: below)
        }
        return FWPoint(x: signature.x, y: max(0, signature.y - lineHeight - 6))
    }
}

public enum SignatureBackground {
    public static func removeNearWhite(_ rgba: inout [UInt8], threshold: UInt8 = 245) {
        var index = 0
        while index + 3 < rgba.count {
            let red = rgba[index]
            let green = rgba[index + 1]
            let blue = rgba[index + 2]
            if red >= threshold && green >= threshold && blue >= threshold {
                rgba[index] = 0
                rgba[index + 1] = 0
                rgba[index + 2] = 0
                rgba[index + 3] = 0
            }
            index += 4
        }
    }
}

public struct SignatureBitmap: Equatable, Sendable {
    public var width: Int
    public var height: Int
    public var rgba: [UInt8]

    public init(width: Int, height: Int, rgba: [UInt8]) {
        self.width = width
        self.height = height
        if rgba.count == width * height * 4 {
            self.rgba = rgba
        } else {
            self.rgba = [UInt8](repeating: 0, count: max(0, width * height * 4))
        }
    }

    public func alphaPlane() -> Data {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(max(0, width * height))
        let count = min(width * height, rgba.count / 4)
        for pixel in 0..<count {
            bytes.append(rgba[pixel * 4 + 3])
        }
        return Data(bytes)
    }
}

public struct PreparedSignature: Equatable, Sendable {
    public var jpeg: Data
    public var alpha: Data?
    public var png: Data
    public var pixelWidth: Int
    public var pixelHeight: Int

    public init(jpeg: Data, alpha: Data?, png: Data, pixelWidth: Int, pixelHeight: Int) {
        self.jpeg = jpeg
        self.alpha = alpha
        self.png = png
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
    }
}

public enum SignatureEncoding {
    public static let scriptFontNames = ["Snell Roundhand", "Bradley Hand", "Apple Chancery", "Savoye LET"]

    public static func bitmap(strokes: [SignatureStroke], width: Int, height: Int) -> SignatureBitmap {
        let pixelWidth = max(1, width)
        let pixelHeight = max(1, height)
        var storage = [UInt8](repeating: 0, count: pixelWidth * pixelHeight * 4)
        storage.withUnsafeMutableBytes { raw in
            guard let context = CGContext(
                data: raw.baseAddress,
                width: pixelWidth,
                height: pixelHeight,
                bitsPerComponent: 8,
                bytesPerRow: pixelWidth * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return }
            context.translateBy(x: 0, y: CGFloat(pixelHeight))
            context.scaleBy(x: 1, y: -1)
            context.setStrokeColor(NSColor.black.cgColor)
            context.setLineWidth(2.5)
            context.setLineCap(.round)
            context.setLineJoin(.round)
            for stroke in strokes {
                guard let first = stroke.points.first else { continue }
                context.beginPath()
                context.move(to: CGPoint(x: first.x, y: first.y))
                if stroke.points.count == 1 {
                    context.addLine(to: CGPoint(x: first.x + 0.5, y: first.y + 0.5))
                } else {
                    for point in stroke.points.dropFirst() {
                        context.addLine(to: CGPoint(x: point.x, y: point.y))
                    }
                }
                context.strokePath()
            }
        }
        return SignatureBitmap(width: pixelWidth, height: pixelHeight, rgba: storage)
    }

    public static func bitmap(text: String, pointSize: CGFloat = 56) -> SignatureBitmap? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let font = scriptFont(size: pointSize)
        let attributed = NSAttributedString(string: trimmed, attributes: [
            .font: font,
            .foregroundColor: NSColor.black
        ])
        let line = CTLineCreateWithAttributedString(attributed as CFAttributedString)
        var bounds = CTLineGetImageBounds(line, nil)
        if bounds.width < 1 || bounds.height < 1 {
            bounds.size = CGSize(width: 32, height: pointSize)
        }
        let width = max(1, Int(ceil(bounds.width)) + 24)
        let height = max(1, Int(ceil(bounds.height)) + 24)
        var storage = [UInt8](repeating: 0, count: width * height * 4)
        let drew = storage.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(
                data: raw.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.translateBy(x: 12 - bounds.minX, y: 12 - bounds.minY)
            CTLineDraw(line, context)
            return true
        }
        guard drew else { return nil }
        return SignatureBitmap(width: width, height: height, rgba: storage)
    }

    public static func bitmap(imageData: Data, maxSide: Int = 1200) throws -> SignatureBitmap {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw ToolError.message("Could not read that image.")
        }
        let longest = max(image.width, image.height)
        let scale = longest > maxSide ? Double(maxSide) / Double(longest) : 1
        let width = max(1, Int((Double(image.width) * scale).rounded()))
        let height = max(1, Int((Double(image.height) * scale).rounded()))
        var storage = [UInt8](repeating: 0, count: width * height * 4)
        let drew = storage.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(
                data: raw.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drew else { throw ToolError.message("Could not read that image.") }
        return SignatureBitmap(width: width, height: height, rgba: storage)
    }

    public static func prepare(_ bitmap: SignatureBitmap) throws -> PreparedSignature {
        guard bitmap.width > 0, bitmap.height > 0, bitmap.rgba.count == bitmap.width * bitmap.height * 4 else {
            throw ToolError.message("Could not prepare the signature image.")
        }
        let pngImage = try cgImage(premultiplied(bitmap.rgba), width: bitmap.width, height: bitmap.height)
        let jpegImage = try cgImage(matted(bitmap.rgba), width: bitmap.width, height: bitmap.height)
        let png = try pngData(pngImage)
        let jpeg: Data
        do {
            jpeg = try ImageEncoder.jpegData(jpegImage, quality: 0.92)
        } catch {
            throw ToolError.message("Could not prepare the signature image.")
        }
        let alpha = bitmap.alphaPlane()
        let hasTransparency = alpha.contains { $0 < 250 }
        return PreparedSignature(
            jpeg: jpeg,
            alpha: hasTransparency ? alpha : nil,
            png: png,
            pixelWidth: bitmap.width,
            pixelHeight: bitmap.height
        )
    }

    private static func scriptFont(size: CGFloat) -> NSFont {
        for name in scriptFontNames {
            if let font = NSFont(name: name, size: size) {
                return font
            }
        }
        return NSFont(name: "Times-Italic", size: size) ?? NSFont.systemFont(ofSize: size)
    }

    private static func premultiplied(_ rgba: [UInt8]) -> [UInt8] {
        var copy = rgba
        var index = 0
        while index + 3 < copy.count {
            let alpha = Int(copy[index + 3])
            copy[index] = UInt8((Int(copy[index]) * alpha) / 255)
            copy[index + 1] = UInt8((Int(copy[index + 1]) * alpha) / 255)
            copy[index + 2] = UInt8((Int(copy[index + 2]) * alpha) / 255)
            index += 4
        }
        return copy
    }

    private static func matted(_ rgba: [UInt8]) -> [UInt8] {
        var copy = rgba
        var index = 0
        while index + 3 < copy.count {
            if copy[index + 3] == 0 {
                copy[index] = 255
                copy[index + 1] = 255
                copy[index + 2] = 255
            }
            copy[index + 3] = 255
            index += 4
        }
        return copy
    }

    private static func cgImage(_ rgba: [UInt8], width: Int, height: Int) throws -> CGImage {
        guard let provider = CGDataProvider(data: Data(rgba) as CFData) else {
            throw ToolError.message("Could not prepare the signature image.")
        }
        guard let image = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ) else {
            throw ToolError.message("Could not prepare the signature image.")
        }
        return image
    }

    private static func pngData(_ image: CGImage) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw ToolError.message("Could not prepare the signature image.")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw ToolError.message("Could not prepare the signature image.")
        }
        return data as Data
    }
}

public enum SignatureComposer {
    public static func texts(placement: SignatureTransform, pageHeight: Double, text: String, date: String) -> [SimplePDF.TextObject] {
        let origin = SignaturePlacementMath.captionOrigin(signature: placement.rect(), pageHeight: pageHeight)
        var lines: [SimplePDF.TextObject] = []
        var cursor = origin.y
        let caption = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !caption.isEmpty {
            lines.append(SimplePDF.TextObject(text: caption, x: origin.x, y: cursor, size: 12))
            cursor += 16
        }
        let stamp = date.trimmingCharacters(in: .whitespacesAndNewlines)
        if !stamp.isEmpty {
            lines.append(SimplePDF.TextObject(text: stamp, x: origin.x, y: min(cursor, max(0, pageHeight - 12)), size: 12))
        }
        return lines
    }

    public static func applying(document: SimplePDF, pageIndex: Int, signature: SimplePDF.ImageObject, text: String, date: String) -> SimplePDF {
        guard document.pages.indices.contains(pageIndex) else { return document }
        var copy = document
        copy.pages[pageIndex].images.append(signature)
        let placement = SignatureTransform(
            center: FWPoint(x: signature.rect.x + signature.rect.width / 2, y: signature.rect.y + signature.rect.height / 2),
            baseSize: FWSize(width: signature.rect.width, height: signature.rect.height),
            scale: 1
        )
        copy.pages[pageIndex].texts.append(contentsOf: texts(placement: placement, pageHeight: copy.pages[pageIndex].height, text: text, date: date))
        return copy
    }
}

public struct SavedSignature: Equatable, Sendable, Identifiable, Codable {
    public var id: UUID
    public var name: String
    public var png: Data

    public init(id: UUID, name: String, png: Data) {
        self.id = id
        self.name = name
        self.png = png
    }
}

public struct SignatureStore: Sendable {
    public var directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public static func applicationSupportDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return base
            .appendingPathComponent("File Wheel", isDirectory: true)
            .appendingPathComponent("Signatures", isDirectory: true)
    }

    public func load() throws -> [SavedSignature] {
        let indexURL = directory.appendingPathComponent("index.json")
        guard FileManager.default.fileExists(atPath: indexURL.path) else { return [] }
        let data = try Data(contentsOf: indexURL)
        let records = try JSONDecoder().decode([SignatureRecord].self, from: data)
        return records.compactMap { record in
            guard isSafeFileName(record.file) else { return nil }
            let url = directory.appendingPathComponent(record.file)
            guard let png = try? Data(contentsOf: url) else { return nil }
            return SavedSignature(id: record.id, name: record.name, png: png)
        }
    }

    public func save(_ signature: SavedSignature) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = "\(signature.id.uuidString).png"
        let url = directory.appendingPathComponent(file)
        do {
            try signature.png.write(to: url, options: .atomic)
            var records = (try? loadRecords()) ?? []
            records.removeAll { $0.id == signature.id }
            records.append(SignatureRecord(id: signature.id, name: displayName(signature.name), file: file))
            try write(records)
        } catch let error as ToolError {
            throw error
        } catch {
            throw ToolError.message("Could not save the signature.")
        }
    }

    public func delete(id: UUID) throws {
        var records = (try? loadRecords()) ?? []
        if let record = records.first(where: { $0.id == id }), isSafeFileName(record.file) {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(record.file))
        }
        records.removeAll { $0.id == id }
        do {
            try write(records)
        } catch {
            throw ToolError.message("Could not save the signature.")
        }
    }

    private func loadRecords() throws -> [SignatureRecord] {
        let indexURL = directory.appendingPathComponent("index.json")
        guard FileManager.default.fileExists(atPath: indexURL.path) else { return [] }
        return try JSONDecoder().decode([SignatureRecord].self, from: Data(contentsOf: indexURL))
    }

    private func write(_ records: [SignatureRecord]) throws {
        let data = try JSONEncoder().encode(records)
        try data.write(to: directory.appendingPathComponent("index.json"), options: .atomic)
    }

    private func displayName(_ name: String) -> String {
        let cleaned = name
            .replacingOccurrences(of: "/", with: " ")
            .replacingOccurrences(of: ":", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty { return "Signature" }
        return String(cleaned.prefix(80))
    }

    private func isSafeFileName(_ name: String) -> Bool {
        !name.isEmpty && !name.contains("/") && !name.contains("\\") && !name.contains("..") && name == (name as NSString).lastPathComponent
    }
}

private struct SignatureRecord: Codable, Equatable {
    var id: UUID
    var name: String
    var file: String
}

public struct SignPDFParameters: Equatable, Sendable {
    public var imageJPEG: Data
    public var alpha: Data?
    public var pixelWidth: Int
    public var pixelHeight: Int
    public var pageIndex: Int
    public var placement: SignatureTransform?
    public var text: String
    public var date: String

    public init(
        imageJPEG: Data = Data(),
        alpha: Data? = nil,
        pixelWidth: Int = 0,
        pixelHeight: Int = 0,
        pageIndex: Int = 0,
        placement: SignatureTransform? = nil,
        text: String = "",
        date: String = ""
    ) {
        self.imageJPEG = imageJPEG
        self.alpha = alpha
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.pageIndex = pageIndex
        self.placement = placement
        self.text = text
        self.date = date
    }
}
