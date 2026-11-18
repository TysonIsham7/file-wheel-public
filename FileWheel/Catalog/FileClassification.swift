import Foundation

public struct FileInput: Equatable, Hashable, Sendable, Codable {
    public var url: URL
    public var normalizedExtension: String
    public var kind: MediaKind
    public var isDirectory: Bool

    public init(url: URL, normalizedExtension: String, kind: MediaKind, isDirectory: Bool) {
        self.url = url
        self.normalizedExtension = normalizedExtension
        self.kind = kind
        self.isDirectory = isDirectory
    }

    public var baseName: String {
        let stem = url.deletingPathExtension().lastPathComponent
        if normalizedExtension == "tar.gz" {
            let lower = stem.lowercased()
            if lower.hasSuffix(".tar") {
                return String(stem.dropLast(4))
            }
        }
        return stem
    }
}

public enum MediaClassifier {
    public static let rasterExtensions: Set<String> = ["jpg", "png", "webp", "heic", "tif", "avif", "bmp", "gif"]
    public static let audioExtensions: Set<String> = ["mp3", "m4a", "wav", "flac", "ogg", "opus", "aiff", "wma"]
    public static let videoExtensions: Set<String> = ["mp4", "mov", "mkv", "webm", "avi", "wmv"]
    public static let archiveExtensions: Set<String> = ["zip", "tar", "tar.gz", "gz", "rar"]

    public static func normalizeExtension(_ raw: String) -> String {
        switch raw.lowercased() {
        case "jpeg", "jpg":
            return "jpg"
        case "tif", "tiff":
            return "tif"
        case "tgz":
            return "tar.gz"
        case "aif":
            return "aiff"
        default:
            return raw.lowercased()
        }
    }

    public static func normalizedExtension(for url: URL) -> String {
        let name = url.lastPathComponent.lowercased()
        if name.hasSuffix(".tar.gz") || name.hasSuffix(".tgz") {
            return "tar.gz"
        }
        return normalizeExtension(url.pathExtension)
    }

    public static func kind(for ext: String, isDirectory: Bool) -> MediaKind {
        if isDirectory {
            return .folder
        }
        if ext == "svg" || rasterExtensions.contains(ext) {
            return .image
        }
        if videoExtensions.contains(ext) {
            return .video
        }
        if audioExtensions.contains(ext) {
            return .audio
        }
        switch ext {
        case "pdf":
            return .pdf
        case "txt":
            return .text
        case "md":
            return .markdown
        case "docx":
            return .word
        case "srt", "vtt":
            return .subtitle
        default:
            if archiveExtensions.contains(ext) {
                return .archive
            }
            return .unknown
        }
    }

    public static func classify(_ url: URL, isDirectory: Bool? = nil) -> FileInput {
        let directory: Bool
        if let isDirectory {
            directory = isDirectory
        } else {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) {
                directory = isDir.boolValue
            } else {
                directory = url.hasDirectoryPath
            }
        }
        let ext = directory ? "" : normalizedExtension(for: url)
        return FileInput(
            url: url,
            normalizedExtension: ext,
            kind: kind(for: ext, isDirectory: directory),
            isDirectory: directory
        )
    }
}
