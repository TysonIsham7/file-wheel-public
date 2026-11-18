import Foundation

enum GzipName {
    /// Original filename stored in a gzip header, basename only.
    static func originalFilename(in data: Data) -> String? {
        guard data.count >= 10, data[0] == 0x1F, data[1] == 0x8B else { return nil }
        let flags = data[3]
        let hasName = flags & 0x08 != 0
        guard hasName else { return nil }
        var index = 10
        if flags & 0x04 != 0 {
            guard index + 2 <= data.count else { return nil }
            let extra = Int(data[index]) | (Int(data[index + 1]) << 8)
            index += 2 + extra
        }
        guard index < data.count else { return nil }
        var bytes: [UInt8] = []
        while index < data.count, data[index] != 0 {
            bytes.append(data[index])
            index += 1
        }
        guard let name = String(bytes: bytes, encoding: .isoLatin1) ?? String(bytes: bytes, encoding: .utf8) else {
            return nil
        }
        let base = (name as NSString).lastPathComponent
        if base.isEmpty || base == "." || base == ".." || !ArchivePathSafety.isSafe(base) {
            return nil
        }
        return base
    }

    static func outputBaseName(source: URL, headerSample: Data) -> String {
        if let stored = originalFilename(in: headerSample) {
            return (stored as NSString).deletingPathExtension
        }
        return Phase3Naming.sourceBaseName(for: source)
    }
}

enum ArchiveCommands {
    static let tar = URL(fileURLWithPath: "/usr/bin/tar")
    static let gzip = URL(fileURLWithPath: "/usr/bin/gzip")
    static let gunzip = URL(fileURLWithPath: "/usr/bin/gunzip")
    static let zip = URL(fileURLWithPath: "/usr/bin/zip")

    static func require(_ url: URL, missing: String) throws {
        if !FileManager.default.isExecutableFile(atPath: url.path) {
            throw FileWheelError(missing)
        }
    }
}
