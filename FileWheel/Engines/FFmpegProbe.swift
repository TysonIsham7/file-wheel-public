import Foundation

public struct MediaInfo: Equatable, Sendable {
    public var duration: Double
    public var width: Int
    public var height: Int
    public var hasAudio: Bool
    public var audioChannels: Int

    public init(duration: Double, width: Int, height: Int, hasAudio: Bool, audioChannels: Int) {
        self.duration = duration
        self.width = width
        self.height = height
        self.hasAudio = hasAudio
        self.audioChannels = audioChannels
    }
}

public enum MediaProbe {
    public static func info(url: URL, ffmpeg: URL, ffprobe: URL?, runner: CommandRunning) throws -> MediaInfo {
        if let ffprobe {
            let result = try runner.run(
                executable: ffprobe,
                arguments: ["-v", "error", "-print_format", "json", "-show_format", "-show_streams", url.path],
                currentDirectory: nil,
                standardInput: nil,
                cancellation: nil
            )
            if result.status == 0, let parsed = parseProbe(result.stdoutText) {
                return parsed
            }
        }
        let result = try runner.run(
            executable: ffmpeg,
            arguments: ["-hide_banner", "-i", url.path],
            currentDirectory: nil,
            standardInput: nil,
            cancellation: nil
        )
        return parseFFmpegBanner(result.stderrText)
    }

    static func parseProbe(_ text: String) -> MediaInfo? {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let streams = json["streams"] as? [[String: Any]] ?? []
        var width = 0
        var height = 0
        var channels = 0
        var hasAudio = false
        for stream in streams {
            let type = stream["codec_type"] as? String
            if type == "video", width == 0 {
                width = stream["width"] as? Int ?? 0
                height = stream["height"] as? Int ?? 0
            }
            if type == "audio" {
                hasAudio = true
                channels = stream["channels"] as? Int ?? channels
            }
        }
        let format = json["format"] as? [String: Any]
        let duration = Double(format?["duration"] as? String ?? "") ?? 0
        return MediaInfo(duration: duration, width: width, height: height, hasAudio: hasAudio, audioChannels: channels)
    }

    static func parseFFmpegBanner(_ text: String) -> MediaInfo {
        var duration = 0.0
        if let range = text.range(of: #"Duration:\s+(\d+):(\d+):(\d+(?:\.\d+)?)"#, options: .regularExpression) {
            let slice = String(text[range])
            let parts = slice.replacingOccurrences(of: "Duration:", with: "").trimmingCharacters(in: .whitespaces).split(separator: ":")
            if parts.count == 3 {
                let hours = Double(String(parts[0])) ?? 0
                let minutes = Double(String(parts[1])) ?? 0
                let seconds = Double(String(parts[2])) ?? 0
                duration = hours * 3600 + minutes * 60 + seconds
            }
        }
        var width = 0
        var height = 0
        if let match = text.range(of: #"(\d{2,5})x(\d{2,5})"#, options: .regularExpression) {
            let pair = String(text[match]).split(separator: "x")
            if pair.count == 2 {
                width = Int(pair[0]) ?? 0
                height = Int(pair[1]) ?? 0
            }
        }
        let hasAudio = text.contains("Audio:")
        return MediaInfo(duration: duration, width: width, height: height, hasAudio: hasAudio, audioChannels: hasAudio ? 2 : 0)
    }
}

public enum FFmpegRun {
    public static func run(
        _ ffmpeg: URL,
        arguments: [String],
        runner: CommandRunning,
        cancellation: CancellationFlag?,
        standardInput: Data? = nil
    ) throws {
        let result = try runner.run(
            executable: ffmpeg,
            arguments: arguments,
            currentDirectory: nil,
            standardInput: standardInput,
            cancellation: cancellation
        )
        if cancellation?.isCancelled == true {
            throw ToolError.cancelled
        }
        if result.status != 0 {
            throw ToolError.message(ProcessText.lastUsefulLine(result.stderrText))
        }
    }
}
