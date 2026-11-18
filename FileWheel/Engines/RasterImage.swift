import Foundation

public struct RasterImage: Equatable, Sendable {
    public var width: Int
    public var height: Int
    public var rgba: [UInt8]

    public init(width: Int, height: Int, rgba: [UInt8]) {
        self.width = width
        self.height = height
        if rgba.count == width * height * 4 {
            self.rgba = rgba
        } else {
            self.rgba = [UInt8](repeating: 0, count: max(0, width * height * 4))
        }
    }

    public init(width: Int, height: Int, fill: RGBA) {
        var data = [UInt8](repeating: 0, count: max(0, width * height * 4))
        for index in 0..<max(0, width * height) {
            data[index * 4] = fill.r
            data[index * 4 + 1] = fill.g
            data[index * 4 + 2] = fill.b
            data[index * 4 + 3] = fill.a
        }
        self.init(width: width, height: height, rgba: data)
    }

    public func pixel(_ x: Int, _ y: Int) -> RGBA {
        guard x >= 0, y >= 0, x < width, y < height else { return .black }
        let index = (y * width + x) * 4
        return RGBA(r: rgba[index], g: rgba[index + 1], b: rgba[index + 2], a: rgba[index + 3])
    }

    public mutating func setPixel(_ x: Int, _ y: Int, _ pixel: RGBA) {
        guard x >= 0, y >= 0, x < width, y < height else { return }
        let index = (y * width + x) * 4
        rgba[index] = pixel.r
        rgba[index + 1] = pixel.g
        rgba[index + 2] = pixel.b
        rgba[index + 3] = pixel.a
    }
}

public enum RasterCodec {
    public static func decode(url: URL, ffmpeg: URL, runner: CommandRunning, cancellation: CancellationFlag?) throws -> RasterImage {
        let result = try runner.run(
            executable: ffmpeg,
            arguments: ["-hide_banner", "-i", url.path, "-f", "rawvideo", "-pix_fmt", "rgba", "-"],
            currentDirectory: nil,
            standardInput: nil,
            cancellation: cancellation
        )
        if result.status != 0 {
            throw ToolError.message(ProcessText.lastUsefulLine(result.stderrText))
        }
        let info = try MediaProbe.info(url: url, ffmpeg: ffmpeg, ffprobe: FFmpegLocator.ffprobe(beside: ffmpeg), runner: runner)
        let width = info.width
        let height = info.height
        guard width > 0, height > 0, result.stdout.count >= width * height * 4 else {
            throw ToolError.message("Could not read the image.")
        }
        return RasterImage(width: width, height: height, rgba: Array(result.stdout.prefix(width * height * 4)))
    }

    public static func encode(_ image: RasterImage, to url: URL, format: String, quality: Double, ffmpeg: URL, runner: CommandRunning, cancellation: CancellationFlag?) throws {
        var arguments = [
            "-hide_banner", "-y",
            "-f", "rawvideo",
            "-pix_fmt", "rgba",
            "-s", "\(image.width)x\(image.height)",
            "-i", "-"
        ]
        switch format {
        case "jpg", "jpeg":
            arguments.append(contentsOf: ["-q:v", FFmpegGraphs.jpegQualityArgument(quality)])
        case "webp":
            arguments.append(contentsOf: ["-c:v", "libwebp", "-quality", String(Int(min(100, max(1, quality * 100))))])
        case "png":
            arguments.append(contentsOf: ["-c:v", "png"])
        case "bmp":
            arguments.append(contentsOf: ["-c:v", "bmp"])
        case "tif":
            arguments.append(contentsOf: ["-c:v", "tiff"])
        case "gif":
            arguments.append(contentsOf: ["-c:v", "gif"])
        default:
            arguments.append(contentsOf: ["-q:v", FFmpegGraphs.jpegQualityArgument(quality)])
        }
        arguments.append(url.path)
        let data = Data(image.rgba)
        try FFmpegRun.run(ffmpeg, arguments: arguments, runner: runner, cancellation: cancellation, standardInput: data)
    }
}
