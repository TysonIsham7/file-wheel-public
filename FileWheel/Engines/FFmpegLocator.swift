import Foundation

public enum FFmpegLocator {
    public static let ffmpegSearchPaths = [
        "/opt/homebrew/bin/ffmpeg",
        "/usr/local/bin/ffmpeg",
        "/usr/bin/ffmpeg",
    ]

    public static let unarSearchPaths = [
        "/opt/homebrew/bin/unar",
        "/usr/local/bin/unar",
        "/usr/bin/unar",
    ]

    /// ffmpeg from `FILEWHEEL_FFMPEG`, then Homebrew and the usual system locations.
    public static func resolve(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> URL? {
        locate(environment: environment, fileManager: fileManager)
    }

    public static func locate(
        bundle _: Bundle? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> URL? {
        firstExecutable(
            override: environment["FILEWHEEL_FFMPEG"],
            paths: ffmpegSearchPaths,
            fileManager: fileManager
        )
    }

    public static func ffprobe(beside ffmpeg: URL, fileManager: FileManager = .default) -> URL? {
        let sibling = ffmpeg.deletingLastPathComponent().appendingPathComponent("ffprobe")
        if fileManager.isExecutableFile(atPath: sibling.path) {
            return sibling
        }
        return firstExecutable(
            override: nil,
            paths: [
                "/opt/homebrew/bin/ffprobe",
                "/usr/local/bin/ffprobe",
                "/usr/bin/ffprobe",
            ],
            fileManager: fileManager
        )
    }

    public static func unar(
        bundle _: Bundle? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> URL? {
        firstExecutable(
            override: environment["FILEWHEEL_UNAR"],
            paths: unarSearchPaths,
            fileManager: fileManager
        )
    }

    public static func parseVersion(_ text: String) -> String? {
        let pattern = #"ffmpeg version (\d+\.\d+(?:\.\d+)?)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range), match.numberOfRanges > 1,
              let versionRange = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[versionRange])
    }

    public static func check(executable: URL?, runner: CommandRunning) -> FFmpegVersionCheck {
        guard let executable else {
            return FFmpegVersionCheck(
                executable: nil,
                foundVersion: nil,
                pinnedVersion: "",
                matchesPin: false,
                summary: FileWheelMessages.ffmpegMissing,
                canEncodeWMA: false,
                hardwareH264: false
            )
        }
        let versionResult = try? runner.run(executable: executable, arguments: ["-version"])
        let versionText = (versionResult?.stdoutText ?? "") + (versionResult?.stderrText ?? "")
        let found = parseVersion(versionText)
        let encoders = (try? runner.run(executable: executable, arguments: ["-hide_banner", "-encoders"]))?.stdoutText ?? ""
        let canWMA = encoders.contains("wmav1") || encoders.contains("wmav2")
        let hardware = encoders.contains("h264_videotoolbox")
        let summary = found.map { "ffmpeg \($0)" } ?? "ffmpeg was found but its version could not be read."
        return FFmpegVersionCheck(
            executable: executable,
            foundVersion: found,
            pinnedVersion: found ?? "",
            matchesPin: found != nil,
            summary: summary,
            canEncodeWMA: canWMA,
            hardwareH264: hardware
        )
    }

    private static func firstExecutable(override: String?, paths: [String], fileManager: FileManager) -> URL? {
        var candidates: [URL] = []
        if let override, !override.isEmpty {
            candidates.append(URL(fileURLWithPath: override))
        }
        candidates.append(contentsOf: paths.map { URL(fileURLWithPath: $0) })
        return candidates.first { fileManager.isExecutableFile(atPath: $0.path) }
    }
}
