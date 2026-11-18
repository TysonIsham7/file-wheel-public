import Foundation

public struct ToolEnvironment {
    public var runner: CommandRunning
    public var ffmpeg: URL?
    public var ffprobe: URL?
    public var unar: URL?
    public var zip: URL
    public var unzip: URL
    public var tar: URL
    public var gzip: URL
    public var qr: QRDetecting
    public var speech: SpeechRangeFinding
    public var textRecognizer: any TextRecognizing
    public var cancellation: CancellationFlag
    public var hardwareH264: Bool

    public init(
        runner: CommandRunning,
        ffmpeg: URL?,
        ffprobe: URL?,
        unar: URL?,
        zip: URL,
        unzip: URL,
        tar: URL,
        gzip: URL,
        qr: QRDetecting,
        speech: SpeechRangeFinding,
        textRecognizer: any TextRecognizing,
        cancellation: CancellationFlag,
        hardwareH264: Bool
    ) {
        self.runner = runner
        self.ffmpeg = ffmpeg
        self.ffprobe = ffprobe
        self.unar = unar
        self.zip = zip
        self.unzip = unzip
        self.tar = tar
        self.gzip = gzip
        self.qr = qr
        self.speech = speech
        self.textRecognizer = textRecognizer
        self.cancellation = cancellation
        self.hardwareH264 = hardwareH264
    }

    public static func system(cancellation: CancellationFlag = CancellationFlag(), qr: QRDetecting? = nil) -> ToolEnvironment {
        let ffmpeg = FFmpegLocator.locate()
        let runner = FoundationCommandRunner()
        let check = FFmpegLocator.check(executable: ffmpeg, runner: runner)
        return ToolEnvironment(
            runner: runner,
            ffmpeg: ffmpeg,
            ffprobe: ffmpeg.flatMap { FFmpegLocator.ffprobe(beside: $0) },
            unar: FFmpegLocator.unar(),
            zip: URL(fileURLWithPath: "/usr/bin/zip"),
            unzip: URL(fileURLWithPath: "/usr/bin/unzip"),
            tar: URL(fileURLWithPath: "/usr/bin/tar"),
            gzip: URL(fileURLWithPath: "/usr/bin/gzip"),
            qr: qr ?? FixedQRDetector(codes: []),
            speech: FailingSpeechFinder(),
            textRecognizer: VisionTextRecognizer(),
            cancellation: cancellation,
            hardwareH264: check.hardwareH264
        )
    }
}

extension ToolEnvironment {
    public static func production() -> ToolEnvironment {
        #if canImport(Vision) && canImport(AppKit)
        return system(qr: VisionQRDetector())
        #else
        return system()
        #endif
    }
}

public enum ToolExecutor {
    /// Tool jobs never open a network connection. Read aloud is a separate phase.
    public static let allowsNetwork = false

    public static func run(_ request: ToolRunRequest, environment: ToolEnvironment) throws -> ToolRunOutcome {
        var request = request
        defer { request.parameters = request.parameters.scrubbed() }
        try ToolValidation.validate(request)
        try throwIfCancelled(environment)
        let work = ToolWork(request: request, environment: environment)
        switch request.tool {
        case .compress: return try work.compress()
        case .cropImage: return try work.cropImage()
        case .adjustImage: return try work.adjustImage()
        case .annotate: return try work.annotate()
        case .redact: return try work.redact()
        case .trimVideo: return try work.trim(video: true)
        case .cropVideo: return try work.cropVideo()
        case .speed: return try work.speed()
        case .splitVideo: return try work.splitVideo()
        case .joinVideos: return try work.joinVideos()
        case .snapshots: return try work.snapshots()
        case .normalizeAudio: return try work.normalize()
        case .trimAudio: return try work.trim(video: false)
        case .bleep: return try work.bleep()
        case .channels: return try work.channels()
        case .editMetadata: return try work.editMetadata()
        case .stripMetadata: return try work.stripMetadata()
        case .mergePDFs: return try work.mergePDFs()
        case .splitPDF: return try work.splitPDF()
        case .reorganizePDF: return try work.reorganizePDF()
        case .imagesToPDF: return try work.imagesToPDF()
        case .collage: return try work.collage()
        case .readQR: return try work.readQR()
        case .extractArchive: return try work.extractArchive()
        case .packArchive: return try work.packArchive()
        case .ocrPDF: return try work.ocrPDF()
        case .signPDF: return try work.signPDF()
        case .protectPDF:
            switch request.parameters {
            case .unlockPDF:
                return try work.unlockPDF()
            default:
                return try work.protectPDF()
            }
        }
    }

    private static func throwIfCancelled(_ environment: ToolEnvironment) throws {
        if environment.cancellation.isCancelled {
            throw ToolError.cancelled
        }
    }
}

final class ToolWork {
    var request: ToolRunRequest
    var environment: ToolEnvironment
    var reserved: Set<String> = []

    init(request: ToolRunRequest, environment: ToolEnvironment) {
        self.request = request
        self.environment = environment
    }

    deinit {
        request.parameters = request.parameters.scrubbed()
    }

    func compress() throws -> ToolRunOutcome {
        guard case .compress(let parameters) = request.parameters else { throw ToolError.message("Compress needs its settings.") }
        var outputs: [URL] = []
        var notice: String?
        var met: Bool?
        for file in request.files {
            switch file.kind {
            case .image:
                let outcome = try compressImage(file, parameters)
                outputs.append(outcome.url)
                notice = outcome.notice ?? notice
                met = outcome.met
            case .video:
                let outcome = try compressVideo(file, parameters)
                outputs.append(outcome.url)
                notice = outcome.notice ?? notice
                met = outcome.met
            case .audio:
                let outcome = try compressAudio(file, parameters)
                outputs.append(outcome.url)
                notice = outcome.notice ?? notice
                met = outcome.met
            case .pdf:
                let outcome = try compressPDF(file, parameters)
                outputs.append(outcome.url)
                notice = outcome.notice ?? notice
                met = outcome.met
            default:
                throw ToolError.message("Compress does not apply to \(file.url.lastPathComponent).")
            }
        }
        return ToolRunOutcome(outputs: outputs, message: notice, metCompressTarget: met)
    }

    func cropImage() throws -> ToolRunOutcome {
        guard case .cropImage(let parameters) = request.parameters, let file = request.files.first else {
            throw ToolError.message("Crop image needs one image.")
        }
        let image = try decode(file)
        let cropped = try ImageOps.crop(image, to: parameters.rect)
        let url = try writeImage(cropped, like: file, quality: request.settings.jpegQuality)
        return ToolRunOutcome(outputs: [url])
    }

    func adjustImage() throws -> ToolRunOutcome {
        guard case .adjustImage(let parameters) = request.parameters, let file = request.files.first else {
            throw ToolError.message("Adjust image needs one image.")
        }
        let image = try decode(file)
        let adjusted = ImageOps.adjust(
            image,
            exposure: parameters.exposure,
            contrast: parameters.contrast,
            saturation: parameters.saturation,
            sharpness: parameters.sharpness,
            rotation: parameters.rotation,
            flipHorizontal: parameters.flipHorizontal,
            flipVertical: parameters.flipVertical
        )
        let url = try writeImage(adjusted, like: file, quality: request.settings.jpegQuality)
        return ToolRunOutcome(outputs: [url])
    }

    func annotate() throws -> ToolRunOutcome {
        guard case .annotate(let parameters) = request.parameters, let file = request.files.first else {
            throw ToolError.message("Annotate needs one image.")
        }
        var image = try decode(file)
        for mark in parameters.marks {
            switch mark {
            case .pen(let points, let width):
                guard let first = points.first else { continue }
                var previous = first
                for point in points.dropFirst() {
                    ImageOps.line(image: &image, from: previous, to: point, color: .black, thickness: max(1, Int(width)))
                    previous = point
                }
            case .text(let string, let origin, let size):
                ImageOps.drawText(&image, text: string, origin: origin, size: size, color: .black)
            case .rectangle(let rect, let width):
                ImageOps.strokeRect(&image, rect: rect, color: .black, width: max(1, Int(width)))
            case .arrow(let start, let end):
                ImageOps.arrow(image: &image, from: start, to: end, color: .black)
            }
        }
        let url = try writeImage(image, like: file, quality: request.settings.jpegQuality)
        return ToolRunOutcome(outputs: [url])
    }

    func redact() throws -> ToolRunOutcome {
        guard case .redact(let parameters) = request.parameters, let file = request.files.first else {
            throw ToolError.message("Redact needs one image or PDF.")
        }
        if file.kind == .pdf {
            let document: SimplePDF
            do {
                document = try readPDF(file)
            } catch let error as ToolError where error == .passwordProtected {
                throw error
            } catch {
                #if canImport(PDFKit) && canImport(AppKit)
                let url = try allocate(file, base: file.baseName, ext: "pdf")
                try PDFKitEngine.rasterRedact(source: file.url, boxes: parameters.boxes, destination: url)
                return ToolRunOutcome(outputs: [url], message: "Redacted regions were rasterized, so the text underneath is gone.")
                #else
                throw error
                #endif
            }
            let edited = document.redacting(parameters.boxes)
            let url = try writePDF(edited, base: file.baseName, source: file)
            let covered = parameters.boxes.map(\.rect)
            let remaining = edited.pages.flatMap { $0.spans() }
            let text = Redaction.remainingText(remaining, covering: covered)
            if parameters.boxes.contains(where: { box in
                document.pages.indices.contains(box.pageIndex) && document.pages[box.pageIndex].spans().contains { $0.rect.intersects(box.rect) }
            }) && text == document.extractableText() {
                throw ToolError.message("Redaction did not remove the covered text.")
            }
            return ToolRunOutcome(outputs: [url])
        }
        var image = try decode(file)
        for box in parameters.boxes {
            ImageOps.fill(&image, rect: box.rect, color: .black)
        }
        let url = try writeImage(image, like: file, quality: 0.92)
        return ToolRunOutcome(outputs: [url])
    }

    func trim(video: Bool) throws -> ToolRunOutcome {
        let parameters: TrimParameters
        if video, case .trimVideo(let value) = request.parameters {
            parameters = value
        } else if !video, case .trimAudio(let value) = request.parameters {
            parameters = value
        } else {
            throw ToolError.message("Trim needs in and out points.")
        }
        guard let file = request.files.first else { throw ToolError.message("Trim needs one file.") }
        let ffmpeg = try requireFFmpeg()
        let ext = file.normalizedExtension
        let url = try allocate(file, base: file.baseName, ext: ext)
        var arguments = ["-hide_banner", "-y", "-i", file.url.path, "-ss", String(parameters.start), "-to", String(parameters.end)]
        if video {
            arguments.append(contentsOf: ["-c:v", "libx264", "-preset", "veryfast", "-c:a", "aac"])
        } else {
            arguments.append(contentsOf: audioCodec(ext))
        }
        arguments.append(url.path)
        try FFmpegRun.run(ffmpeg, arguments: arguments, runner: environment.runner, cancellation: environment.cancellation)
        return ToolRunOutcome(outputs: [url])
    }

    func cropVideo() throws -> ToolRunOutcome {
        guard case .cropVideo(let parameters) = request.parameters, let file = request.files.first else {
            throw ToolError.message("Crop video needs one video.")
        }
        let ffmpeg = try requireFFmpeg()
        let rect = parameters.rect.integral()
        let url = try allocate(file, base: file.baseName, ext: file.normalizedExtension)
        let filter = "crop=\(Int(rect.width)):\(Int(rect.height)):\(Int(rect.x)):\(Int(rect.y))"
        try FFmpegRun.run(ffmpeg, arguments: ["-hide_banner", "-y", "-i", file.url.path, "-vf", filter, "-c:v", "libx264", "-preset", "veryfast", "-c:a", "copy", url.path], runner: environment.runner, cancellation: environment.cancellation)
        return ToolRunOutcome(outputs: [url])
    }

    func speed() throws -> ToolRunOutcome {
        guard case .speed(let parameters) = request.parameters, let file = request.files.first else {
            throw ToolError.message("Speed needs one video.")
        }
        let ffmpeg = try requireFFmpeg()
        let info = try probe(file)
        let url = try allocate(file, base: file.baseName, ext: file.normalizedExtension)
        var arguments = ["-hide_banner", "-y", "-i", file.url.path]
        arguments.append(contentsOf: FFmpegGraphs.speedFilters(rate: parameters.rate.value, hasAudio: info.hasAudio))
        arguments.append(contentsOf: ["-c:v", "libx264", "-preset", "veryfast"])
        if info.hasAudio {
            arguments.append(contentsOf: ["-c:a", "aac"])
        }
        arguments.append(url.path)
        try FFmpegRun.run(ffmpeg, arguments: arguments, runner: environment.runner, cancellation: environment.cancellation)
        return ToolRunOutcome(outputs: [url])
    }

    func splitVideo() throws -> ToolRunOutcome {
        guard case .splitVideo(let parameters) = request.parameters, let file = request.files.first else {
            throw ToolError.message("Split video needs one video.")
        }
        let ffmpeg = try requireFFmpeg()
        let info = try probe(file)
        let ranges: [(Double, Double)]
        switch parameters.mode {
        case .playhead(let time):
            guard time > 0, time < info.duration else { throw ToolError.message("The playhead has to sit inside the video.") }
            ranges = [(0, time), (time, info.duration)]
        case .equalParts(let count):
            guard info.duration > 0 else { throw ToolError.message("The video has no duration.") }
            var built: [(Double, Double)] = []
            let partCount = Double(count)
            for index in 0..<count {
                let start = info.duration * Double(index) / partCount
                let end = info.duration * Double(index + 1) / partCount
                built.append((start, end))
            }
            ranges = built
        }
        var outputs: [URL] = []
        for (index, range) in ranges.enumerated() {
            try throwIfCancelled()
            let url = try allocate(file, base: String(format: "%@-part-%03d", file.baseName, index + 1), ext: file.normalizedExtension)
            try FFmpegRun.run(
                ffmpeg,
                arguments: ["-hide_banner", "-y", "-i", file.url.path, "-ss", String(range.0), "-to", String(range.1), "-c:v", "libx264", "-preset", "veryfast", "-c:a", "aac", url.path],
                runner: environment.runner,
                cancellation: environment.cancellation
            )
            outputs.append(url)
        }
        return ToolRunOutcome(outputs: outputs)
    }

    func joinVideos() throws -> ToolRunOutcome {
        guard case .joinVideos(let order) = request.parameters else { throw ToolError.message("Join videos needs a list.") }
        let files = order.files.isEmpty ? request.files : order.files
        guard files.count >= 2 else { throw ToolError.message("Add at least two videos.") }
        let ffmpeg = try requireFFmpeg()
        let infos = try files.map { try probe($0) }
        let width = max(2, infos[0].width - infos[0].width % 2)
        let height = max(2, infos[0].height - infos[0].height % 2)
        let includeAudio = infos.allSatisfy(\.hasAudio)
        var arguments = ["-hide_banner", "-y"]
        for file in files {
            arguments.append(contentsOf: ["-i", file.url.path])
        }
        var filters: [String] = []
        var concat = ""
        for index in files.indices {
            filters.append("[\(index):v]scale=\(width):\(height):force_original_aspect_ratio=decrease,pad=\(width):\(height):(ow-iw)/2:(oh-ih)/2,setsar=1[v\(index)]")
            concat += "[v\(index)]"
            if includeAudio { concat += "[\(index):a]" }
        }
        if includeAudio {
            filters.append("\(concat)concat=n=\(files.count):v=1:a=1[v][a]")
        } else {
            filters.append("\(concat)concat=n=\(files.count):v=1:a=0[v]")
        }
        arguments.append(contentsOf: ["-filter_complex", filters.joined(separator: ";"), "-map", "[v]"])
        if includeAudio {
            arguments.append(contentsOf: ["-map", "[a]", "-c:a", "aac"])
        }
        arguments.append(contentsOf: ["-c:v", "libx264", "-preset", "veryfast"])
        let url = try allocate(files[0], base: "\(files[0].baseName)-joined", ext: files[0].normalizedExtension)
        arguments.append(url.path)
        try FFmpegRun.run(ffmpeg, arguments: arguments, runner: environment.runner, cancellation: environment.cancellation)
        return ToolRunOutcome(outputs: [url])
    }

    func snapshots() throws -> ToolRunOutcome {
        guard case .snapshots(let parameters) = request.parameters, let file = request.files.first else {
            throw ToolError.message("Snapshots needs one video.")
        }
        let ffmpeg = try requireFFmpeg()
        let info = try probe(file)
        let times: [Double]
        switch parameters.mode {
        case .every(let seconds):
            times = SnapshotTimes.every(seconds, duration: info.duration)
        case .count(let count):
            times = SnapshotTimes.count(count, duration: info.duration)
        }
        guard !times.isEmpty else { throw ToolError.message("The video has no duration.") }
        let prefix = freeSeriesPrefix(file, stem: "\(file.baseName)-snap")
        var outputs: [URL] = []
        for (index, time) in times.enumerated() {
            try throwIfCancelled()
            let url = try allocate(file, base: String(format: "%@-%03d", prefix, index + 1), ext: "jpg")
            let seek = min(time, max(0, info.duration - 0.05))
            try FFmpegRun.run(
                ffmpeg,
                arguments: ["-hide_banner", "-y", "-ss", String(seek), "-i", file.url.path, "-frames:v", "1", url.path],
                runner: environment.runner,
                cancellation: environment.cancellation
            )
            outputs.append(url)
        }
        return ToolRunOutcome(outputs: outputs)
    }

    func normalize() throws -> ToolRunOutcome {
        let ffmpeg = try requireFFmpeg()
        var outputs: [URL] = []
        for file in request.files {
            let url = try allocate(file, base: file.baseName, ext: file.normalizedExtension == "mp4" || file.kind == .video ? file.normalizedExtension : (file.kind == .video ? "mp4" : file.normalizedExtension))
            var arguments = ["-hide_banner", "-y", "-i", file.url.path]
            arguments.append(contentsOf: FFmpegGraphs.loudnormArguments(video: file.kind == .video))
            if file.kind == .audio {
                arguments.append(contentsOf: audioCodec(file.normalizedExtension))
            }
            arguments.append(url.path)
            try FFmpegRun.run(ffmpeg, arguments: arguments, runner: environment.runner, cancellation: environment.cancellation)
            outputs.append(url)
        }
        return ToolRunOutcome(outputs: outputs)
    }

    func bleep() throws -> ToolRunOutcome {
        guard case .bleep(var parameters) = request.parameters, let file = request.files.first else {
            throw ToolError.message("Bleep needs one audio or video file.")
        }
        var notice: String?
        let word = parameters.word.trimmingCharacters(in: .whitespacesAndNewlines)
        if !word.isEmpty {
            do {
                let found = try environment.speech.ranges(in: file.url, word: word)
                if !found.isEmpty {
                    parameters.ranges = found
                }
            } catch {
                notice = "Speech recognition failed. Mark ranges by hand."
            }
        }
        let ranges = parameters.ranges.filter(\.isValid)
        guard !ranges.isEmpty else {
            throw ToolError.message(notice ?? "Mark at least one range.")
        }
        let ffmpeg = try requireFFmpeg()
        let info = try probe(file)
        let graph = FFmpegGraphs.bleepFilter(ranges: ranges, toneHz: parameters.toneHz, duration: info.duration)
        let url = try allocate(file, base: file.baseName, ext: file.kind == .video ? file.normalizedExtension : file.normalizedExtension)
        var arguments = ["-hide_banner", "-y", "-i", file.url.path, "-filter_complex", graph, "-map", "[aout]"]
        if file.kind == .video {
            arguments.append(contentsOf: ["-map", "0:v:0", "-c:v", "copy", "-c:a", "aac"])
        } else {
            arguments.append(contentsOf: audioCodec(file.normalizedExtension))
        }
        arguments.append(url.path)
        try FFmpegRun.run(ffmpeg, arguments: arguments, runner: environment.runner, cancellation: environment.cancellation)
        return ToolRunOutcome(outputs: [url], message: notice)
    }

    func channels() throws -> ToolRunOutcome {
        guard case .channels(let mode) = request.parameters, let file = request.files.first else {
            throw ToolError.message("Channels needs one audio file.")
        }
        let ffmpeg = try requireFFmpeg()
        let url = try allocate(file, base: "\(file.baseName)-\(mode.rawValue)", ext: file.normalizedExtension)
        var arguments = ["-hide_banner", "-y", "-i", file.url.path]
        arguments.append(contentsOf: FFmpegGraphs.channelFilter(mode))
        arguments.append(contentsOf: audioCodec(file.normalizedExtension))
        arguments.append(url.path)
        try FFmpegRun.run(ffmpeg, arguments: arguments, runner: environment.runner, cancellation: environment.cancellation)
        return ToolRunOutcome(outputs: [url])
    }

    func editMetadata() throws -> ToolRunOutcome {
        guard case .editMetadata(let edit) = request.parameters else { throw ToolError.message("Edit metadata needs its fields.") }
        var outputs: [URL] = []
        for file in request.files {
            outputs.append(try writeMetadata(file, edit: edit, strip: false))
        }
        return ToolRunOutcome(outputs: outputs)
    }

    func stripMetadata() throws -> ToolRunOutcome {
        var outputs: [URL] = []
        for file in request.files {
            outputs.append(try writeMetadata(file, edit: MetadataEdit(gps: .clear), strip: true))
        }
        return ToolRunOutcome(outputs: outputs)
    }

    func mergePDFs() throws -> ToolRunOutcome {
        guard case .mergePDFs(let order) = request.parameters else { throw ToolError.message("Merge PDFs needs a list.") }
        let files = order.files.isEmpty ? request.files : order.files
        guard files.count >= 2 else { throw ToolError.message("Add at least two PDFs.") }
        var pages: [SimplePDF.Page] = []
        for file in files {
            pages.append(contentsOf: try readPDF(file).pages)
        }
        let url = try writePDF(SimplePDF(pages: pages), base: "\(files[0].baseName)-merged", source: files[0])
        return ToolRunOutcome(outputs: [url])
    }

    func splitPDF() throws -> ToolRunOutcome {
        guard case .splitPDF(let parameters) = request.parameters, let file = request.files.first else {
            throw ToolError.message("Split PDF needs one PDF.")
        }
        let document = try readPDF(file)
        var outputs: [URL] = []
        switch parameters.mode {
        case .eachPage:
            for (index, page) in document.pages.enumerated() {
                let url = try writePDF(SimplePDF(pages: [page]), base: String(format: "%@-page-%03d", file.baseName, index + 1), source: file)
                outputs.append(url)
            }
        case .ranges(let text):
            let ranges = try PageRangeParser.parse(text, pageCount: document.pages.count)
            for range in ranges {
                let pages = document.pages[(range.lowerBound - 1)..<range.upperBound]
                let label = range.lowerBound == range.upperBound ? "\(range.lowerBound)" : "\(range.lowerBound)-\(range.upperBound)"
                let url = try writePDF(SimplePDF(pages: Array(pages)), base: "\(file.baseName)-pages-\(label)", source: file)
                outputs.append(url)
            }
        }
        return ToolRunOutcome(outputs: outputs)
    }

    func reorganizePDF() throws -> ToolRunOutcome {
        guard case .reorganizePDF(let parameters) = request.parameters, let file = request.files.first else {
            throw ToolError.message("Reorganize PDF needs one PDF.")
        }
        let document = try readPDF(file)
        var pages: [SimplePDF.Page] = []
        for edit in parameters.pages where !edit.deleted {
            guard document.pages.indices.contains(edit.id) else { continue }
            var page = document.pages[edit.id]
            page.rotation = edit.rotation
            pages.append(page)
        }
        guard !pages.isEmpty else { throw ToolError.message("At least one page has to remain.") }
        let url = try writePDF(SimplePDF(pages: pages, title: document.title, author: document.author, subject: document.subject, gps: document.gps), base: file.baseName, source: file)
        return ToolRunOutcome(outputs: [url])
    }

    func imagesToPDF() throws -> ToolRunOutcome {
        guard case .imagesToPDF(let parameters) = request.parameters else { throw ToolError.message("Images to PDF needs images.") }
        let ffmpeg = try requireFFmpeg()
        var pages: [SimplePDF.Page] = []
        for file in request.files {
            let image = try decode(file)
            let temp = FileManager.default.temporaryDirectory.appendingPathComponent("filewheel-\(UUID().uuidString).jpg")
            try RasterCodec.encode(image, to: temp, format: "jpg", quality: request.settings.jpegQuality, ffmpeg: ffmpeg, runner: environment.runner, cancellation: environment.cancellation)
            let jpeg = try Data(contentsOf: temp)
            try? FileManager.default.removeItem(at: temp)
            let imageSize = FWSize(width: Double(image.width), height: Double(image.height))
            let rect = parameters.mode == .fit ? PageLayout.fit(image: imageSize, page: PageSize.usLetter) : PageLayout.fill(image: imageSize, page: PageSize.usLetter)
            pages.append(SimplePDF.Page(images: [SimplePDF.ImageObject(jpeg: jpeg, rect: rect, pixelWidth: image.width, pixelHeight: image.height)]))
        }
        let url = try writePDF(SimplePDF(pages: pages), base: request.files[0].baseName, source: request.files[0])
        return ToolRunOutcome(outputs: [url])
    }

    func collage() throws -> ToolRunOutcome {
        guard case .collage(let parameters) = request.parameters else { throw ToolError.message("Collage needs its layout.") }
        let images = try request.files.map { try decode($0) }
        let canvas = ImageOps.collage(images: images, layout: parameters.layout, gap: Int(parameters.gap), background: parameters.background)
        let url = try writeImage(canvas, like: request.files[0], quality: request.settings.jpegQuality, ext: "jpg", base: "\(request.files[0].baseName)-collage")
        return ToolRunOutcome(outputs: [url])
    }

    func readQR() throws -> ToolRunOutcome {
        guard case .readQR(let parameters) = request.parameters, let file = request.files.first else {
            throw ToolError.message("Read QR needs one image or PDF.")
        }
        let codes = try environment.qr.codes(in: file.url)
        if codes.isEmpty {
            return ToolRunOutcome(outputs: [], message: "No code found", qrCodes: [])
        }
        guard parameters.saveAsText else {
            return ToolRunOutcome(outputs: [], message: nil, qrCodes: codes)
        }
        let url = try allocate(file, base: file.baseName, ext: "txt")
        try AtomicFileWrite.commit(destination: url) { temp in
            try codes.joined(separator: "\n").data(using: .utf8)?.write(to: temp)
        }
        return ToolRunOutcome(outputs: [url], qrCodes: codes)
    }

    func extractArchive() throws -> ToolRunOutcome {
        var outputs: [URL] = []
        for file in request.files {
            let directory = try DestinationFolder.directory(for: file.url, settings: request.settings)
            switch file.normalizedExtension {
            case "zip":
                let folder = try allocate(file, base: "\(file.baseName)-extracted", ext: "")
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try runTool(environment.unzip, ["-q", "-o", file.url.path, "-d", folder.path])
                outputs.append(folder)
            case "tar", "tar.gz":
                let folder = try allocate(file, base: "\(file.baseName)-extracted", ext: "")
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try runTool(environment.tar, ["-xf", file.url.path, "-C", folder.path])
                outputs.append(folder)
            case "gz":
                let url = try allocate(file, base: file.baseName, ext: "")
                let result = try environment.runner.run(executable: environment.gzip, arguments: ["-dc", file.url.path], currentDirectory: nil, standardInput: nil, cancellation: environment.cancellation)
                guard result.status == 0 else { throw ToolError.message(ProcessText.lastUsefulLine(result.stderrText)) }
                try AtomicFileWrite.commit(destination: url) { temp in
                    try result.stdout.write(to: temp)
                }
                outputs.append(url)
            case "rar":
                guard let unar = environment.unar else {
                    throw ToolError.message(FileWheelMessages.rarBinaryMissing)
                }
                let folder = try allocate(file, base: "\(file.baseName)-extracted", ext: "")
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try runTool(unar, ["-o", folder.path, file.url.path])
                outputs.append(folder)
            default:
                throw ToolError.message("Extract does not apply to \(file.url.lastPathComponent).")
            }
            _ = directory
        }
        return ToolRunOutcome(outputs: outputs)
    }

    func packArchive() throws -> ToolRunOutcome {
        guard case .packArchive(let parameters) = request.parameters else { throw ToolError.message("Pack archive needs a format.") }
        if parameters.format == .gz {
            guard request.files.count == 1, !request.files[0].isDirectory else {
                throw ToolError.message("gz can only pack a single file.")
            }
            let file = request.files[0]
            let url = try allocate(file, base: file.baseName, ext: "gz")
            let result = try environment.runner.run(executable: environment.gzip, arguments: ["-c", "-n", file.url.path], currentDirectory: nil, standardInput: nil, cancellation: environment.cancellation)
            guard result.status == 0 else { throw ToolError.message(ProcessText.lastUsefulLine(result.stderrText)) }
            try AtomicFileWrite.commit(destination: url) { temp in
                try result.stdout.write(to: temp)
            }
            return ToolRunOutcome(outputs: [url])
        }
        let source = request.files[0]
        let staging = FileManager.default.temporaryDirectory.appendingPathComponent("filewheel-pack-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: staging) }
        for file in request.files {
            let dest = staging.appendingPathComponent(file.url.lastPathComponent)
            try FileManager.default.copyItem(at: file.url, to: dest)
        }
        let url = try allocate(source, base: source.baseName, ext: parameters.format.fileExtension)
        switch parameters.format {
        case .zip:
            try runTool(environment.zip, ["-q", "-r", url.path, "."], currentDirectory: staging)
        case .tar:
            try runTool(environment.tar, ["-cf", url.path, "-C", staging.path, "."])
        case .tarGz:
            try runTool(environment.tar, ["-czf", url.path, "-C", staging.path, "."])
        case .gz:
            break
        }
        return ToolRunOutcome(outputs: [url])
    }

    private struct CompressWrite {
        var url: URL
        var notice: String?
        var met: Bool?
    }

    private func compressImage(_ file: FileInput, _ parameters: CompressParameters) throws -> CompressWrite {
        let image = try decode(file)
        let format = outputFormat(file)
        switch parameters.mode {
        case .quality(let quality):
            let url = try writeImage(image, like: file, quality: quality, ext: format)
            return CompressWrite(url: url, notice: nil, met: nil)
        case .target(let bytes):
            let search = try searchQuality(target: bytes) { quality in
                let temp = FileManager.default.temporaryDirectory.appendingPathComponent("filewheel-\(UUID().uuidString).\(format)")
                defer { try? FileManager.default.removeItem(at: temp) }
                try RasterCodec.encode(image, to: temp, format: format, quality: quality, ffmpeg: try requireFFmpeg(), runner: environment.runner, cancellation: environment.cancellation)
                return try Data(contentsOf: temp).count
            }
            let url = try writeImage(image, like: file, quality: search.chosen.parameter, ext: format)
            return CompressWrite(url: url, notice: search.notice, met: search.metTarget)
        }
    }

    private func compressVideo(_ file: FileInput, _ parameters: CompressParameters) throws -> CompressWrite {
        let ffmpeg = try requireFFmpeg()
        let encoder = FFmpegGraphs.videoEncoder(codec: parameters.videoCodec, hardware: request.settings.hardwareEncoder, hardwareAvailable: environment.hardwareH264 && parameters.videoCodec == .h264)
        switch parameters.mode {
        case .quality(let quality):
            let crf = Int((1 - min(1, max(0, quality))) * 30 + 18)
            let url = try allocate(file, base: file.baseName, ext: file.normalizedExtension)
            try FFmpegRun.run(ffmpeg, arguments: videoArguments(file: file, url: url, encoder: encoder, extra: ["-crf", String(crf)], maxDimension: parameters.maxDimension), runner: environment.runner, cancellation: environment.cancellation)
            return CompressWrite(url: url, notice: nil, met: nil)
        case .target(let bytes):
            let search = try searchBitrate(target: bytes) { bitrate in
                let temp = FileManager.default.temporaryDirectory.appendingPathComponent("filewheel-\(UUID().uuidString).\(file.normalizedExtension)")
                defer { try? FileManager.default.removeItem(at: temp) }
                try FFmpegRun.run(ffmpeg, arguments: videoArguments(file: file, url: temp, encoder: encoder, extra: ["-b:v", String(Int(bitrate))], maxDimension: parameters.maxDimension), runner: environment.runner, cancellation: environment.cancellation)
                return try Data(contentsOf: temp).count
            }
            let url = try allocate(file, base: file.baseName, ext: file.normalizedExtension)
            try FFmpegRun.run(ffmpeg, arguments: videoArguments(file: file, url: url, encoder: encoder, extra: ["-b:v", String(Int(search.chosen.parameter))], maxDimension: parameters.maxDimension), runner: environment.runner, cancellation: environment.cancellation)
            return CompressWrite(url: url, notice: search.notice, met: search.metTarget)
        }
    }

    private func compressAudio(_ file: FileInput, _ parameters: CompressParameters) throws -> CompressWrite {
        let ffmpeg = try requireFFmpeg()
        switch parameters.mode {
        case .quality(let quality):
            let bitrate = Int(64_000 + quality * 256_000)
            let url = try transcodeAudio(file, bitrate: bitrate, ffmpeg: ffmpeg)
            return CompressWrite(url: url, notice: nil, met: nil)
        case .target(let bytes):
            let info = try probe(file)
            let search = try searchBitrate(target: bytes, low: 32_000, high: 320_000) { bitrate in
                let temp = FileManager.default.temporaryDirectory.appendingPathComponent("filewheel-\(UUID().uuidString).\(file.normalizedExtension)")
                defer { try? FileManager.default.removeItem(at: temp) }
                try FFmpegRun.run(ffmpeg, arguments: ["-hide_banner", "-y", "-i", file.url.path, "-b:a", String(Int(bitrate))] + audioEncoder(file.normalizedExtension) + [temp.path], runner: environment.runner, cancellation: environment.cancellation)
                return try Data(contentsOf: temp).count
            }
            _ = info
            let url = try transcodeAudio(file, bitrate: Int(search.chosen.parameter), ffmpeg: ffmpeg)
            return CompressWrite(url: url, notice: search.notice, met: search.metTarget)
        }
    }

    private func compressPDF(_ file: FileInput, _ parameters: CompressParameters) throws -> CompressWrite {
        let document = try readPDF(file)
        switch parameters.mode {
        case .quality:
            let url = try writePDF(document, base: file.baseName, source: file)
            return CompressWrite(url: url, notice: nil, met: nil)
        case .target(let bytes):
            let data = document.data()
            let met = data.count <= bytes
            let url = try writePDF(document, base: file.baseName, source: file)
            let notice = met ? nil : "Could not get under the target size. Kept the smallest attempt (\(data.count) bytes)."
            return CompressWrite(url: url, notice: notice, met: met)
        }
    }

    private func searchQuality(target: Int, probe: (Double) throws -> Int) throws -> CompressSearchResult {
        var thrown: Error?
        let result = CompressSearch.search(targetBytes: target) { quality in
            do {
                return try probe(quality)
            } catch {
                thrown = error
                return Int.max
            }
        }
        if let thrown { throw thrown }
        return result
    }

    private func searchBitrate(target: Int, low: Double = 100_000, high: Double = 8_000_000, probe: (Double) throws -> Int) throws -> CompressSearchResult {
        var thrown: Error?
        let result = CompressSearch.search(targetBytes: target, low: low, high: high, probe: { bitrate in
            do {
                return try probe(bitrate)
            } catch {
                thrown = error
                return Int.max
            }
        })
        if let thrown { throw thrown }
        return result
    }

    private func videoArguments(file: FileInput, url: URL, encoder: String, extra: [String], maxDimension: Int) -> [String] {
        var arguments = ["-hide_banner", "-y", "-i", file.url.path, "-vf", longEdgeFilter(maxDimension), "-c:v", encoder]
        arguments.append(contentsOf: extra)
        arguments.append(contentsOf: ["-c:a", "aac", url.path])
        return arguments
    }

    private func longEdgeFilter(_ maxDimension: Int) -> String {
        let edge = max(16, maxDimension)
        return "scale='if(gt(iw,ih),min(\(edge),iw),-2)':'if(gt(iw,ih),-2,min(\(edge),ih))'"
    }

    private func transcodeAudio(_ file: FileInput, bitrate: Int, ffmpeg: URL) throws -> URL {
        let url = try allocate(file, base: file.baseName, ext: file.normalizedExtension)
        try FFmpegRun.run(ffmpeg, arguments: ["-hide_banner", "-y", "-i", file.url.path, "-b:a", String(bitrate)] + audioEncoder(file.normalizedExtension) + [url.path], runner: environment.runner, cancellation: environment.cancellation)
        return url
    }

    private func writeMetadata(_ file: FileInput, edit: MetadataEdit, strip: Bool) throws -> URL {
        if file.normalizedExtension == "jpg" || file.normalizedExtension == "jpeg" {
            let data = try Data(contentsOf: file.url)
            let output: Data
            if strip {
                output = JPEGMetadata.strip(data)
            } else {
                var tags = JPEGMetadata.read(data) ?? JPEGTagSet()
                if !edit.title.isEmpty { tags.title = edit.title }
                if !edit.author.isEmpty { tags.author = edit.author }
                if !edit.description.isEmpty { tags.description = edit.description }
                if !edit.creationDate.isEmpty { tags.creationDate = edit.creationDate }
                switch edit.gps {
                case .unchanged:
                    break
                case .clear:
                    tags.gps = nil
                case .set(let latitude, let longitude):
                    tags.gps = GPSFix(latitude: latitude, longitude: longitude)
                }
                output = JPEGMetadata.write(data, tags: tags)
            }
            let url = try allocate(file, base: file.baseName, ext: "jpg")
            try AtomicFileWrite.commit(destination: url) { temp in
                try output.write(to: temp)
            }
            return url
        }
        if file.kind == .pdf {
            var document = try readPDF(file)
            if strip {
                document.title = ""
                document.author = ""
                document.subject = ""
                document.gps = nil
            } else {
                if !edit.title.isEmpty { document.title = edit.title }
                if !edit.author.isEmpty { document.author = edit.author }
                if !edit.description.isEmpty { document.subject = edit.description }
                switch edit.gps {
                case .unchanged:
                    break
                case .clear:
                    document.gps = nil
                case .set(let latitude, let longitude):
                    document.gps = "\(latitude),\(longitude)"
                }
            }
            return try writePDF(document, base: file.baseName, source: file)
        }
        let ffmpeg = try requireFFmpeg()
        let url = try allocate(file, base: file.baseName, ext: file.normalizedExtension)
        var arguments = ["-hide_banner", "-y", "-i", file.url.path, "-c", "copy"]
        if strip {
            arguments.append(contentsOf: ["-map_metadata", "-1"])
        } else {
            if !edit.title.isEmpty { arguments.append(contentsOf: ["-metadata", "title=\(edit.title)"]) }
            if !edit.author.isEmpty { arguments.append(contentsOf: ["-metadata", "artist=\(edit.author)"]) }
            if !edit.description.isEmpty { arguments.append(contentsOf: ["-metadata", "comment=\(edit.description)"]) }
            if !edit.creationDate.isEmpty { arguments.append(contentsOf: ["-metadata", "date=\(edit.creationDate)"]) }
            switch edit.gps {
            case .unchanged:
                break
            case .clear:
                arguments.append(contentsOf: ["-metadata", "location="])
            case .set(let latitude, let longitude):
                arguments.append(contentsOf: ["-metadata", "location=\(latitude),\(longitude)"])
            }
        }
        arguments.append(url.path)
        try FFmpegRun.run(ffmpeg, arguments: arguments, runner: environment.runner, cancellation: environment.cancellation)
        return url
    }

    private func decode(_ file: FileInput) throws -> RasterImage {
        try RasterCodec.decode(url: file.url, ffmpeg: try requireFFmpeg(), runner: environment.runner, cancellation: environment.cancellation)
    }

    private func writeImage(_ image: RasterImage, like file: FileInput, quality: Double, ext: String? = nil, base: String? = nil) throws -> URL {
        let format = ext ?? outputFormat(file)
        let url = try allocate(file, base: base ?? file.baseName, ext: format == "jpeg" ? "jpg" : format)
        try RasterCodec.encode(image, to: url, format: format, quality: quality, ffmpeg: try requireFFmpeg(), runner: environment.runner, cancellation: environment.cancellation)
        return url
    }

    private func outputFormat(_ file: FileInput) -> String {
        let ext = file.normalizedExtension
        if ["jpg", "png", "webp", "bmp", "tif", "gif"].contains(ext) {
            return ext
        }
        return "jpg"
    }

    private func readPDF(_ file: FileInput) throws -> SimplePDF {
        let data = try Data(contentsOf: file.url)
        return try SimplePDF.read(data)
    }

    private func writePDF(_ document: SimplePDF, base: String, source: FileInput) throws -> URL {
        let url = try allocate(source, base: base, ext: "pdf")
        let data = document.data()
        try AtomicFileWrite.commit(destination: url) { temp in
            try data.write(to: temp)
        }
        return url
    }

    private func probe(_ file: FileInput) throws -> MediaInfo {
        try MediaProbe.info(url: file.url, ffmpeg: try requireFFmpeg(), ffprobe: environment.ffprobe, runner: environment.runner)
    }

    private func requireFFmpeg() throws -> URL {
        guard let ffmpeg = environment.ffmpeg else { throw ToolError.message(FileWheelMessages.ffmpegMissing) }
        return ffmpeg
    }

    private func allocate(_ file: FileInput, base: String, ext: String) throws -> URL {
        try throwIfCancelled()
        let directory = try DestinationFolder.directory(for: file.url, settings: request.settings)
        let url = OutputNames.allocate(directory: directory, base: base, ext: ext, source: file.url, reserved: reserved)
        reserved.insert(url.lastPathComponent)
        return url
    }

    private func freeSeriesPrefix(_ file: FileInput, stem: String) -> String {
        let directory = (try? DestinationFolder.directory(for: file.url, settings: request.settings)) ?? file.url.deletingLastPathComponent()
        var prefix = stem
        var number = 1
        while number < 500 {
            let name = "\(prefix)-001.jpg"
            let url = directory.appendingPathComponent(name)
            if !reserved.contains(name) && !FileManager.default.fileExists(atPath: url.path) {
                return prefix
            }
            number += 1
            prefix = "\(stem) \(number)"
        }
        return stem
    }

    private func audioCodec(_ ext: String) -> [String] {
        switch ext {
        case "mp3": return ["-c:a", "libmp3lame", "-q:a", "2"]
        case "wav": return ["-c:a", "pcm_s16le"]
        case "flac": return ["-c:a", "flac"]
        case "ogg": return ["-c:a", "libvorbis"]
        case "opus": return ["-c:a", "libopus"]
        case "aiff": return ["-c:a", "pcm_s16be"]
        case "wma": return ["-c:a", "wmav2"]
        default: return ["-c:a", "aac"]
        }
    }

    private func audioEncoder(_ ext: String) -> [String] {
        switch ext {
        case "mp3": return ["-c:a", "libmp3lame"]
        default: return audioCodec(ext)
        }
    }

    private func runTool(_ executable: URL, _ arguments: [String], currentDirectory: URL? = nil) throws {
        let result = try environment.runner.run(executable: executable, arguments: arguments, currentDirectory: currentDirectory, standardInput: nil, cancellation: environment.cancellation)
        if result.status != 0 {
            throw ToolError.message(ProcessText.lastUsefulLine(result.stderrText.isEmpty ? result.stdoutText : result.stderrText))
        }
    }

    private func throwIfCancelled() throws {
        if environment.cancellation.isCancelled {
            throw ToolError.cancelled
        }
    }

    func ocrPDF() throws -> ToolRunOutcome {
        guard case .ocrPDF(let parameters) = request.parameters, let file = request.files.first else {
            throw ToolError.message("OCR PDF needs one PDF or image.")
        }
        if file.kind == .image {
            let image = try decode(file)
            let jpegURL = FileManager.default.temporaryDirectory.appendingPathComponent("filewheel-ocr-\(UUID().uuidString).jpg")
            defer { try? FileManager.default.removeItem(at: jpegURL) }
            try RasterCodec.encode(image, to: jpegURL, format: "jpg", quality: 0.9, ffmpeg: try requireFFmpeg(), runner: environment.runner, cancellation: environment.cancellation)
            let jpeg = try Data(contentsOf: jpegURL)
            let words = try OCRRecognition.words(
                recognizer: environment.textRecognizer,
                jpeg: jpeg,
                pixelWidth: image.width,
                pixelHeight: image.height,
                pageWidth: Double(image.width),
                pageHeight: Double(image.height),
                language: parameters.language
            )
            let picture = SimplePDF.ImageObject(
                jpeg: jpeg,
                rect: FWRect(x: 0, y: 0, width: Double(image.width), height: Double(image.height)),
                pixelWidth: image.width,
                pixelHeight: image.height
            )
            let spec = OCRPageSpec(
                width: Double(image.width),
                height: Double(image.height),
                extractableText: "",
                keptImages: [picture],
                recognized: words,
                force: parameters.forceOCR
            )
            let url = try writePDF(OCRTextLayer.document(pages: [spec]), base: "\(file.baseName)\(PDFToolSuffix.ocr)", source: file)
            return ToolRunOutcome(outputs: [url])
        }
        try PDFLockProbe.throwIfLocked(file.url)
        let data = try Data(contentsOf: file.url)
        if let parsed = try? SimplePDF.read(data), OCRAssembly.canBuildFromEmbeddedImages(parsed, force: parameters.forceOCR) {
            let specs = try OCRAssembly.specs(document: parsed, force: parameters.forceOCR) { image in
                try OCRRecognition.words(
                    recognizer: environment.textRecognizer,
                    jpeg: image.jpeg,
                    pixelWidth: image.pixelWidth,
                    pixelHeight: image.pixelHeight,
                    pageWidth: image.rect.width,
                    pageHeight: image.rect.height,
                    language: parameters.language
                )
            }
            let url = try writePDF(OCRTextLayer.document(pages: specs), base: "\(file.baseName)\(PDFToolSuffix.ocr)", source: file)
            return ToolRunOutcome(outputs: [url])
        }
        let url = try allocate(file, base: "\(file.baseName)\(PDFToolSuffix.ocr)", ext: "pdf")
        try OCRDocumentWriter.write(source: file.url, destination: url, parameters: parameters, recognizer: environment.textRecognizer)
        return ToolRunOutcome(outputs: [url])
    }

    func signPDF() throws -> ToolRunOutcome {
        guard case .signPDF(let parameters) = request.parameters, let file = request.files.first else {
            throw ToolError.message("Sign PDF needs one PDF.")
        }
        guard let placement = parameters.placement else {
            throw ToolError.message("Click the page to place the signature.")
        }
        guard !parameters.imageJPEG.isEmpty, parameters.pixelWidth > 0, parameters.pixelHeight > 0 else {
            throw ToolError.message("Choose a signature.")
        }
        try PDFLockProbe.throwIfLocked(file.url)
        let url = try allocate(file, base: "\(file.baseName)\(PDFToolSuffix.signed)", ext: "pdf")
        if try PDFSignatureWriter.write(source: file.url, destination: url, parameters: parameters) {
            return ToolRunOutcome(outputs: [url])
        }
        let parsed = try readPDF(file)
        guard parsed.pages.indices.contains(parameters.pageIndex) else {
            throw ToolError.message("That page is not in this PDF.")
        }
        let signature = SimplePDF.ImageObject(
            jpeg: parameters.imageJPEG,
            rect: placement.rect(),
            pixelWidth: parameters.pixelWidth,
            pixelHeight: parameters.pixelHeight,
            alpha: parameters.alpha
        )
        let edited = SignatureComposer.applying(document: parsed, pageIndex: parameters.pageIndex, signature: signature, text: parameters.text, date: parameters.date)
        try AtomicFileWrite.commit(destination: url) { temp in
            try edited.data().write(to: temp)
        }
        return ToolRunOutcome(outputs: [url])
    }

    func protectPDF() throws -> ToolRunOutcome {
        guard case .protectPDF(var parameters) = request.parameters, let file = request.files.first else {
            throw ToolError.message("Protect PDF needs one PDF.")
        }
        defer {
            PasswordMemory.clear(&parameters.password)
            PasswordMemory.clear(&parameters.confirm)
            PasswordMemory.clear(&parameters.ownerPassword)
            request.parameters = .protectPDF(parameters)
        }
        var plan = try PDFProtectionPlan.make(
            password: parameters.password,
            confirm: parameters.confirm,
            ownerPassword: parameters.ownerPassword,
            allowPrinting: parameters.allowPrinting,
            allowCopying: parameters.allowCopying
        )
        defer {
            PasswordMemory.clear(&plan.userPassword)
            PasswordMemory.clear(&plan.ownerPassword)
        }
        let url = try allocate(file, base: "\(file.baseName)\(PDFToolSuffix.protectedPDF)", ext: "pdf")
        try PDFProtector.protect(source: file.url, destination: url, plan: plan)
        return ToolRunOutcome(outputs: [url])
    }

    func unlockPDF() throws -> ToolRunOutcome {
        guard case .unlockPDF(var parameters) = request.parameters, let file = request.files.first else {
            throw ToolError.message("Unlock PDF needs one PDF.")
        }
        defer {
            PasswordMemory.clear(&parameters.password)
            request.parameters = .unlockPDF(parameters)
        }
        if parameters.password.isEmpty {
            throw ToolError.message(PDFProtectValidation.enterCurrent)
        }
        let url = try allocate(file, base: PDFToolSuffix.unlockedBase(from: file.baseName), ext: "pdf")
        try PDFProtector.unlock(source: file.url, destination: url, password: parameters.password)
        return ToolRunOutcome(outputs: [url])
    }
}
