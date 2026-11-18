import Foundation

/// Finds ffmpeg and unar already installed on the Mac.
/// Search order is `FILEWHEEL_FFMPEG` / `FILEWHEEL_UNAR`, then `/opt/homebrew/bin`, `/usr/local/bin`, and `/usr/bin`.
enum SystemToolLocator {
    static func ffmpeg(bundle: Bundle = .main) -> URL? {
        _ = bundle
        return FFmpegLocator.resolve()
    }

    static func unar(bundle: Bundle = .main) -> URL? {
        _ = bundle
        return FFmpegLocator.unar()
    }

    static func ffmpegVersion(bundle: Bundle = .main) async -> String? {
        guard let url = ffmpeg(bundle: bundle) else { return nil }
        guard let output = try? await CapturedProcess.run(executable: url, arguments: ["-version"]) else { return nil }
        guard output.status == 0 else { return nil }
        let text = String(data: output.stdout, encoding: .utf8) ?? ""
        return text.split(whereSeparator: \.isNewline).first.map(String.init)
    }

    static func ffmpegGap(bundle: Bundle = .main) async -> String? {
        ffmpeg(bundle: bundle) == nil ? FileWheelMessages.ffmpegMissing : nil
    }

    static func unarGap(bundle: Bundle = .main) -> String? {
        unar(bundle: bundle) == nil ? FileWheelMessages.rarBinaryMissing : nil
    }
}
