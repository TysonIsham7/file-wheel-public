import Foundation

public enum OutputNames {
    /// `Name.ext`, then `Name 2.ext`, then `Name 3.ext`. Never returns the source URL.
    public static func allocate(
        directory: URL,
        base: String,
        ext: String,
        source: URL?,
        reserved: Set<String> = [],
        fileExists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }
    ) -> URL {
        let sourcePath = source?.standardizedFileURL.path
        let trimmedBase = base.isEmpty ? "File" : base
        let suffix = ext.isEmpty ? "" : ".\(ext)"
        var index = 1
        while index < 10_000 {
            let fileName = index == 1 ? "\(trimmedBase)\(suffix)" : "\(trimmedBase) \(index)\(suffix)"
            let url = directory.appendingPathComponent(fileName)
            let path = url.standardizedFileURL.path
            if path != sourcePath && !reserved.contains(fileName) && !fileExists(url) {
                return url
            }
            index += 1
        }
        return directory.appendingPathComponent("\(trimmedBase)-\(UUID().uuidString)\(suffix)")
    }

    public static func seriesBase(directory: URL, base: String, ext: String, source: URL?, fileExists: (URL) -> Bool) -> String {
        var candidate = base
        var index = 1
        while index < 1_000 {
            let first = allocate(
                directory: directory,
                base: "\(candidate)-001",
                ext: ext,
                source: source,
                reserved: [],
                fileExists: fileExists
            )
            if first.lastPathComponent == "\(candidate)-001.\(ext)" || ext.isEmpty && first.lastPathComponent == "\(candidate)-001" {
                return candidate
            }
            index += 1
            candidate = "\(base) \(index)"
        }
        return base
    }
}

public enum AtomicFileWrite {
    public static func commit(destination: URL, body: (URL) throws -> Void) throws {
        let directory = destination.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let temp = directory.appendingPathComponent(".\(destination.lastPathComponent).filewheel-\(UUID().uuidString).tmp")
        do {
            try body(temp)
            if FileManager.default.fileExists(atPath: destination.path) {
                _ = try FileManager.default.replaceItemAt(destination, withItemAt: temp)
            } else {
                try FileManager.default.moveItem(at: temp, to: destination)
            }
        } catch {
            try? FileManager.default.removeItem(at: temp)
            throw error
        }
    }
}

public enum DestinationFolder {
    public static func directory(for source: URL, settings: FileWheelSettings) throws -> URL {
        switch settings.output {
        case .besideOriginal:
            return source.deletingLastPathComponent()
        case .folder(let path):
            let url = URL(fileURLWithPath: path, isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }
    }
}
