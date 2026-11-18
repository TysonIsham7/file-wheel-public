@preconcurrency import AVFoundation
import AudioToolbox
import CoreMedia
import Foundation

public struct AVFoundationEngine: Sendable {
    public init() {}

    public func convert(_ job: EngineJob) async throws {
        if job.cancel.isCancelled {
            throw ConversionError.cancelled
        }
        switch (job.entry.kind, job.entry.target) {
        case (.video, "mp4"):
            try await exportMovie(job, fileType: .mp4)
        case (.video, "mov"):
            try await exportMovie(job, fileType: .mov)
        case (_, "mp3"):
            try await writeEncodedAudio(job, fileType: .mp3, formatID: kAudioFormatMPEGLayer3, bitRate: 192_000)
        case (_, "m4a"):
            try await exportM4A(job)
        case (_, "wav"):
            try await writePCM(job, fileType: .wav, bigEndian: false)
        case (_, "aiff"):
            try await writePCM(job, fileType: .aiff, bigEndian: true)
        default:
            throw EngineFallback("AVFoundation does not write \(job.entry.target)")
        }
    }

    public func probeStreams(_ url: URL) async throws -> MediaStreams {
        let asset = AVURLAsset(url: url)
        let playable = try await asset.load(.isPlayable)
        if !playable {
            throw EngineFallback("AVFoundation cannot read this file")
        }
        let audio = try await asset.loadTracks(withMediaType: .audio)
        let video = try await asset.loadTracks(withMediaType: .video)
        let duration = try await asset.load(.duration)
        let seconds = duration.seconds
        return MediaStreams(
            hasAudio: !audio.isEmpty,
            hasVideo: !video.isEmpty,
            durationSeconds: seconds.isFinite && seconds > 0 ? seconds : nil
        )
    }

    private func exportMovie(_ job: EngineJob, fileType: AVFileType) async throws {
        let asset = AVURLAsset(url: job.source)
        let video = try await asset.loadTracks(withMediaType: .video)
        if video.isEmpty {
            throw EngineFallback("AVFoundation found no video track")
        }
        let preset = try await videoPreset(for: asset, fileType: fileType)
        try await export(asset, preset: preset, fileType: fileType, to: job.tempOutput, cancel: job.cancel)
    }

    private func exportM4A(_ job: EngineJob) async throws {
        let asset = AVURLAsset(url: job.source)
        let audio = try await asset.loadTracks(withMediaType: .audio)
        if audio.isEmpty {
            throw ConversionError.noAudio
        }
        let compatible = await AVAssetExportSession.compatibility(
            ofExportPreset: AVAssetExportPresetAppleM4A,
            with: asset,
            outputFileType: .m4a
        )
        guard compatible else {
            throw EngineFallback("AVFoundation cannot write M4A for this file")
        }
        try await export(asset, preset: AVAssetExportPresetAppleM4A, fileType: .m4a, to: job.tempOutput, cancel: job.cancel)
    }

    private func videoPreset(for asset: AVURLAsset, fileType: AVFileType) async throws -> String {
        if await AVAssetExportSession.compatibility(
            ofExportPreset: AVAssetExportPreset1920x1080,
            with: asset,
            outputFileType: fileType
        ) {
            return AVAssetExportPreset1920x1080
        }
        if await AVAssetExportSession.compatibility(
            ofExportPreset: AVAssetExportPresetHighestQuality,
            with: asset,
            outputFileType: fileType
        ) {
            return AVAssetExportPresetHighestQuality
        }
        throw EngineFallback("AVFoundation has no H.264 preset for this video")
    }

    private func export(
        _ asset: AVURLAsset,
        preset: String,
        fileType: AVFileType,
        to dest: URL,
        cancel: ConversionCancel
    ) async throws {
        guard let session = AVAssetExportSession(asset: asset, presetName: preset) else {
            throw EngineFallback("AVFoundation could not open this file")
        }
        guard session.supportedFileTypes.contains(fileType) else {
            throw EngineFallback("AVFoundation cannot write \(fileType.rawValue)")
        }
        session.outputURL = dest
        session.outputFileType = fileType
        session.shouldOptimizeForNetworkUse = fileType == .mp4 || fileType == .mov
        let box = ExportBox(session)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let gate = ResumeGate(continuation)
            cancel.onCancel {
                box.session.cancelExport()
                gate.resume(throwing: ConversionError.cancelled)
            }
            box.session.exportAsynchronously {
                switch box.session.status {
                case .completed:
                    gate.resume(returning: ())
                case .cancelled:
                    gate.resume(throwing: ConversionError.cancelled)
                default:
                    let reason = box.session.error?.localizedDescription ?? "AVFoundation export failed"
                    gate.resume(throwing: EngineFallback(reason))
                }
            }
        }
    }

    private func writePCM(_ job: EngineJob, fileType: AVFileType, bigEndian: Bool) async throws {
        let layout = try await audioLayout(job.source)
        let settings = pcmSettings(sampleRate: layout.sampleRate, channels: layout.channels, bigEndian: bigEndian)
        try await transcode(job, fileType: fileType, readerSettings: settings, writerSettings: settings)
    }

    private func writeEncodedAudio(
        _ job: EngineJob,
        fileType: AVFileType,
        formatID: AudioFormatID,
        bitRate: Int
    ) async throws {
        let layout = try await audioLayout(job.source)
        let readerSettings = pcmSettings(sampleRate: layout.sampleRate, channels: layout.channels, bigEndian: false)
        let writerSettings: [String: Any] = [
            AVFormatIDKey: formatID,
            AVSampleRateKey: layout.sampleRate,
            AVNumberOfChannelsKey: layout.channels,
            AVEncoderBitRateKey: bitRate,
        ]
        try await transcode(job, fileType: fileType, readerSettings: readerSettings, writerSettings: writerSettings)
    }

    private func audioLayout(_ url: URL) async throws -> (sampleRate: Double, channels: Int) {
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard let track = tracks.first else {
            throw ConversionError.noAudio
        }
        let descriptions = try await track.load(.formatDescriptions)
        guard let description = descriptions.first,
              let basic = CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee else {
            throw EngineFallback("AVFoundation could not read the audio format")
        }
        let sampleRate = basic.mSampleRate > 0 ? basic.mSampleRate : 44_100
        let channels = max(1, Int(basic.mChannelsPerFrame))
        return (sampleRate, channels)
    }

    private func pcmSettings(sampleRate: Double, channels: Int, bigEndian: Bool) -> [String: Any] {
        [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channels,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: bigEndian,
            AVLinearPCMIsNonInterleaved: false,
        ]
    }

    private func transcode(
        _ job: EngineJob,
        fileType: AVFileType,
        readerSettings: [String: Any],
        writerSettings: [String: Any]
    ) async throws {
        let asset = AVURLAsset(url: job.source)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard let track = tracks.first else {
            throw ConversionError.noAudio
        }
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: readerSettings)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else {
            throw EngineFallback("AVFoundation could not read this audio")
        }
        reader.add(output)

        let writer: AVAssetWriter
        do {
            writer = try AVAssetWriter(outputURL: job.tempOutput, fileType: fileType)
        } catch {
            throw EngineFallback("AVFoundation cannot write \(fileType.rawValue)")
        }
        guard writer.canApply(outputSettings: writerSettings, forMediaType: .audio) else {
            throw EngineFallback("AVFoundation cannot encode \(job.entry.target)")
        }
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: writerSettings)
        input.expectsMediaDataInRealTime = false
        guard writer.canAdd(input) else {
            throw EngineFallback("AVFoundation cannot encode \(job.entry.target)")
        }
        writer.add(input)
        try await pump(reader: reader, output: output, writer: writer, input: input, cancel: job.cancel)
    }

    private func pump(
        reader: AVAssetReader,
        output: AVAssetReaderOutput,
        writer: AVAssetWriter,
        input: AVAssetWriterInput,
        cancel: ConversionCancel
    ) async throws {
        guard reader.startReading() else {
            throw EngineFallback(reader.error?.localizedDescription ?? "AVFoundation could not read this file")
        }
        guard writer.startWriting() else {
            throw EngineFallback(writer.error?.localizedDescription ?? "AVFoundation could not start writing")
        }
        writer.startSession(atSourceTime: .zero)

        let queue = DispatchQueue(label: "filewheel.avfoundation")
        let box = TranscodeBox(reader: reader, output: output, writer: writer, input: input)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let gate = ResumeGate(continuation)
            cancel.onCancel {
                box.stop()
                gate.resume(throwing: ConversionError.cancelled)
            }
            box.input.requestMediaDataWhenReady(on: queue) {
                while box.input.isReadyForMoreMediaData {
                    if cancel.isCancelled {
                        box.stop()
                        gate.resume(throwing: ConversionError.cancelled)
                        return
                    }
                    if let sample = box.output.copyNextSampleBuffer() {
                        if !box.input.append(sample) {
                            box.reader.cancelReading()
                            box.input.markAsFinished()
                            gate.resume(throwing: EngineFallback(box.writer.error?.localizedDescription ?? "AVFoundation write failed"))
                            return
                        }
                    } else if box.reader.status == .failed {
                        box.input.markAsFinished()
                        gate.resume(throwing: EngineFallback(box.reader.error?.localizedDescription ?? "AVFoundation read failed"))
                        return
                    } else {
                        box.input.markAsFinished()
                        box.writer.finishWriting {
                            if box.writer.status == .completed {
                                gate.resume(returning: ())
                            } else if box.writer.status == .cancelled || cancel.isCancelled {
                                gate.resume(throwing: ConversionError.cancelled)
                            } else {
                                gate.resume(throwing: EngineFallback(box.writer.error?.localizedDescription ?? "AVFoundation write failed"))
                            }
                        }
                        return
                    }
                }
            }
        }
    }
}

/// AVFoundation objects are not Sendable. These boxes keep them inside one unchecked reference the callbacks can share.
private final class ExportBox: @unchecked Sendable {
    let session: AVAssetExportSession
    init(_ session: AVAssetExportSession) { self.session = session }
}

private final class TranscodeBox: @unchecked Sendable {
    let reader: AVAssetReader
    let output: AVAssetReaderOutput
    let writer: AVAssetWriter
    let input: AVAssetWriterInput

    init(reader: AVAssetReader, output: AVAssetReaderOutput, writer: AVAssetWriter, input: AVAssetWriterInput) {
        self.reader = reader
        self.output = output
        self.writer = writer
        self.input = input
    }

    func stop() {
        reader.cancelReading()
        input.markAsFinished()
        writer.cancelWriting()
    }
}
