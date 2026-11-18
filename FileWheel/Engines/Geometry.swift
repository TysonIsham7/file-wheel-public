import Foundation

public struct FWPoint: Equatable, Hashable, Sendable, Codable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public struct FWSize: Equatable, Hashable, Sendable, Codable {
    public var width: Double
    public var height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }
}

public struct FWRect: Equatable, Hashable, Sendable, Codable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var maxX: Double { x + width }
    public var maxY: Double { y + height }
    public var isEmpty: Bool { width <= 0 || height <= 0 }

    public func intersects(_ other: FWRect) -> Bool {
        x < other.maxX && maxX > other.x && y < other.maxY && maxY > other.y
    }

    public func contains(_ point: FWPoint) -> Bool {
        point.x >= x && point.x < maxX && point.y >= y && point.y < maxY
    }

    public func integral() -> FWRect {
        let minX = x.rounded(.down)
        let minY = y.rounded(.down)
        let maxX = self.maxX.rounded(.up)
        let maxY = self.maxY.rounded(.up)
        return FWRect(x: minX, y: minY, width: max(0, maxX - minX), height: max(0, maxY - minY))
    }
}

public enum PageSize {
    public static let usLetter = FWSize(width: 612, height: 792)
}

public enum PageLayout {
    /// Top-left origin. Fit keeps the whole image inside the page.
    public static func fit(image: FWSize, page: FWSize) -> FWRect {
        guard image.width > 0, image.height > 0, page.width > 0, page.height > 0 else {
            return FWRect(x: 0, y: 0, width: 0, height: 0)
        }
        let scale = min(page.width / image.width, page.height / image.height)
        let width = image.width * scale
        let height = image.height * scale
        return FWRect(x: (page.width - width) / 2, y: (page.height - height) / 2, width: width, height: height)
    }

    /// Top-left origin. Fill covers the page and may crop.
    public static func fill(image: FWSize, page: FWSize) -> FWRect {
        guard image.width > 0, image.height > 0, page.width > 0, page.height > 0 else {
            return FWRect(x: 0, y: 0, width: 0, height: 0)
        }
        let scale = max(page.width / image.width, page.height / image.height)
        let width = image.width * scale
        let height = image.height * scale
        return FWRect(x: (page.width - width) / 2, y: (page.height - height) / 2, width: width, height: height)
    }
}

public enum SVGRaster {
    public static let choices = [72, 144, 300]

    public static func pixels(points: Double, dpi: Int) -> Int {
        max(1, Int((points * Double(dpi) / 72.0).rounded()))
    }
}

public struct RGBA: Equatable, Sendable {
    public var r, g, b, a: UInt8

    public init(r: UInt8, g: UInt8, b: UInt8, a: UInt8 = 255) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }

    public static let black = RGBA(r: 0, g: 0, b: 0)
    public static let white = RGBA(r: 255, g: 255, b: 255)
}

public struct TextSpan: Equatable, Sendable {
    public var text: String
    public var rect: FWRect

    public init(text: String, rect: FWRect) {
        self.text = text
        self.rect = rect
    }
}

public enum Redaction {
    public static func remainingText(_ spans: [TextSpan], covering rects: [FWRect]) -> String {
        spans.filter { span in
            !rects.contains(where: { span.rect.intersects($0) })
        }.map(\.text).joined(separator: "\n")
    }
}
