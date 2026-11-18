import Foundation

public struct EngineRouter: Sendable {
    public var ffmpeg: FFmpegEngine
    public var imageIO: ImageIOCapabilities

    public init(ffmpegURL: URL?, imageIO: ImageIOCapabilities) {
        self.ffmpeg = FFmpegEngine(executable: ffmpegURL)
        self.imageIO = imageIO
    }

    public init(session: FFmpegSession, imageIO: ImageIOCapabilities) {
        self.ffmpeg = FFmpegEngine(executable: session.url)
        self.imageIO = imageIO
    }

    public func convert(_ job: EngineJob) async throws {
        switch job.entry.engine {
        case .avFoundation:
            do {
                try await AVFoundationEngine().convert(job)
            } catch is EngineFallback {
                try await ffmpeg.convert(job)
            }
        case .ffmpeg:
            try await ffmpeg.convert(job)
        case .imageIOThenFFmpeg, .svgRasterize, .svgWrap:
            try await RemainingImageEngine(ffmpeg: ffmpeg, imageIO: imageIO).convert(job)
        case .document, .archive, .readAloud, .tool:
            throw ConversionError.failed("\(job.entry.label) is run by the document, archive, or tool path")
        }
    }
}
