import Foundation

public enum OutputNaming {
    public static func destinationURL(
        source: URL,
        targetExtension: String,
        directory: URL,
        fileManager: FileManager = .default
    ) -> URL {
        let names = (try? fileManager.contentsOfDirectory(atPath: directory.path)) ?? []
        let existing = Set(names.map { $0.lowercased() })
        let name = uniqueName(
            base: source.deletingPathExtension().lastPathComponent,
            ext: targetExtension,
            sourceFileName: source.lastPathComponent,
            existingLowercased: existing
        )
        return directory.appendingPathComponent(name)
    }

    /// `Name.ext`, then `Name 2.ext`. Never returns the source filename.
    public static func uniqueName(
        base: String,
        ext: String,
        sourceFileName: String?,
        existingLowercased: Set<String>
    ) -> String {
        let sourceLower = sourceFileName?.lowercased()
        var index = 1
        while index < 10_000 {
            let name = index == 1 ? "\(base).\(ext)" : "\(base) \(index).\(ext)"
            let lower = name.lowercased()
            if lower != sourceLower && !existingLowercased.contains(lower) {
                return name
            }
            index += 1
        }
        return "\(base) \(UUID().uuidString).\(ext)"
    }
}

enum JobPublish {
    static func publish(temp: URL, to final: URL, fileManager: FileManager = .default) throws {
        if fileManager.fileExists(atPath: final.path) {
            _ = try fileManager.replaceItemAt(final, withItemAt: temp)
        } else {
            try fileManager.moveItem(at: temp, to: final)
        }
    }
}
