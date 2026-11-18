import Foundation

#if canImport(ImageIO) && canImport(CoreGraphics)
import ImageIO
import CoreGraphics

enum AppleImageEngine {
    static func decode(_ url: URL) throws -> RasterImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw ToolError.message("Could not read the image.")
        }
        let width = image.width
        let height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw ToolError.message("Could not read the image.")
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return RasterImage(width: width, height: height, rgba: pixels)
    }

    static func encode(_ image: RasterImage, to url: URL, format: String, quality: Double) throws {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: image.width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let buffer = context.data else {
            throw ToolError.message("Could not write the image.")
        }
        let bytes = buffer.bindMemory(to: UInt8.self, capacity: image.rgba.count)
        for index in image.rgba.indices {
            bytes[index] = image.rgba[index]
        }
        guard let cgImage = context.makeImage() else {
            throw ToolError.message("Could not write the image.")
        }
        let type: CFString
        switch format {
        case "png": type = "public.png" as CFString
        case "tif": type = "public.tiff" as CFString
        case "gif": type = "com.compuserve.gif" as CFString
        case "heic": type = "public.heic" as CFString
        case "avif": type = "public.avif" as CFString
        case "bmp": type = "com.microsoft.bmp" as CFString
        case "webp": type = "org.webmproject.webp" as CFString
        default: type = "public.jpeg" as CFString
        }
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type, 1, nil) else {
            throw ToolError.message("Could not write the image.")
        }
        let options = [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
        CGImageDestinationAddImage(destination, cgImage, options)
        if !CGImageDestinationFinalize(destination) {
            throw ToolError.message("Could not write the image.")
        }
    }
}
#endif

#if canImport(Vision) && canImport(AppKit)
import Vision
import AppKit

public struct VisionQRDetector: QRDetecting {
    public init() {}

    public func codes(in imageURL: URL) throws -> [String] {
        guard let image = NSImage(contentsOf: imageURL),
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let cgImage = bitmap.cgImage else {
            return []
        }
        let request = VNDetectBarcodesRequest()
        request.symbologies = [.qr]
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])
        return (request.results ?? []).compactMap { $0.payloadStringValue }
    }
}
#endif

#if canImport(PDFKit) && canImport(AppKit)
import PDFKit
import AppKit

enum PDFKitEngine {
    static func isPasswordProtected(_ url: URL) -> Bool {
        guard let document = PDFDocument(url: url) else { return false }
        return document.isLocked || document.isEncrypted
    }

    static func rasterRedact(source: URL, boxes: [RedactBox], destination: URL) throws {
        guard let document = PDFDocument(url: source) else {
            throw ToolError.message("Could not read this PDF.")
        }
        if document.isLocked {
            throw ToolError.passwordProtected
        }
        let output = PDFDocument()
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            let bounds = page.bounds(for: .mediaBox)
            let scale: CGFloat = 2
            let size = NSSize(width: bounds.width * scale, height: bounds.height * scale)
            let image = NSImage(size: size)
            image.lockFocus()
            if let context = NSGraphicsContext.current?.cgContext {
                context.saveGState()
                context.scaleBy(x: scale, y: scale)
                page.draw(with: .mediaBox, to: context)
                context.setFillColor(NSColor.black.cgColor)
                for box in boxes where box.pageIndex == index {
                    let rect = CGRect(x: box.rect.x, y: bounds.height - box.rect.y - box.rect.height, width: box.rect.width, height: box.rect.height)
                    context.fill(rect)
                }
                context.restoreGState()
            }
            image.unlockFocus()
            guard let newPage = PDFPage(image: image) else { continue }
            output.insert(newPage, at: output.pageCount)
        }
        if !output.write(to: destination) {
            throw ToolError.message("Could not write the PDF.")
        }
    }
}
#endif

#if canImport(Security)
import Security

public final class KeychainAPIKeyStore: APIKeyStoring {
    public init() {}

    private let service = "app.filewheel.xai-api-key"
    private let account = "xai"

    public func read() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func save(_ value: String) throws {
        try clear()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(value.utf8)
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            throw ToolError.message("Could not save the xAI key in the Keychain.")
        }
    }

    public func clear() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
#endif

#if canImport(ServiceManagement)
import ServiceManagement

public struct MacLoginItem: LoginItemManaging {
    public init() {}

    public func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    public func isEnabled() -> Bool {
        SMAppService.mainApp.status == .enabled
    }
}
#endif
