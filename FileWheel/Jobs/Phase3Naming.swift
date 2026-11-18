import Foundation

/// Sibling names from spec section 6.
/// `Name.ext`, then `Name 2.ext`, then `Name 3.ext`. Never the source URL.
enum Phase3Naming {
    static func sourceBaseName(for url: URL) -> String {
        let name = url.lastPathComponent
        let lower = name.lowercased()
        if lower.hasSuffix(".tar.gz") {
            return String(name.dropLast(".tar.gz".count))
        }
        if lower.hasSuffix(".tgz") {
            return String(name.dropLast(".tgz".count))
        }
        return url.deletingPathExtension().lastPathComponent
    }

    static func uniqueFileURL(
        directory: URL,
        base: String,
        pathExtension: String,
        source: URL?,
        reserved: inout Set<URL>
    ) -> URL {
        unique(
            directory: directory,
            stem: base,
            suffix: pathExtension.isEmpty ? "" : ".\(pathExtension)",
            source: source,
            reserved: &reserved
        )
    }

    static func uniqueFolderURL(
        directory: URL,
        name: String,
        source: URL? = nil,
        reserved: inout Set<URL>
    ) -> URL {
        unique(directory: directory, stem: name, suffix: "", source: source, reserved: &reserved)
    }

    /// `Name-page-001.jpg` inside an already-unique folder, or beside the source for one page.
    static func pageFileName(base: String, page: Int, pathExtension: String) -> String {
        String(format: "%@-page-%03d.%@", base, page, pathExtension)
    }

    private static func unique(
        directory: URL,
        stem: String,
        suffix: String,
        source: URL?,
        reserved: inout Set<URL>
    ) -> URL {
        let sourceID = source?.standardizedFileURL
        let manager = FileManager.default
        var collision = 0
        while true {
            let fileName = collision == 0 ? "\(stem)\(suffix)" : "\(stem) \(collision + 1)\(suffix)"
            let candidate = directory.appendingPathComponent(fileName).standardizedFileURL
            collision += 1
            if let sourceID, candidate == sourceID { continue }
            if reserved.contains(candidate) { continue }
            if manager.fileExists(atPath: candidate.path) { continue }
            reserved.insert(candidate)
            return candidate
        }
    }
}

enum OutputPublisher {
    /// Publishes a finished temp item. `replaceItemAt` is atomic when the destination exists;
    /// when it does not, the temp item is moved into place.
    static func publish(temp: URL, to finalURL: URL) throws {
        let manager = FileManager.default
        if manager.fileExists(atPath: finalURL.path) {
            _ = try manager.replaceItemAt(finalURL, withItemAt: temp)
            return
        }
        do {
            _ = try manager.replaceItemAt(finalURL, withItemAt: temp)
        } catch {
            if manager.fileExists(atPath: temp.path) {
                try manager.moveItem(at: temp, to: finalURL)
            } else if !manager.fileExists(atPath: finalURL.path) {
                throw error
            }
        }
    }

    static func removeQuietly(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
