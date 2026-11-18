import Foundation

public struct FileFailure: Equatable, Sendable {
    public let source: URL
    public let reason: String

    public init(source: URL, reason: String) {
        self.source = source
        self.reason = reason
    }
}

public struct BatchResult: Equatable, Sendable {
    public let outputs: [URL]
    public let failures: [FileFailure]
    public let cancelled: Bool

    public init(outputs: [URL], failures: [FileFailure], cancelled: Bool) {
        self.outputs = outputs
        self.failures = failures
        self.cancelled = cancelled
    }
}

public struct ConversionRequest: Sendable {
    public let inputs: [URL]
    public let entry: CatalogEntry
    public let destinationDirectory: URL?
    public var options: ConversionOptions

    public init(
        inputs: [URL],
        entry: CatalogEntry,
        destinationDirectory: URL? = nil,
        options: ConversionOptions = .specDefaults
    ) {
        self.inputs = inputs
        self.entry = entry
        self.destinationDirectory = destinationDirectory
        self.options = options
    }
}

/// One heavy conversion at a time. A failure is recorded and the rest of the batch continues.
/// Cancel deletes the in-flight temp file and leaves no new destination for that file.
public struct ConversionJobRunner: Sendable {
    public var router: EngineRouter

    public init(router: EngineRouter) {
        self.router = router
    }

    public func run(
        _ request: ConversionRequest,
        cancel: ConversionCancel = ConversionCancel()
    ) async -> BatchResult {
        var outputs: [URL] = []
        var failures: [FileFailure] = []
        for input in request.inputs {
            if cancel.isCancelled {
                return BatchResult(outputs: outputs, failures: failures, cancelled: true)
            }
            let outcome = await convertOne(input, request: request, cancel: cancel)
            switch outcome {
            case .output(let url):
                outputs.append(url)
            case .failure(let failure):
                failures.append(failure)
            case .cancelled:
                return BatchResult(outputs: outputs, failures: failures, cancelled: true)
            }
        }
        return BatchResult(outputs: outputs, failures: failures, cancelled: false)
    }

    private func convertOne(
        _ input: URL,
        request: ConversionRequest,
        cancel: ConversionCancel
    ) async -> OneOutcome {
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: input.path, isDirectory: &isDirectory), isDirectory.boolValue {
            return .failure(FileFailure(source: input, reason: "Folders are archive inputs only"))
        }
        let format = KnownFormats.canonical(extension: input.pathExtension)
        guard format?.id == request.entry.source else {
            return .failure(FileFailure(source: input, reason: ConversionError.sameKindRequired.errorDescription ?? "Same kind of file required"))
        }

        let directory = request.destinationDirectory ?? input.deletingLastPathComponent()
        let final = OutputNaming.destinationURL(
            source: input,
            targetExtension: request.entry.target,
            directory: directory
        )
        let temp = directory.appendingPathComponent(".\(UUID().uuidString).filewheel.\(request.entry.target)")
        let job = EngineJob(
            source: input,
            tempOutput: temp,
            entry: request.entry,
            options: request.options,
            cancel: cancel
        )
        do {
            try await router.convert(job)
            if cancel.isCancelled {
                try? FileManager.default.removeItem(at: temp)
                return .cancelled
            }
            try JobPublish.publish(temp: temp, to: final)
            return .output(final)
        } catch {
            try? FileManager.default.removeItem(at: temp)
            if cancel.isCancelled || (error as? ConversionError) == .cancelled {
                return .cancelled
            }
            let reason = (error as? LocalizedError)?.errorDescription ?? "Conversion failed"
            return .failure(FileFailure(source: input, reason: reason))
        }
    }
}

private enum OneOutcome {
    case output(URL)
    case failure(FileFailure)
    case cancelled
}

public enum SourceProbe {
    public static func inspect(url: URL, ffmpegURL: URL?) async -> SourceFile {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return SourceFile(fileExtension: url.pathExtension, isDirectory: false, hasAudio: nil)
        }
        if isDirectory.boolValue {
            return SourceFile(fileExtension: url.pathExtension, isDirectory: true, hasAudio: nil)
        }
        let format = KnownFormats.canonical(extension: url.pathExtension)
        guard format?.kind == .audio || format?.kind == .video else {
            return SourceFile(fileExtension: url.pathExtension, isDirectory: false, hasAudio: nil)
        }
        if let streams = try? await AVFoundationEngine().probeStreams(url) {
            return SourceFile(fileExtension: url.pathExtension, isDirectory: false, hasAudio: streams.hasAudio)
        }
        if let ffmpegURL, let streams = try? await FFmpegEngine(executable: ffmpegURL).probe(url: url) {
            return SourceFile(fileExtension: url.pathExtension, isDirectory: false, hasAudio: streams.hasAudio)
        }
        return SourceFile(fileExtension: url.pathExtension, isDirectory: false, hasAudio: nil)
    }
}

public enum FileWheelJobs {
    public static func offer(
        files: [SourceFile],
        capabilities: FFmpegCapabilities,
        imageIO: ImageIOCapabilities
    ) -> WheelOffer {
        ConversionCatalog.offer(files: files, capabilities: capabilities, imageIO: imageIO)
    }

    public static func launchSession() async -> FFmpegSession {
        await FFmpegSession.launch()
    }
}
