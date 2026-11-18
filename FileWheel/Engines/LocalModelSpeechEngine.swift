import Foundation

/// Same contract as the other Read aloud engines: one MP3 beside the source, nothing uploaded.
/// The owner points Settings at an installed model executable. There is no Ara voice and no network call.
@MainActor
enum LocalModelSpeechEngine {
    static func isInstalled(path: String) -> Bool {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return FileManager.default.isExecutableFile(atPath: trimmed)
    }

    static func synthesize(
        text: String,
        modelPath: String,
        speed: Double,
        baseName: String,
        destinationDirectory: URL,
        source: URL,
        reserved: inout Set<URL>
    ) async throws -> URL {
        guard isInstalled(path: modelPath) else {
            throw FileWheelError(FileWheelMessages.noLocalModel)
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            throw FileWheelError(FileWheelMessages.noTextToRead)
        }
        let textURL = destinationDirectory.appendingPathComponent(".filewheel-\(UUID().uuidString).txt")
        let tempMP3 = destinationDirectory.appendingPathComponent(".filewheel-\(UUID().uuidString).mp3")
        let finalURL = Phase3Naming.uniqueFileURL(
            directory: destinationDirectory,
            base: baseName,
            pathExtension: "mp3",
            source: source,
            reserved: &reserved
        )
        defer {
            OutputPublisher.removeQuietly(textURL)
            OutputPublisher.removeQuietly(tempMP3)
        }
        do {
            try text.write(to: textURL, atomically: true, encoding: .utf8)
            let speedText = String(format: "%.2f", min(1.5, max(0.7, speed)))
            let output = try await CapturedProcess.run(
                executable: URL(fileURLWithPath: modelPath),
                arguments: ["--input", textURL.path, "--output", tempMP3.path, "--speed", speedText]
            )
            try CapturedProcess.requireZero(output, fallback: FileWheelMessages.emptyLocalSpeech)
            let size = (try? FileManager.default.attributesOfItem(atPath: tempMP3.path)[.size] as? NSNumber)?.int64Value ?? 0
            if size == 0 {
                throw FileWheelError(FileWheelMessages.emptyLocalSpeech)
            }
            try Task.checkCancellation()
            try OutputPublisher.publish(temp: tempMP3, to: finalURL)
        } catch {
            OutputPublisher.removeQuietly(finalURL)
            reserved.remove(finalURL.standardizedFileURL)
            throw error
        }
        return finalURL
    }
}
