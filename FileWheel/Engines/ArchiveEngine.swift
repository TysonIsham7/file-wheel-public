import Foundation
import ZIPFoundation

/// zip, tar, tar.gz, gz, and rar-read.
/// RAR is extract-only, through `unar` installed on the Mac. Creating a RAR is not implemented.
@MainActor
enum ArchiveEngine {
    static func convert(
        source: URL,
        entry: Phase3Entry,
        destinationDirectory: URL,
        reserved: inout Set<URL>
    ) async throws -> URL {
        try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        let base = Phase3Naming.sourceBaseName(for: source)
        switch entry.id {
        case "pack.zip":
            return try await publishFile(extension: "zip", base: base, directory: destinationDirectory, source: source, reserved: &reserved) { temp in
                try await packZip(item: source, to: temp, keepParent: true)
            }
        case "pack.tar":
            return try await publishFile(extension: "tar", base: base, directory: destinationDirectory, source: source, reserved: &reserved) { temp in
                try await packTar(item: source, to: temp, compressed: false)
            }
        case "pack.tar.gz":
            return try await publishFile(extension: "tar.gz", base: base, directory: destinationDirectory, source: source, reserved: &reserved) { temp in
                try await packTar(item: source, to: temp, compressed: true)
            }
        case "pack.gz":
            if source.hasDirectoryPath {
                throw FileWheelError(FileWheelMessages.gzSingleFileOnly)
            }
            return try await publishFile(extension: "gz", base: base, directory: destinationDirectory, source: source, reserved: &reserved) { temp in
                try await gzipFile(source, to: temp)
            }
        case "zip.extract", "tar.extract", "tar.gz.extract", "rar.extract":
            return try await publishExtractedFolder(base: base, directory: destinationDirectory, reserved: &reserved) { folder in
                try await extract(source, to: folder)
            }
        case "gz.extract":
            return try await gunzipFile(source, base: base, directory: destinationDirectory, reserved: &reserved)
        case "zip.tar":
            return try await repack(source, toExtension: "tar", base: base, directory: destinationDirectory, reserved: &reserved) { folder, dest in
                try await packDirectoryContents(folder, to: dest, format: .tar)
            }
        case "zip.tar.gz":
            return try await repack(source, toExtension: "tar.gz", base: base, directory: destinationDirectory, reserved: &reserved) { folder, dest in
                try await packDirectoryContents(folder, to: dest, format: .tarGz)
            }
        case "tar.zip":
            return try await repack(source, toExtension: "zip", base: base, directory: destinationDirectory, reserved: &reserved) { folder, dest in
                try await packZip(item: folder, to: dest, keepParent: false)
            }
        case "tar.tar.gz":
            return try await publishFile(extension: "tar.gz", base: base, directory: destinationDirectory, source: source, reserved: &reserved) { temp in
                try await gzipFile(source, to: temp)
            }
        case "tar.gz.tar":
            return try await publishFile(extension: "tar", base: base, directory: destinationDirectory, source: source, reserved: &reserved) { temp in
                try await gunzipStream(source, to: temp)
            }
        case "tar.gz.zip":
            return try await repack(source, toExtension: "zip", base: base, directory: destinationDirectory, reserved: &reserved) { folder, dest in
                try await packZip(item: folder, to: dest, keepParent: false)
            }
        default:
            throw FileWheelError(FileWheelMessages.archiveUnreadable)
        }
    }

    private enum PackedFormat {
        case tar
        case tarGz
    }

    private static func publishFile(
        extension pathExtension: String,
        base: String,
        directory: URL,
        source: URL,
        reserved: inout Set<URL>,
        write: (URL) async throws -> Void
    ) async throws -> URL {
        let finalURL = Phase3Naming.uniqueFileURL(
            directory: directory,
            base: base,
            pathExtension: pathExtension,
            source: source,
            reserved: &reserved
        )
        let temp = directory.appendingPathComponent(".filewheel-\(UUID().uuidString).partial")
        do {
            try await write(temp)
            try Task.checkCancellation()
            try OutputPublisher.publish(temp: temp, to: finalURL)
        } catch {
            OutputPublisher.removeQuietly(temp)
            OutputPublisher.removeQuietly(finalURL)
            reserved.remove(finalURL.standardizedFileURL)
            throw error
        }
        return finalURL
    }

    private static func publishExtractedFolder(
        base: String,
        directory: URL,
        reserved: inout Set<URL>,
        fill: (URL) async throws -> Void
    ) async throws -> URL {
        let finalURL = Phase3Naming.uniqueFolderURL(
            directory: directory,
            name: "\(base)-extracted",
            reserved: &reserved
        )
        let temp = directory.appendingPathComponent(".filewheel-\(UUID().uuidString)-extract")
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        do {
            try await fill(temp)
            try Task.checkCancellation()
            try OutputPublisher.publish(temp: temp, to: finalURL)
        } catch {
            OutputPublisher.removeQuietly(temp)
            OutputPublisher.removeQuietly(finalURL)
            reserved.remove(finalURL.standardizedFileURL)
            throw error
        }
        return finalURL
    }

    private static func repack(
        _ source: URL,
        toExtension pathExtension: String,
        base: String,
        directory: URL,
        reserved: inout Set<URL>,
        pack: (URL, URL) async throws -> Void
    ) async throws -> URL {
        try await publishFile(extension: pathExtension, base: base, directory: directory, source: source, reserved: &reserved) { dest in
            let scratch = directory.appendingPathComponent(".filewheel-\(UUID().uuidString)-repack")
            try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
            defer { OutputPublisher.removeQuietly(scratch) }
            try await extract(source, to: scratch)
            try await pack(scratch, dest)
        }
    }

    static func packZip(item: URL, to destination: URL, keepParent: Bool) async throws {
        do {
            try FileManager.default.zipItem(
                at: item,
                to: destination,
                shouldKeepParent: keepParent,
                compressionMethod: .deflate
            )
        } catch {
            if FileManager.default.fileExists(atPath: destination.path) {
                try? FileManager.default.removeItem(at: destination)
            }
            try await packZipWithSystemTool(item: item, to: destination, keepParent: keepParent)
        }
    }

    private static func packZipWithSystemTool(item: URL, to destination: URL, keepParent: Bool) async throws {
        try ArchiveCommands.require(ArchiveCommands.zip, missing: FileWheelMessages.archiveUnreadable)
        let arguments: [String]
        let directory: URL
        if keepParent {
            directory = item.deletingLastPathComponent()
            arguments = ["-r", "-X", destination.path, item.lastPathComponent]
        } else {
            directory = item
            arguments = ["-r", "-X", destination.path, "."]
        }
        let output = try await CapturedProcess.run(
            executable: ArchiveCommands.zip,
            arguments: arguments,
            currentDirectory: directory
        )
        try CapturedProcess.requireZero(output, fallback: FileWheelMessages.archiveUnreadable)
    }

    private static func packTar(item: URL, to destination: URL, compressed: Bool) async throws {
        try ArchiveCommands.require(ArchiveCommands.tar, missing: "tar is not available on this Mac.")
        var arguments = compressed ? ["-czf", destination.path] : ["-cf", destination.path]
        arguments += ["-C", item.deletingLastPathComponent().path, "--", item.lastPathComponent]
        let output = try await CapturedProcess.run(executable: ArchiveCommands.tar, arguments: arguments)
        try CapturedProcess.requireZero(output, fallback: FileWheelMessages.archiveUnreadable)
    }

    private static func packDirectoryContents(_ directory: URL, to destination: URL, format: PackedFormat) async throws {
        try ArchiveCommands.require(ArchiveCommands.tar, missing: "tar is not available on this Mac.")
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { !$0.hasPrefix(".") }
        if names.isEmpty {
            throw FileWheelError(FileWheelMessages.archiveUnreadable)
        }
        var arguments = format == .tarGz ? ["-czf", destination.path] : ["-cf", destination.path]
        arguments += ["-C", directory.path, "--"]
        arguments += names
        let output = try await CapturedProcess.run(executable: ArchiveCommands.tar, arguments: arguments)
        try CapturedProcess.requireZero(output, fallback: FileWheelMessages.archiveUnreadable)
    }

    private static func gzipFile(_ source: URL, to destination: URL) async throws {
        try ArchiveCommands.require(ArchiveCommands.gzip, missing: "gzip is not available on this Mac.")
        let output = try await CapturedProcess.run(
            executable: ArchiveCommands.gzip,
            arguments: ["-c", source.path],
            standardOutput: destination
        )
        try CapturedProcess.requireZero(output, fallback: FileWheelMessages.archiveUnreadable)
    }

    private static func gunzipStream(_ source: URL, to destination: URL) async throws {
        try ArchiveCommands.require(ArchiveCommands.gunzip, missing: "gunzip is not available on this Mac.")
        let output = try await CapturedProcess.run(
            executable: ArchiveCommands.gunzip,
            arguments: ["-c", source.path],
            standardOutput: destination
        )
        try CapturedProcess.requireZero(output, fallback: FileWheelMessages.archiveUnreadable)
    }

    private static func gunzipFile(
        _ source: URL,
        base: String,
        directory: URL,
        reserved: inout Set<URL>
    ) async throws -> URL {
        let headerName = GzipName.originalFilename(in: gzipHeaderSample(source))
        let outputName: String
        let outputExtension: String
        if let headerName {
            let ns = headerName as NSString
            outputExtension = ns.pathExtension
            outputName = ns.deletingPathExtension
        } else {
            outputExtension = ""
            outputName = base
        }
        let finalURL = Phase3Naming.uniqueFileURL(
            directory: directory,
            base: outputName.isEmpty ? base : outputName,
            pathExtension: outputExtension,
            source: source,
            reserved: &reserved
        )
        let temp = directory.appendingPathComponent(".filewheel-\(UUID().uuidString).partial")
        do {
            try await gunzipStream(source, to: temp)
            try Task.checkCancellation()
            try OutputPublisher.publish(temp: temp, to: finalURL)
        } catch {
            OutputPublisher.removeQuietly(temp)
            OutputPublisher.removeQuietly(finalURL)
            reserved.remove(finalURL.standardizedFileURL)
            throw error
        }
        return finalURL
    }

    private static func gzipHeaderSample(_ url: URL) -> Data {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return Data() }
        defer { try? handle.close() }
        return handle.readData(ofLength: 512)
    }

    static func extract(_ source: URL, to directory: URL) async throws {
        let format = DroppedFile.formatKey(for: source)
        switch format {
        case "zip":
            try extractZip(source, to: directory)
        case "tar", "tar.gz":
            try await extractTar(source, to: directory)
        case "gz":
            let base = Phase3Naming.sourceBaseName(for: source)
            let file = directory.appendingPathComponent(base)
            try await gunzipStream(source, to: file)
        case "rar":
            try await extractRar(source, to: directory)
        default:
            throw FileWheelError(FileWheelMessages.archiveUnreadable)
        }
    }

    private static func extractZip(_ source: URL, to directory: URL) throws {
        let archive: Archive
        do {
            archive = try Archive(url: source, accessMode: .read)
        } catch {
            throw FileWheelError(FileWheelMessages.archiveUnreadable)
        }
        for entry in archive {
            if entry.type == .symlink || !ArchivePathSafety.isSafe(entry.path) {
                throw FileWheelError(FileWheelMessages.unsafeArchivePath)
            }
        }
        do {
            try FileManager.default.unzipItem(at: source, to: directory, allowUncontainedSymlinks: false)
        } catch let error as FileWheelError {
            throw error
        } catch {
            throw FileWheelError(FileWheelMessages.archiveUnreadable)
        }
    }

    private static func extractTar(_ source: URL, to directory: URL) async throws {
        try ArchiveCommands.require(ArchiveCommands.tar, missing: "tar is not available on this Mac.")
        let listing = try await CapturedProcess.run(
            executable: ArchiveCommands.tar,
            arguments: ["-tf", source.path]
        )
        try CapturedProcess.requireZero(listing, fallback: FileWheelMessages.archiveUnreadable)
        let text = String(data: listing.stdout, encoding: .utf8) ?? ""
        for line in text.split(whereSeparator: \.isNewline) {
            let name = String(line)
            if name.contains(" -> ") || !ArchivePathSafety.isSafe(name) {
                throw FileWheelError(FileWheelMessages.unsafeArchivePath)
            }
        }
        let output = try await CapturedProcess.run(
            executable: ArchiveCommands.tar,
            arguments: ["-xf", source.path, "-C", directory.path]
        )
        try CapturedProcess.requireZero(output, fallback: FileWheelMessages.archiveUnreadable)
    }

    private static func extractRar(_ source: URL, to directory: URL) async throws {
        guard let unar = SystemToolLocator.unar() else {
            throw FileWheelError(FileWheelMessages.rarBinaryMissing)
        }
        let output = try await CapturedProcess.run(
            executable: unar,
            arguments: ["-q", "-output-directory", directory.path, source.path]
        )
        try CapturedProcess.requireZero(output, fallback: FileWheelMessages.archiveUnreadable)
    }
}
