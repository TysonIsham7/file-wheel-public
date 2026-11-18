import Foundation

public enum FFmpegTask: Equatable, Sendable {
    case audio(codec: String, extra: [String])
    case video(videoCodec: String, videoExtra: [String], audioCodec: String, audioExtra: [String], longEdge: Int, fastStart: Bool)
    case gif(maxWidth: Int, fps: Int)
    case extractMP3
    case still(codec: String, extra: [String])
}

/// Builds ffmpeg argv. The executable path is not part of this array and is never passed through a shell.
public enum FFmpegCommand {
    public static func arguments(input: URL, output: URL, task: FFmpegTask, progress: Bool) -> [String] {
        var args = ["-hide_banner", "-nostdin", "-y", "-i", input.path]
        if progress {
            args.append(contentsOf: ["-nostats", "-progress", "pipe:1"])
        }
        switch task {
        case .audio(let codec, let extra):
            args.append(contentsOf: ["-vn", "-c:a", codec])
            args.append(contentsOf: extra)
        case .video(let videoCodec, let videoExtra, let audioCodec, let audioExtra, let longEdge, let fastStart):
            args.append(contentsOf: ["-c:v", videoCodec])
            args.append(contentsOf: videoExtra)
            args.append(contentsOf: ["-pix_fmt", "yuv420p", "-vf", scaleFilter(longEdge: longEdge)])
            args.append(contentsOf: ["-c:a", audioCodec])
            args.append(contentsOf: audioExtra)
            if fastStart {
                args.append(contentsOf: ["-movflags", "+faststart"])
            }
        case .gif(let maxWidth, let fps):
            args.append(contentsOf: ["-an", "-vf", gifFilter(maxWidth: maxWidth, fps: fps), "-loop", "0"])
        case .extractMP3:
            args.append(contentsOf: ["-vn", "-map", "0:a:0", "-c:a", "libmp3lame", "-q:a", "2"])
        case .still(let codec, let extra):
            args.append(contentsOf: ["-frames:v", "1", "-update", "1", "-c:v", codec])
            args.append(contentsOf: extra)
        }
        args.append(output.path)
        return args
    }

    public static func task(entry: CatalogEntry, options: ConversionOptions) -> FFmpegTask {
        switch entry.kind {
        case .audio:
            return audioTask(target: entry.target)
        case .video:
            if entry.target == "gif" {
                return .gif(maxWidth: options.gifMaxWidth, fps: options.gifFPS)
            }
            if entry.target == "mp3" {
                return .extractMP3
            }
            return videoTask(target: entry.target, options: options)
        case .image:
            return stillTask(target: entry.target, quality: options.jpegQuality)
        case .pdf, .text, .subtitle, .archive, .folder, .markdown, .word, .unknown:
            return stillTask(target: entry.target, quality: options.jpegQuality)
        }
    }

    public static func scaleFilter(longEdge: Int) -> String {
        let edge = max(2, longEdge)
        return "scale=w=\(edge):h=\(edge):force_original_aspect_ratio=decrease:force_divisible_by=2"
    }

    public static func gifFilter(maxWidth: Int, fps: Int) -> String {
        let width = max(2, maxWidth)
        let rate = max(1, fps)
        return "fps=\(rate),scale='min(\(width)\\,iw)':-2:flags=lanczos,split[s0][s1];[s0]palettegen=stats_mode=diff[p];[s1][p]paletteuse"
    }

    static func audioTask(target: String) -> FFmpegTask {
        switch target {
        case "mp3":
            return .audio(codec: "libmp3lame", extra: ["-q:a", "2"])
        case "m4a":
            return .audio(codec: "aac", extra: ["-b:a", "192k"])
        case "wav":
            return .audio(codec: "pcm_s16le", extra: [])
        case "aiff":
            return .audio(codec: "pcm_s16be", extra: [])
        case "flac":
            return .audio(codec: "flac", extra: [])
        case "ogg":
            return .audio(codec: "libvorbis", extra: ["-q:a", "5"])
        case "opus":
            return .audio(codec: "libopus", extra: ["-b:a", "128k", "-ar", "48000"])
        case "wma":
            return .audio(codec: "wmav2", extra: ["-b:a", "128k"])
        default:
            return .audio(codec: "aac", extra: ["-b:a", "192k"])
        }
    }

    static func videoTask(target: String, options: ConversionOptions) -> FFmpegTask {
        let edge = options.maxLongEdge
        switch target {
        case "webm":
            let codec = "libvpx-vp9"
            return .video(
                videoCodec: codec,
                videoExtra: ["-crf", "32", "-b:v", "0", "-cpu-used", "4"],
                audioCodec: "libopus",
                audioExtra: ["-b:a", "128k", "-ar", "48000"],
                longEdge: edge,
                fastStart: false
            )
        case "avi":
            return .video(
                videoCodec: "mpeg4",
                videoExtra: ["-q:v", "5"],
                audioCodec: "libmp3lame",
                audioExtra: ["-q:a", "2"],
                longEdge: edge,
                fastStart: false
            )
        case "wmv":
            return .video(
                videoCodec: "wmv2",
                videoExtra: ["-b:v", "2M"],
                audioCodec: "wmav2",
                audioExtra: ["-b:a", "128k"],
                longEdge: edge,
                fastStart: false
            )
        default:
            let hardware = options.hardwareEncoder
            let videoCodec = hardware ? "h264_videotoolbox" : "libx264"
            let videoExtra = hardware
                ? ["-b:v", "8M"]
                : ["-preset", "medium", "-crf", String(options.videoCRF)]
            let fastStart = target == "mp4" || target == "mov"
            return .video(
                videoCodec: videoCodec,
                videoExtra: videoExtra,
                audioCodec: "aac",
                audioExtra: ["-b:a", "192k"],
                longEdge: edge,
                fastStart: fastStart
            )
        }
    }

    static func stillTask(target: String, quality: Double) -> FFmpegTask {
        switch target {
        case "avif":
            return .still(codec: "libaom-av1", extra: ["-still-picture", "1"])
        case "bmp":
            return .still(codec: "bmp", extra: [])
        case "webp":
            let q = Int((quality * 100).rounded())
            return .still(codec: "libwebp", extra: ["-quality", String(q)])
        case "jpg":
            let q = max(1, min(31, Int(((1 - quality) * 30).rounded()) + 1))
            return .still(codec: "mjpeg", extra: ["-q:v", String(q)])
        case "heic":
            return .still(codec: "libx265", extra: ["-tag:v", "hvc1"])
        case "png":
            return .still(codec: "png", extra: [])
        case "gif":
            return .still(codec: "gif", extra: [])
        case "tif":
            return .still(codec: "tiff", extra: [])
        default:
            return .still(codec: "png", extra: [])
        }
    }
}

public enum FFmpegDiagnostics {
    public static func lastUsefulLine(_ stderr: String) -> String {
        let lines = stderr
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !isProgress($0) }
        let markers = ["error", "invalid", "no such", "does not", "failed", "unknown", "unable"]
        if let hit = lines.last(where: { line in
            let lower = line.lowercased()
            return markers.contains { lower.contains($0) }
        }) {
            return hit
        }
        return lines.last ?? "ffmpeg failed"
    }

    public static func streams(fromStderr stderr: String) -> MediaStreams {
        let text = stderr.replacingOccurrences(of: "\r", with: "\n")
        let hasAudio = text.range(
            of: #"Stream #\d+:\d+.*:\s*Audio:"#,
            options: .regularExpression
        ) != nil
        let hasVideo = text.range(
            of: #"Stream #\d+:\d+.*:\s*Video:"#,
            options: .regularExpression
        ) != nil
        return MediaStreams(hasAudio: hasAudio, hasVideo: hasVideo, durationSeconds: duration(in: text))
    }

    static func duration(in text: String) -> Double? {
        guard let match = text.range(of: #"Duration:\s*(\d+):(\d+):(\d+(?:\.\d+)?)"#, options: .regularExpression) else {
            return nil
        }
        let slice = String(text[match])
        let numbers = slice.split { !$0.isNumber && $0 != "." }.map(String.init).filter { !$0.isEmpty }
        guard numbers.count >= 3,
              let hours = Double(numbers[0]),
              let minutes = Double(numbers[1]),
              let seconds = Double(numbers[2]) else {
            return nil
        }
        return hours * 3600 + minutes * 60 + seconds
    }

    public static func fraction(progressChunk: String, duration: Double?) -> Double? {
        guard let duration, duration > 0 else { return nil }
        var seconds: Double?
        for raw in progressChunk.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("out_time_us=") {
                let value = line.dropFirst("out_time_us=".count)
                if let micros = Double(value) {
                    seconds = micros / 1_000_000
                }
            } else if line.hasPrefix("out_time_ms="), seconds == nil {
                let value = line.dropFirst("out_time_ms=".count)
                if let raw = Double(value) {
                    // Some ffmpeg builds report microseconds in out_time_ms.
                    seconds = raw > duration * 1000 ? raw / 1_000_000 : raw / 1000
                }
            } else if line.hasPrefix("out_time="), seconds == nil {
                let clock = String(line.dropFirst("out_time=".count))
                seconds = Self.duration(in: "Duration: \(clock)")
            }
        }
        guard let seconds else { return nil }
        return min(1, max(0, seconds / duration))
    }

    private static func isProgress(_ line: String) -> Bool {
        if line.hasPrefix("frame=") || line.hasPrefix("size=") { return true }
        if line.hasPrefix("video:") || line.hasPrefix("Press [q]") { return true }
        if line.contains("bitrate=") && line.contains("speed=") { return true }
        return false
    }
}

public struct MediaStreams: Equatable, Sendable {
    public var hasAudio: Bool
    public var hasVideo: Bool
    public var durationSeconds: Double?

    public init(hasAudio: Bool, hasVideo: Bool, durationSeconds: Double?) {
        self.hasAudio = hasAudio
        self.hasVideo = hasVideo
        self.durationSeconds = durationSeconds
    }
}
