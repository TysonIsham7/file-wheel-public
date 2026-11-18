import AppKit
import AVFoundation
import Foundation

struct MacVoice: Identifiable, Equatable {
    var identifier: String
    var name: String
    var language: String
    var id: String { identifier }
}

enum MacVoiceInventory {
    /// Voices already installed, including a Personal Voice the owner has created.
    /// Premium voices appear only after they have been downloaded.
    static func installed() -> [MacVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .map { MacVoice(identifier: $0.identifier, name: $0.name, language: $0.language) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func resolve(_ identifier: String?) throws -> (name: String, wordsPerMinute: Float) {
        let voices = AVSpeechSynthesisVoice.speechVoices()
        let voice: AVSpeechSynthesisVoice?
        if let identifier, !identifier.isEmpty {
            voice = voices.first { $0.identifier == identifier }
            if voice == nil {
                throw FileWheelError(FileWheelMessages.missingMacVoice)
            }
        } else {
            let code = AVSpeechSynthesisVoice.currentLanguageCode()
            voice = AVSpeechSynthesisVoice(language: code) ?? voices.first
        }
        guard let voice else {
            throw FileWheelError(FileWheelMessages.missingMacVoice)
        }
        let voiceName = NSSpeechSynthesizer.VoiceName(rawValue: voice.identifier)
        let baseRate = NSSpeechSynthesizer(voice: voiceName)?.rate ?? 175
        return (voice.name, baseRate > 1 ? baseRate : 175)
    }
}

@MainActor
enum MacOSSpeechEngine {
    static func synthesize(
        text: String,
        voiceIdentifier: String?,
        speed: Double,
        baseName: String,
        destinationDirectory: URL,
        source: URL,
        reserved: inout Set<URL>
    ) async throws -> URL {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            throw FileWheelError(FileWheelMessages.noTextToRead)
        }
        let voice = try MacVoiceInventory.resolve(voiceIdentifier)
        let scaled = Int((voice.wordsPerMinute * Float(min(1.5, max(0.7, speed)))).rounded())
        let rate = min(600, max(40, scaled))
        let directory = destinationDirectory
        let textURL = directory.appendingPathComponent(".filewheel-\(UUID().uuidString).txt")
        let m4aURL = directory.appendingPathComponent(".filewheel-\(UUID().uuidString).m4a")
        let tempMP3 = directory.appendingPathComponent(".filewheel-\(UUID().uuidString).mp3")
        let finalURL = Phase3Naming.uniqueFileURL(
            directory: directory,
            base: baseName,
            pathExtension: "mp3",
            source: source,
            reserved: &reserved
        )
        defer {
            OutputPublisher.removeQuietly(textURL)
            OutputPublisher.removeQuietly(m4aURL)
            OutputPublisher.removeQuietly(tempMP3)
        }
        do {
            try text.write(to: textURL, atomically: true, encoding: .utf8)
            let say = URL(fileURLWithPath: "/usr/bin/say")
            guard FileManager.default.isExecutableFile(atPath: say.path) else {
                throw FileWheelError(FileWheelMessages.missingMacVoice)
            }
            let spoken = try await CapturedProcess.run(
                executable: say,
                arguments: ["-v", voice.name, "-r", String(rate), "-o", m4aURL.path, "-f", textURL.path]
            )
            try CapturedProcess.requireZero(spoken, fallback: FileWheelMessages.missingMacVoice)
            let m4aSize = (try? FileManager.default.attributesOfItem(atPath: m4aURL.path)[.size] as? NSNumber)?.int64Value ?? 0
            if m4aSize == 0 {
                throw FileWheelError(FileWheelMessages.emptyMacSpeech)
            }
            try await FFmpegInvoker.transcodeToMP3(input: m4aURL, output: tempMP3)
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
