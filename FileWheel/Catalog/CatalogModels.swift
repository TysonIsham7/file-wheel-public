import Foundation

/// Directed wheel entries. The wheel, Services menu, and About read this catalog.
/// Phase 1 and Phase 2 append image, audio, and video rows through `FileWheelCatalog`.
struct Phase3Entry: Identifiable, Equatable {
    let id: String
    let label: String
    let progressTitle: String
    let source: CatalogSource
    let kind: CatalogKind
    /// Read aloud is counted on its own About line, not in the pair total.
    let countsAsPair: Bool

    init(
        id: String,
        label: String,
        progressTitle: String? = nil,
        source: CatalogSource,
        kind: CatalogKind,
        countsAsPair: Bool = true
    ) {
        self.id = id
        self.label = label
        self.progressTitle = progressTitle ?? label
        self.source = source
        self.kind = kind
        self.countsAsPair = countsAsPair
    }
}

enum CatalogKind: Equatable {
    case document
    case archive
    case readAloud
}

enum CatalogSource: Equatable {
    /// Every dropped item is a file of one of these formats.
    case files(Set<String>)
    /// One non-archive file, and a folder when `folders` is true.
    /// `gz` packing sets `folders` to false.
    case pack(folders: Bool)
}

struct DroppedFile: Equatable {
    let url: URL
    let isDirectory: Bool
    /// Catalog format key: `pdf`, `tar.gz`, `directory`, …
    let format: String

    static let archiveFormats: Set<String> = ["zip", "tar", "tar.gz", "gz", "rar"]

    static func inspect(_ url: URL, isDirectory: Bool? = nil) -> DroppedFile {
        let directory = isDirectory ?? url.hasDirectoryPath
        if directory {
            return DroppedFile(url: url, isDirectory: true, format: "directory")
        }
        return DroppedFile(url: url, isDirectory: false, format: formatKey(for: url))
    }

    static func formatKey(for url: URL) -> String {
        let name = url.lastPathComponent.lowercased()
        if name.hasSuffix(".tar.gz") || name.hasSuffix(".tgz") {
            return "tar.gz"
        }
        switch url.pathExtension.lowercased() {
        case "pdf": return "pdf"
        case "txt", "text": return "txt"
        case "md", "markdown": return "md"
        case "docx": return "docx"
        case "srt": return "srt"
        case "vtt": return "vtt"
        case "zip": return "zip"
        case "tar": return "tar"
        case "gz": return "gz"
        case "rar": return "rar"
        case "jpg", "jpeg": return "jpg"
        case "tif", "tiff": return "tif"
        default: return url.pathExtension.lowercased()
        }
    }
}

extension CatalogSource {
    func matches(_ files: [DroppedFile]) -> Bool {
        guard !files.isEmpty else { return false }
        switch self {
        case .files(let formats):
            return files.allSatisfy { !$0.isDirectory && formats.contains($0.format) }
        case .pack(let folders):
            guard files.count == 1, let only = files.first else { return false }
            if only.isDirectory { return folders }
            return !DroppedFile.archiveFormats.contains(only.format)
        }
    }
}

enum FileWheelCatalog {
    /// Phase 1 and Phase 2 assign their rows here. About counts whatever is registered.
    static var additionalEntries: [Phase3Entry] = []

    static var entries: [Phase3Entry] {
        Phase3Catalog.entries + additionalEntries
    }

    static var pairCount: Int {
        entries.reduce(0) { $0 + ($1.countsAsPair ? 1 : 0) }
    }

    static var readAloudCount: Int {
        entries.reduce(0) { $0 + ($1.kind == .readAloud ? 1 : 0) }
    }

    static func entry(id: String) -> Phase3Entry? {
        entries.first { $0.id == id }
    }
}

struct Phase3Offer: Equatable {
    let wedges: [Phase3Entry]
    /// Set when the drag shares no action. The wheel shows this and accepts no drop.
    let notice: String?

    static func make(for files: [DroppedFile]) -> Phase3Offer {
        let wedges = FileWheelCatalog.entries.filter { $0.source.matches(files) }
        if wedges.isEmpty {
            return Phase3Offer(wedges: [], notice: files.isEmpty ? nil : FileWheelMessages.sameKindRequired)
        }
        return Phase3Offer(wedges: wedges, notice: nil)
    }
}
