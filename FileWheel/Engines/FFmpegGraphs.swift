import Foundation

public enum AtempoChain {
    /// ffmpeg `atempo` accepts 0.5...2.0. Extra filters cover rates outside that range.
    public static func filters(for rate: Double) -> [String] {
        var remaining = rate
        var parts: [String] = []
        var guardrail = 0
        while remaining < 0.5 && guardrail < 8 {
            parts.append("atempo=0.5")
            remaining /= 0.5
            guardrail += 1
        }
        while remaining > 2.0 && guardrail < 16 {
            parts.append("atempo=2.0")
            remaining /= 2.0
            guardrail += 1
        }
        let clamped = min(2.0, max(0.5, remaining))
        parts.append(String(format: "atempo=%.4f", clamped))
        return parts
    }
}

public enum SnapshotTimes {
    public static func every(_ interval: Double, duration: Double) -> [Double] {
        guard interval > 0, duration > 0 else { return [] }
        var times: [Double] = []
        var cursor = 0.0
        while cursor < duration - 0.001 && times.count < 500 {
            times.append(cursor)
            cursor += interval
        }
        return times.isEmpty ? [0] : times
    }

    public static func count(_ count: Int, duration: Double) -> [Double] {
        guard count > 0, duration > 0 else { return [] }
        if count == 1 {
            return [duration / 2]
        }
        return (0..<count).map { index in
            duration * Double(index) / Double(count - 1)
        }
    }
}

public enum FFmpegGraphs {
    public static func channelFilter(_ mode: ChannelMode) -> [String] {
        switch mode {
        case .mono:
            return ["-ac", "1"]
        case .stereo:
            return ["-ac", "2"]
        case .left:
            return ["-af", "pan=mono|c0=c0"]
        case .right:
            return ["-af", "pan=mono|c0=c1"]
        case .swap:
            return ["-af", "pan=stereo|c0=c1|c1=c0"]
        }
    }

    public static func speedFilters(rate: Double, hasAudio: Bool) -> [String] {
        var filters: [String] = ["-filter:v", "setpts=PTS/\(String(format: "%.4f", rate))"]
        if hasAudio {
            let audio = AtempoChain.filters(for: rate).joined(separator: ",")
            filters.append(contentsOf: ["-filter:a", audio])
        }
        return filters
    }

    public static func loudnormArguments(video: Bool) -> [String] {
        if video {
            return ["-map", "0:v:0", "-map", "0:a:0?", "-c:v", "copy", "-c:a", "aac", "-af", "loudnorm=I=-16:TP=-1.5:LRA=11"]
        }
        return ["-af", "loudnorm=I=-16:TP=-1.5:LRA=11"]
    }

    public static func bleepFilter(ranges: [TimeRange], toneHz: Double, duration: Double) -> String {
        let windows = ranges.filter(\.isValid).map { range in
            "between(t\\,\(String(format: "%.3f", range.start))\\,\(String(format: "%.3f", range.end)))"
        }
        let gate = windows.isEmpty ? "0" : windows.joined(separator: "+")
        let hz = String(format: "%.2f", toneHz)
        let length = String(format: "%.3f", max(duration, 0.1))
        return "[0:a]aformat=sample_fmts=fltp:channel_layouts=stereo,volume=0:enable='\(gate)'[muted];sine=frequency=\(hz):sample_rate=44100:duration=\(length)[tone];[tone]volume=0:enable='not(\(gate))'[beep];[muted][beep]amix=inputs=2:normalize=0:duration=first[aout]"
    }

    public static func jpegQualityArgument(_ quality: Double) -> String {
        let clamped = min(1, max(0.01, quality))
        let q = Int((1 - clamped) * 29 + 2)
        return String(q)
    }

    public static func videoEncoder(codec: VideoCodecChoice, hardware: Bool, hardwareAvailable: Bool) -> String {
        if hardware && hardwareAvailable {
            return codec == .hevc ? "hevc_videotoolbox" : "h264_videotoolbox"
        }
        return codec.ffmpegEncoder
    }
}

public enum PageRangeParser {
    public static func parse(_ text: String, pageCount: Int) throws -> [ClosedRange<Int>] {
        let cleaned = text.replacingOccurrences(of: " ", with: "")
        if cleaned.isEmpty {
            throw ToolError.message("Enter a page range.")
        }
        var ranges: [ClosedRange<Int>] = []
        for part in cleaned.split(separator: ",") {
            let piece = String(part)
            if piece.contains("-") {
                let ends = piece.split(separator: "-", maxSplits: 1).map(String.init)
                guard ends.count == 2, let lower = Int(ends[0]), let upper = Int(ends[1]), lower >= 1, upper >= lower, upper <= pageCount else {
                    throw ToolError.message("Page range \(piece) is outside 1–\(pageCount).")
                }
                ranges.append(lower...upper)
            } else {
                guard let page = Int(piece), page >= 1, page <= pageCount else {
                    throw ToolError.message("Page \(piece) is outside 1–\(pageCount).")
                }
                ranges.append(page...page)
            }
        }
        return ranges
    }
}
