import Foundation

enum FFmpegInvoker {
    static func concatenateMP3s(_ chunks: [URL], to output: URL) async throws {
        guard let ffmpeg = SystemToolLocator.ffmpeg() else {
            throw FileWheelError(FileWheelMessages.ffmpegMissing)
        }
        let listURL = output.deletingLastPathComponent().appendingPathComponent(".filewheel-\(UUID().uuidString).concat.txt")
        let list = chunks.map { url in
            let escaped = url.path.replacingOccurrences(of: "'", with: "'\\''")
            return "file '\(escaped)'"
        }.joined(separator: "\n")
        try list.write(to: listURL, atomically: true, encoding: .utf8)
        defer { OutputPublisher.removeQuietly(listURL) }

        let copied = try await CapturedProcess.run(
            executable: ffmpeg,
            arguments: ["-y", "-f", "concat", "-safe", "0", "-i", listURL.path, "-c", "copy", output.path]
        )
        if copied.status == 0, fileHasBytes(output) { return }

        let encoded = try await CapturedProcess.run(
            executable: ffmpeg,
            arguments: [
                "-y", "-f", "concat", "-safe", "0", "-i", listURL.path,
                "-ar", "44100", "-c:a", "libmp3lame", "-b:a", "192k", output.path,
            ]
        )
        try CapturedProcess.requireZero(encoded, fallback: copied.lastUsefulStderrLine ?? FileWheelMessages.archiveUnreadable)
        if !fileHasBytes(output) {
            throw FileWheelError(encoded.lastUsefulStderrLine ?? "ffmpeg produced no audio.")
        }
    }

    static func transcodeToMP3(input: URL, output: URL) async throws {
        guard let ffmpeg = SystemToolLocator.ffmpeg() else {
            throw FileWheelError(FileWheelMessages.ffmpegMissing)
        }
        let result = try await CapturedProcess.run(
            executable: ffmpeg,
            arguments: ["-y", "-i", input.path, "-vn", "-ar", "44100", "-c:a", "libmp3lame", "-b:a", "192k", output.path]
        )
        try CapturedProcess.requireZero(result, fallback: "ffmpeg could not write the MP3.")
        if !fileHasBytes(output) {
            throw FileWheelError(FileWheelMessages.emptyMacSpeech)
        }
    }

    private static func fileHasBytes(_ url: URL) -> Bool {
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
        return size > 0
    }
}
