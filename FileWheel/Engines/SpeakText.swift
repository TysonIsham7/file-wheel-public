import Foundation

/// Cleanup and 15,000-character splitting for Read aloud.
/// txt and md share this cleanup. Other formats pass already-extracted text.
enum SpeakTextCleanup {
    static func cleanMarkdown(_ raw: String) -> String {
        let normalized = raw.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let withoutFences = dropCodeFences(normalized)
        let lines = withoutFences.components(separatedBy: "\n").map(cleanLine)
        return lines.joined(separator: "\n")
    }

    private static func dropCodeFences(_ text: String) -> String {
        var output: [String] = []
        var inFence = false
        var fenceMark = ""
        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !inFence {
                if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                    inFence = true
                    fenceMark = trimmed.hasPrefix("```") ? "```" : "~~~"
                    continue
                }
                output.append(line)
            } else if trimmed.hasPrefix(fenceMark) {
                inFence = false
                fenceMark = ""
            }
        }
        return output.joined(separator: "\n")
    }

    private static func cleanLine(_ line: String) -> String {
        var text = line
        if let range = text.range(of: #"^\s{0,3}#{1,6}\s+"#, options: .regularExpression) {
            text.removeSubrange(range)
        }
        text = replaceLinks(text)
        text = stripEmphasis(text)
        return text
    }

    /// `[label](url)` and `![label](url)` keep the label. Reference links keep the label.
    private static func replaceLinks(_ text: String) -> String {
        var text = replacing(text, pattern: #"!\[([^\]]*)\]\([^)]*\)"#, with: "$1")
        text = replacing(text, pattern: #"\[([^\]]+)\]\([^)]*\)"#, with: "$1")
        text = replacing(text, pattern: #"\[([^\]]+)\]\[[^\]]*\]"#, with: "$1")
        return text
    }

    /// Removes emphasis marks and keeps the words they wrap. Snake_case is left alone.
    private static func stripEmphasis(_ text: String) -> String {
        var text = text
        let patterns = [
            #"\*\*\*([^\*\n]+)\*\*\*"#,
            #"___([^_\n]+)___"#,
            #"\*\*([^\*\n]+)\*\*"#,
            #"__([^_\n]+)__"#,
            #"~~([^~\n]+)~~"#,
            #"(?<!\*)\*([^\*\n]+)\*(?!\*)"#,
            #"(?<![A-Za-z0-9_])_([^_\n]+)_(?![A-Za-z0-9_])"#,
        ]
        for pattern in patterns {
            text = replacing(text, pattern: pattern, with: "$1")
        }
        return text
    }

    private static func replacing(_ text: String, pattern: String, with template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: template)
    }
}

/// Splits on paragraph boundaries at 15,000 characters and never drops text.
/// A paragraph longer than the ceiling is split on sentences, then words, then scalars.
enum TextChunker {
    static let limit = 15_000

    static func characterCount(_ text: String) -> Int {
        text.unicodeScalars.count
    }

    static func chunks(_ text: String) -> [String] {
        let paragraphs = paragraphs(in: text)
        var result: [String] = []
        var current: [String] = []
        var currentCount = 0

        func flush() {
            guard !current.isEmpty else { return }
            result.append(current.joined(separator: "\n\n"))
            current = []
            currentCount = 0
        }

        for paragraph in paragraphs {
            let pieces = splitOversized(paragraph)
            if pieces.count > 1 {
                flush()
                result.append(contentsOf: pieces)
                continue
            }
            guard let piece = pieces.first else { continue }
            let pieceCount = characterCount(piece)
            let separator = current.isEmpty ? 0 : 2
            if currentCount + separator + pieceCount > limit {
                flush()
            }
            if current.isEmpty {
                current = [piece]
                currentCount = pieceCount
            } else {
                current.append(piece)
                currentCount += 2 + pieceCount
            }
        }
        flush()
        return result
    }

    /// Form feeds (PDF page breaks) and blank lines are paragraph boundaries.
    static func paragraphs(in text: String) -> [String] {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{000C}", with: "\n\n")
        return normalized
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { characterCount($0) > 0 }
    }

    /// Keeps every scalar. Prefers a break after whitespace or sentence punctuation.
    private static func splitOversized(_ paragraph: String) -> [String] {
        if characterCount(paragraph) <= limit { return [paragraph] }
        let scalars = paragraph.unicodeScalars
        var result: [String] = []
        var start = scalars.startIndex
        while start < scalars.endIndex {
            var end = start
            var count = 0
            var lastBreak = start
            while end < scalars.endIndex && count < limit {
                let scalar = scalars[end]
                count += 1
                end = scalars.index(after: end)
                if scalar == " " || scalar == "\n" || scalar == "." || scalar == "!" || scalar == "?" {
                    lastBreak = end
                }
            }
            let cut = (end < scalars.endIndex && lastBreak > start) ? lastBreak : end
            result.append(String(String.UnicodeScalarView(scalars[start..<cut])))
            start = cut
        }
        return result.filter { characterCount($0) > 0 }
    }
}
