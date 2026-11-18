import Foundation

struct SubtitleCue: Equatable {
    var start: TimeInterval
    var end: TimeInterval
    var text: String
}

enum SubtitleFormat {
    case srt
    case vtt
}

enum SubtitleCodec {
    /// Each non-empty line becomes a cue, 3 seconds apart, starting at 00:00:00.
    static func cuesFromPlainText(_ text: String) -> [SubtitleCue] {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.components(separatedBy: "\n").filter { !$0.isEmpty }
        return lines.enumerated().map { index, line in
            let start = TimeInterval(index * 3)
            return SubtitleCue(start: start, end: start + 3, text: line)
        }
    }

    static func cues(from raw: String, format: SubtitleFormat) throws -> [SubtitleCue] {
        switch format {
        case .srt: return try parseSRT(raw)
        case .vtt: return try parseVTT(raw)
        }
    }

    static func writeSRT(_ cues: [SubtitleCue]) -> String {
        cues.enumerated().map { index, cue in
            "\(index + 1)\n\(formatTime(cue.start, vtt: false)) --> \(formatTime(cue.end, vtt: false))\n\(cue.text)\n"
        }.joined(separator: "\n")
    }

    static func writeVTT(_ cues: [SubtitleCue]) -> String {
        let body = cues.map { cue in
            "\(formatTime(cue.start, vtt: true)) --> \(formatTime(cue.end, vtt: true))\n\(cue.text)\n"
        }.joined(separator: "\n")
        return "WEBVTT\n\n" + body
    }

    /// Cue text only. Timestamps and cue numbers are omitted.
    static func plainText(_ cues: [SubtitleCue]) -> String {
        cues.map(\.text).joined(separator: "\n")
    }

    static func formatTime(_ seconds: TimeInterval, vtt: Bool) -> String {
        let clamped = max(0, seconds)
        let totalMillis = Int((clamped * 1000).rounded())
        let millis = totalMillis % 1000
        let totalSeconds = totalMillis / 1000
        let secs = totalSeconds % 60
        let mins = (totalSeconds / 60) % 60
        let hours = totalSeconds / 3600
        let separator = vtt ? "." : ","
        return String(format: "%02d:%02d:%02d%@%03d", hours, mins, secs, separator, millis)
    }

    private static func parseSRT(_ raw: String) throws -> [SubtitleCue] {
        let blocks = blocks(in: raw)
        var cues: [SubtitleCue] = []
        for block in blocks {
            let lines = block.components(separatedBy: "\n")
            guard let timingIndex = lines.firstIndex(where: { $0.contains("-->") }) else { continue }
            let timing = lines[timingIndex]
            let text = lines.dropFirst(timingIndex + 1).joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            guard let cue = cue(timing: timing, text: text) else {
                throw FileWheelError(FileWheelMessages.subtitleUnreadable)
            }
            if !text.isEmpty { cues.append(cue) }
        }
        return cues
    }

    private static func parseVTT(_ raw: String) throws -> [SubtitleCue] {
        var lines = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
        if lines.first?.hasPrefix("\u{FEFF}") == true {
            lines[0] = String(lines[0].dropFirst())
        }
        if lines.first?.trimmingCharacters(in: .whitespaces).hasPrefix("WEBVTT") == true {
            lines.removeFirst()
        }
        let rawBlocks = lines.joined(separator: "\n")
        var cues: [SubtitleCue] = []
        for block in blocks(in: rawBlocks) {
            let trimmed = block.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("NOTE") || trimmed.hasPrefix("STYLE") || trimmed.hasPrefix("REGION") {
                continue
            }
            let blockLines = trimmed.components(separatedBy: "\n")
            guard let timingIndex = blockLines.firstIndex(where: { $0.contains("-->") }) else { continue }
            let text = blockLines.dropFirst(timingIndex + 1).joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            guard let cue = cue(timing: blockLines[timingIndex], text: text) else {
                throw FileWheelError(FileWheelMessages.subtitleUnreadable)
            }
            if !text.isEmpty { cues.append(cue) }
        }
        return cues
    }

    private static func blocks(in raw: String) -> [String] {
        raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func cue(timing: String, text: String) -> SubtitleCue? {
        let parts = timing.components(separatedBy: "-->")
        guard parts.count >= 2 else { return nil }
        let startToken = parts[0].trimmingCharacters(in: .whitespaces)
        let endToken = parts[1].trimmingCharacters(in: .whitespaces).split(separator: " ").first.map(String.init) ?? ""
        guard let start = parseTime(startToken), let end = parseTime(endToken) else { return nil }
        return SubtitleCue(start: start, end: end, text: text)
    }

    static func parseTime(_ token: String) -> TimeInterval? {
        let cleaned = token.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        let pieces = cleaned.split(separator: ":").map(String.init)
        let seconds: Double
        let minutes: Double
        let hours: Double
        switch pieces.count {
        case 3:
            guard let h = Double(pieces[0]), let m = Double(pieces[1]), let s = Double(pieces[2]) else { return nil }
            hours = h
            minutes = m
            seconds = s
        case 2:
            guard let m = Double(pieces[0]), let s = Double(pieces[1]) else { return nil }
            hours = 0
            minutes = m
            seconds = s
        default:
            return nil
        }
        return hours * 3600 + minutes * 60 + seconds
    }
}
