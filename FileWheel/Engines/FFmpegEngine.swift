import Foundation

public struct FFmpegEngine: Sendable {
    public var executable: URL?

    public init(executable: URL?) {
        self.executable = executable
    }

    public func convert(_ job: EngineJob) async throws {
        guard let executable else {
            throw ConversionError.ffmpegMissing
        }
        if job.cancel.isCancelled {
            throw ConversionError.cancelled
        }
        let task = FFmpegCommand.task(entry: job.entry, options: job.options)
        if case .extractMP3 = task {
            let streams = try await probe(url: job.source, executable: executable, cancel: job.cancel)
            if !streams.hasAudio {
                throw ConversionError.noAudio
            }
        }
        let arguments = FFmpegCommand.arguments(
            input: job.source,
            output: job.tempOutput,
            task: task,
            progress: true
        )
        let result = try await ProcessRunner.run(
            executable: executable,
            arguments: arguments,
            cancel: job.cancel
        )
        if job.cancel.isCancelled {
            try? FileManager.default.removeItem(at: job.tempOutput)
            throw ConversionError.cancelled
        }
        guard result.status == 0 else {
            try? FileManager.default.removeItem(at: job.tempOutput)
            throw ConversionError.failed(FFmpegDiagnostics.lastUsefulLine(result.stderr))
        }
    }

    public func probe(url: URL) async throws -> MediaStreams {
        guard let executable else {
            throw ConversionError.ffmpegMissing
        }
        return try await probe(url: url, executable: executable, cancel: nil)
    }

    public func capabilities() async -> FFmpegCapabilities {
        guard let executable else {
            return .missing
        }
        async let version = invoke(executable, ["-hide_banner", "-version"])
        async let encoders = invoke(executable, ["-hide_banner", "-encoders"])
        async let muxers = invoke(executable, ["-hide_banner", "-muxers"])
        let versionOut = await version
        let encodersOut = await encoders
        let muxersOut = await muxers
        guard let versionOut, let encodersOut, let muxersOut else {
            return .missing
        }
        return FFmpegCapabilities.parse(
            versionOutput: versionOut.stdout.isEmpty ? versionOut.stderr : versionOut.stdout,
            encodersOutput: encodersOut.stdout,
            muxersOutput: muxersOut.stdout
        )
    }

    private func probe(url: URL, executable: URL, cancel: ConversionCancel?) async throws -> MediaStreams {
        let result = try await ProcessRunner.run(
            executable: executable,
            arguments: ["-hide_banner", "-nostdin", "-i", url.path],
            cancel: cancel
        )
        if cancel?.isCancelled == true {
            throw ConversionError.cancelled
        }
        let stderr = result.stderr
        if stderr.contains("No such file or directory") {
            throw ConversionError.failed(FFmpegDiagnostics.lastUsefulLine(stderr))
        }
        return FFmpegDiagnostics.streams(fromStderr: stderr)
    }

    private func invoke(_ executable: URL, _ arguments: [String]) async -> ProcessOutput? {
        try? await ProcessRunner.run(executable: executable, arguments: arguments, cancel: nil)
    }
}

public struct FFmpegSession: Sendable {
    public let url: URL?
    public let capabilities: FFmpegCapabilities
    public let report: CapabilityReport

    public init(
        url: URL?,
        capabilities: FFmpegCapabilities,
        report: CapabilityReport
    ) {
        self.url = url
        self.capabilities = capabilities
        self.report = report
    }

    public static func launch(imageIO: ImageIOCapabilities = .current()) async -> FFmpegSession {
        let url = FFmpegLocator.resolve()
        let engine = FFmpegEngine(executable: url)
        let capabilities = await engine.capabilities()
        let report = CapabilityReportBuilder.make(
            capabilities: capabilities,
            imageIO: imageIO
        )
        return FFmpegSession(
            url: url,
            capabilities: capabilities,
            report: report
        )
    }
}
