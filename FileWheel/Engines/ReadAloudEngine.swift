import Foundation

struct ReadAloudFile {
    var url: URL
    var text: String
    var chunks: [String]
}

struct ReadAloudPreparation {
    var files: [ReadAloudFile]
    var failures: [(url: URL, message: String)]
    var characterCount: Int
    var chunkCount: Int
}

protocol ConversionProgress: AnyObject {
    func update(message: String, fraction: Double?)
}

enum SpokenText {
    static func extract(from url: URL) throws -> String {
        let format = DroppedFile.formatKey(for: url)
        switch format {
        case "txt", "md":
            return SpeakTextCleanup.cleanMarkdown(try DocumentTextExtractor.plainText(at: url))
        case "pdf":
            let document = try PDFEngine.open(url: url)
            let pages = PDFEngine.pageStrings(document)
            if PageText.allPagesLackExtractableText(pages) {
                throw FileWheelError(FileWheelMessages.pdfNoExtractableText)
            }
            return PageText.join(pages)
        case "docx":
            return try DocumentTextExtractor.docxParagraphs(at: url)
                .joined(separator: "\n\n")
        case "srt":
            let cues = try SubtitleCodec.cues(from: try DocumentTextExtractor.plainText(at: url), format: .srt)
            return SubtitleCodec.plainText(cues)
        case "vtt":
            let cues = try SubtitleCodec.cues(from: try DocumentTextExtractor.plainText(at: url), format: .vtt)
            return SubtitleCodec.plainText(cues)
        default:
            throw FileWheelError(FileWheelMessages.noTextToRead)
        }
    }
}

@MainActor
enum SpeechSynthesis {
    static func prepare(_ urls: [URL], engine: ReadAloudEngineKind) -> ReadAloudPreparation {
        var files: [ReadAloudFile] = []
        var failures: [(url: URL, message: String)] = []
        for url in urls {
            do {
                let text = try SpokenText.extract(from: url)
                let chunks = TextChunker.chunks(text)
                if chunks.isEmpty || TextChunker.characterCount(text.trimmingCharacters(in: .whitespacesAndNewlines)) == 0 {
                    throw FileWheelError(FileWheelMessages.noTextToRead)
                }
                files.append(ReadAloudFile(url: url, text: text, chunks: chunks))
            } catch {
                failures.append((url, (error as? FileWheelError)?.message ?? error.localizedDescription))
            }
        }
        let characters = files.reduce(0) { $0 + TextChunker.characterCount($1.text) }
        let chunks = engine == .xai ? files.reduce(0) { $0 + $1.chunks.count } : files.count
        return ReadAloudPreparation(files: files, failures: failures, characterCount: characters, chunkCount: chunks)
    }

    static func render(
        _ file: ReadAloudFile,
        configuration: ReadAloudConfiguration,
        destinationDirectory: URL,
        client: XAITTSClient,
        progress: ConversionProgress?,
        reserved: inout Set<URL>
    ) async throws -> URL {
        let base = Phase3Naming.sourceBaseName(for: file.url)
        switch configuration.engine {
        case .xai:
            return try await renderXAI(
                file,
                configuration: configuration,
                base: base,
                destinationDirectory: destinationDirectory,
                client: client,
                progress: progress,
                reserved: &reserved
            )
        case .macos:
            progress?.update(message: "Speaking", fraction: 0.2)
            return try await MacOSSpeechEngine.synthesize(
                text: file.text,
                voiceIdentifier: configuration.macOSVoiceIdentifier,
                speed: configuration.clampedSpeed,
                baseName: base,
                destinationDirectory: destinationDirectory,
                source: file.url,
                reserved: &reserved
            )
        case .localModel:
            progress?.update(message: "Speaking", fraction: 0.2)
            return try await LocalModelSpeechEngine.synthesize(
                text: file.text,
                modelPath: configuration.localModelPath,
                speed: configuration.clampedSpeed,
                baseName: base,
                destinationDirectory: destinationDirectory,
                source: file.url,
                reserved: &reserved
            )
        }
    }

    private static func renderXAI(
        _ file: ReadAloudFile,
        configuration: ReadAloudConfiguration,
        base: String,
        destinationDirectory: URL,
        client: XAITTSClient,
        progress: ConversionProgress?,
        reserved: inout Set<URL>
    ) async throws -> URL {
        let parts = file.chunks
        if parts.isEmpty {
            throw FileWheelError(FileWheelMessages.noTextToRead)
        }
        var chunkURLs: [URL] = []
        defer { chunkURLs.forEach(OutputPublisher.removeQuietly) }
        for (index, part) in parts.enumerated() {
            try Task.checkCancellation()
            let partNumber = index + 1
            progress?.update(
                message: FileWheelMessages.readingPart(partNumber, of: parts.count),
                fraction: Double(index) / Double(parts.count)
            )
            let audio = try await synthesizeChunk(part, configuration: configuration, client: client)
            let chunkURL = destinationDirectory.appendingPathComponent(".filewheel-\(UUID().uuidString)-part-\(partNumber).mp3")
            try audio.write(to: chunkURL, options: .atomic)
            chunkURLs.append(chunkURL)
        }
        let finalURL = Phase3Naming.uniqueFileURL(
            directory: destinationDirectory,
            base: base,
            pathExtension: "mp3",
            source: file.url,
            reserved: &reserved
        )
        let temp = destinationDirectory.appendingPathComponent(".filewheel-\(UUID().uuidString).mp3")
        do {
            if chunkURLs.count == 1 {
                try FileManager.default.copyItem(at: chunkURLs[0], to: temp)
            } else {
                try await FFmpegInvoker.concatenateMP3s(chunkURLs, to: temp)
            }
            try Task.checkCancellation()
            try OutputPublisher.publish(temp: temp, to: finalURL)
        } catch {
            OutputPublisher.removeQuietly(temp)
            OutputPublisher.removeQuietly(finalURL)
            throw error
        }
        return finalURL
    }

    private static func synthesizeChunk(
        _ text: String,
        configuration: ReadAloudConfiguration,
        client: XAITTSClient
    ) async throws -> Data {
        let body = TTSRequestBody.make(
            text: text,
            voiceID: configuration.voiceID,
            language: configuration.language,
            speed: configuration.clampedSpeed
        )
        do {
            return try await client.synthesize(body)
        } catch let error as FileWheelError where error.isUnauthorized {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try Task.checkCancellation()
            return try await client.synthesize(body)
        }
    }
}
