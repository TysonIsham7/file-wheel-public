import Foundation

#if canImport(SwiftUI)
import SwiftUI

public struct ToolPanelView: View {
    public var tool: ToolID
    public var files: [FileInput]
    @State private var parameters: ToolParameters
    public var onSubmit: (ToolParameters) -> Void
    public var onCancel: () -> Void

    public init(tool: ToolID, files: [FileInput], parameters: ToolParameters, onSubmit: @escaping (ToolParameters) -> Void, onCancel: @escaping () -> Void) {
        self.tool = tool
        self.files = files
        self.onSubmit = onSubmit
        self.onCancel = onCancel
        _parameters = State(initialValue: parameters)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(heading).font(.title3.weight(.semibold))
            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
            controls
            HStack {
                Button("Cancel", action: onCancel)
                Spacer()
                Button("Apply") {
                    let chosen = parameters
                    parameters = parameters.scrubbed()
                    onSubmit(chosen)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(minWidth: 360, alignment: .leading)
        .onDisappear { parameters = parameters.scrubbed() }
    }

    private var heading: String {
        if case .unlockPDF = parameters { return "Unlock PDF" }
        return tool.title
    }

    private var detail: String {
        switch parameters {
        case .unlockPDF:
            return "Writes a decrypted copy beside the original. The password is used only for this attempt and is not saved."
        case .protectPDF:
            return "Writes an encrypted copy. The password is used only for this attempt and is not saved."
        case .ocrPDF:
            return "Auto-detect is the default. Force OCR also recognizes pages that already have text. Recognition stays on this Mac."
        default:
            return tool.summary
        }
    }

    @ViewBuilder private var controls: some View {
        switch parameters {
        case .compress(let value):
            CompressPanel(value: value) { parameters = .compress($0) }
        case .cropImage(let value):
            CropImagePanel(value: value) { parameters = .cropImage($0) }
        case .adjustImage(let value):
            AdjustPanel(value: value) { parameters = .adjustImage($0) }
        case .annotate(let value):
            AnnotatePanel(value: value) { parameters = .annotate($0) }
        case .redact(let value):
            RedactPanel(value: value) { parameters = .redact($0) }
        case .trimVideo(let value), .trimAudio(let value):
            TrimPanel(value: value, filmstrip: tool == .trimVideo) {
                parameters = tool == .trimVideo ? .trimVideo($0) : .trimAudio($0)
            }
        case .cropVideo(let value):
            CropVideoPanel(value: value) { parameters = .cropVideo($0) }
        case .speed(let value):
            SpeedPanel(value: value) { parameters = .speed($0) }
        case .splitVideo(let value):
            SplitVideoPanel(value: value) { parameters = .splitVideo($0) }
        case .joinVideos(let value):
            OrderPanel(title: "Videos", value: value) { parameters = .joinVideos($0) }
        case .snapshots(let value):
            SnapshotPanel(value: value) { parameters = .snapshots($0) }
        case .bleep(let value):
            BleepPanel(value: value) { parameters = .bleep($0) }
        case .editMetadata(let value):
            MetadataPanel(value: value) { parameters = .editMetadata($0) }
        case .mergePDFs(let value):
            OrderPanel(title: "PDFs", value: value) { parameters = .mergePDFs($0) }
        case .splitPDF(let value):
            SplitPDFPanel(value: value) { parameters = .splitPDF($0) }
        case .reorganizePDF(let value):
            ReorganizePanel(value: value) { parameters = .reorganizePDF($0) }
        case .imagesToPDF(let value):
            ImagesToPDFPanel(value: value) { parameters = .imagesToPDF($0) }
        case .collage(let value):
            CollagePanel(value: value) { parameters = .collage($0) }
        case .packArchive(let value):
            PackPanel(value: value, fileCount: files.count, includesFolder: files.contains { $0.isDirectory }) {
                parameters = .packArchive($0)
            }
        case .ocrPDF(let value):
            OCROptionsPanel(value: value) { parameters = .ocrPDF($0) }
        case .signPDF(let value):
            SignPDFPanel(files: files, value: value) { parameters = .signPDF($0) }
        case .protectPDF(let value):
            ProtectPDFPanel(value: value) { parameters = .protectPDF($0) }
        case .unlockPDF(let value):
            UnlockPDFPanel(value: value) { parameters = .unlockPDF($0) }
        default:
            Text("This tool runs on drop.")
        }
    }
}

public struct QRResultPanel: View {
    public var codes: [String]
    public var onCopy: (String) -> Void
    public var onSave: () -> Void
    public var onClose: () -> Void

    public init(codes: [String], onCopy: @escaping (String) -> Void, onSave: @escaping () -> Void, onClose: @escaping () -> Void) {
        self.codes = codes
        self.onCopy = onCopy
        self.onSave = onSave
        self.onClose = onClose
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Read QR").font(.title3.weight(.semibold))
            if codes.isEmpty {
                Text("No code found")
            } else {
                ForEach(codes, id: \.self) { code in
                    HStack {
                        Text(code).textSelection(.enabled)
                        Spacer()
                        Button("Copy") { onCopy(code) }
                    }
                }
            }
            HStack {
                Button("Close", action: onClose)
                Spacer()
                if !codes.isEmpty {
                    Button("Save as TXT", action: onSave)
                }
            }
        }
        .padding(16)
        .frame(minWidth: 320, alignment: .leading)
    }
}

private struct CompressPanel: View {
    var value: CompressParameters
    var update: (CompressParameters) -> Void
    @State private var useTarget = false
    @State private var amount = "500"
    @State private var unit = "KB"

    var body: some View {
        Toggle("Target size", isOn: $useTarget)
        if useTarget {
            TextField("Size", text: $amount)
            Picker("Unit", selection: $unit) {
                Text("KB").tag("KB")
                Text("MB").tag("MB")
            }
            Button("Use this size") { applyTarget() }
        } else if case .quality(let quality) = value.mode {
            Slider(value: qualityBinding(quality), in: 0.05...1) {
                Text("Quality")
            }
        }
        if value.videoCodec == .h264 || value.videoCodec == .hevc {
            Picker("Codec", selection: codecBinding) {
                Text("H.264").tag(VideoCodecChoice.h264)
                Text("HEVC").tag(VideoCodecChoice.hevc)
            }
            Stepper("Max dimension \(value.maxDimension)", value: dimensionBinding, in: 240...4320, step: 10)
        }
    }

    private var codecBinding: Binding<VideoCodecChoice> {
        Binding { value.videoCodec } set: { codec in
            var copy = value
            copy.videoCodec = codec
            update(copy)
        }
    }

    private var dimensionBinding: Binding<Int> {
        Binding { value.maxDimension } set: { edge in
            var copy = value
            copy.maxDimension = edge
            update(copy)
        }
    }

    private func qualityBinding(_ quality: Double) -> Binding<Double> {
        Binding {
            quality
        } set: { newValue in
            var copy = value
            copy.mode = .quality(newValue)
            update(copy)
        }
    }

    private func applyTarget() {
        let number = Double(amount) ?? 0
        let multiplier = unit == "MB" ? 1_000_000.0 : 1_000.0
        var copy = value
        copy.mode = .target(bytes: Int(number * multiplier))
        update(copy)
    }
}

private struct CropImagePanel: View {
    var value: CropImageParameters
    var update: (CropImageParameters) -> Void

    var body: some View {
        Picker("Aspect", selection: Binding(get: { value.aspect }, set: { preset in
            var copy = value
            copy.aspect = preset
            if let ratio = preset.ratio, copy.rect.height > 0 {
                copy.rect.width = copy.rect.height * ratio
            }
            update(copy)
        })) {
            ForEach(AspectPreset.allCases, id: \.self) { preset in
                Text(preset.title).tag(preset)
            }
        }
        RectFields(rect: value.rect) { rect in
            var copy = value
            copy.rect = rect
            update(copy)
        }
    }
}

private struct RectFields: View {
    var rect: FWRect
    var update: (FWRect) -> Void

    var body: some View {
        TextField("X", value: field(\.x), format: .number)
        TextField("Y", value: field(\.y), format: .number)
        TextField("Width", value: field(\.width), format: .number)
        TextField("Height", value: field(\.height), format: .number)
    }

    private func field(_ keyPath: WritableKeyPath<FWRect, Double>) -> Binding<Double> {
        Binding {
            rect[keyPath: keyPath]
        } set: { newValue in
            var copy = rect
            copy[keyPath: keyPath] = newValue
            update(copy)
        }
    }
}

private struct AdjustPanel: View {
    var value: AdjustImageParameters
    var update: (AdjustImageParameters) -> Void

    var body: some View {
        slider("Exposure", value.exposure, -2...2) { copy, newValue in copy.exposure = newValue }
        slider("Contrast", value.contrast, 0...2) { copy, newValue in copy.contrast = newValue }
        slider("Saturation", value.saturation, 0...2) { copy, newValue in copy.saturation = newValue }
        slider("Sharpness", value.sharpness, 0...2) { copy, newValue in copy.sharpness = newValue }
        Picker("Rotate", selection: Binding(get: { value.rotation }, set: { rotation in
            var copy = value
            copy.rotation = rotation
            update(copy)
        })) {
            Text("0°").tag(0)
            Text("90°").tag(90)
            Text("180°").tag(180)
            Text("270°").tag(270)
        }
        Toggle("Flip horizontal", isOn: Binding(get: { value.flipHorizontal }, set: { flip in
            var copy = value
            copy.flipHorizontal = flip
            update(copy)
        }))
        Toggle("Flip vertical", isOn: Binding(get: { value.flipVertical }, set: { flip in
            var copy = value
            copy.flipVertical = flip
            update(copy)
        }))
    }

    private func slider(_ title: String, _ current: Double, _ range: ClosedRange<Double>, _ write: @escaping (inout AdjustImageParameters, Double) -> Void) -> some View {
        Slider(value: Binding(get: { current }, set: { newValue in
            var copy = value
            write(&copy, newValue)
            update(copy)
        }), in: range) { Text(title) }
    }
}

private struct AnnotatePanel: View {
    var value: AnnotateParameters
    var update: (AnnotateParameters) -> Void
    @State private var text = "Note"

    var body: some View {
        Text("Marks are flattened into the copy. \(value.marks.count) so far.")
        HStack {
            Button("Pen") {
                var copy = value
                copy.marks.append(.pen(points: [FWPoint(x: 8, y: 8), FWPoint(x: 40, y: 24)], width: 3))
                update(copy)
            }
            Button("Rectangle") {
                var copy = value
                copy.marks.append(.rectangle(FWRect(x: 10, y: 10, width: 40, height: 24), width: 2))
                update(copy)
            }
            Button("Arrow") {
                var copy = value
                copy.marks.append(.arrow(from: FWPoint(x: 8, y: 8), to: FWPoint(x: 48, y: 32)))
                update(copy)
            }
        }
        TextField("Text", text: $text)
        Button("Add text") {
            var copy = value
            copy.marks.append(.text(text, at: FWPoint(x: 8, y: 8), size: 14))
            update(copy)
        }
    }
}

private struct RedactPanel: View {
    var value: RedactParameters
    var update: (RedactParameters) -> Void

    var body: some View {
        Text("Black boxes. On a PDF, text under a box is removed from the new file.")
        Button("Add box") {
            var copy = value
            copy.boxes.append(RedactBox(pageIndex: 0, rect: FWRect(x: 40, y: 40, width: 120, height: 36)))
            update(copy)
        }
        ForEach(Array(value.boxes.enumerated()), id: \.offset) { index, box in
            Text("Page \(box.pageIndex + 1): \(Int(box.rect.x)), \(Int(box.rect.y)), \(Int(box.rect.width))×\(Int(box.rect.height))")
            Button("Remove") {
                var copy = value
                copy.boxes.remove(at: index)
                update(copy)
            }
        }
    }
}

private struct TrimPanel: View {
    var value: TrimParameters
    var filmstrip: Bool
    var update: (TrimParameters) -> Void

    var body: some View {
        Text(filmstrip ? "Filmstrip in and out." : "Waveform in and out.")
        TextField("In", value: Binding(get: { value.start }, set: { start in
            var copy = value
            copy.start = start
            update(copy)
        }), format: .number)
        TextField("Out", value: Binding(get: { value.end }, set: { end in
            var copy = value
            copy.end = end
            update(copy)
        }), format: .number)
    }
}

private struct CropVideoPanel: View {
    var value: CropVideoParameters
    var update: (CropVideoParameters) -> Void

    var body: some View {
        Text("The rectangle is applied to the whole duration.")
        RectFields(rect: value.rect) { rect in
            update(CropVideoParameters(rect: rect))
        }
    }
}

private struct SpeedPanel: View {
    var value: SpeedParameters
    var update: (SpeedParameters) -> Void
    @State private var custom = "1.25"

    var body: some View {
        ForEach(SpeedRate.presets, id: \.self) { rate in
            Button("\(rate, format: .number)×") { update(SpeedParameters(rate: .preset(rate))) }
        }
        TextField("Custom rate", text: $custom)
        Button("Use custom rate") {
            if let rate = Double(custom), rate > 0 {
                update(SpeedParameters(rate: .custom(rate)))
            }
        }
        Text("Audio pitch stays natural.")
            .font(.caption)
    }
}

private struct SplitVideoPanel: View {
    var value: SplitVideoParameters
    var update: (SplitVideoParameters) -> Void
    @State private var playhead = "1"
    @State private var parts = "2"

    var body: some View {
        TextField("Playhead seconds", text: $playhead)
        Button("Split at playhead") {
            if let time = Double(playhead) { update(SplitVideoParameters(mode: .playhead(time))) }
        }
        TextField("Equal parts", text: $parts)
        Button("Split into equal parts") {
            if let count = Int(parts) { update(SplitVideoParameters(mode: .equalParts(count))) }
        }
    }
}

private struct OrderPanel: View {
    var title: String
    var value: OrderedInputs
    var update: (OrderedInputs) -> Void

    var body: some View {
        Text(title)
        ForEach(Array(value.files.enumerated()), id: \.offset) { index, file in
            HStack {
                Text(file.url.lastPathComponent)
                Spacer()
                if index > 0 {
                    Button("Up") { move(index, -1) }
                }
            }
        }
        Text("Mixed video sizes scale to the first clip.")
            .font(.caption)
    }

    private func move(_ index: Int, _ delta: Int) {
        var files = value.files
        let target = index + delta
        guard files.indices.contains(target) else { return }
        files.swapAt(index, target)
        update(OrderedInputs(files: files))
    }
}

private struct SnapshotPanel: View {
    var value: SnapshotParameters
    var update: (SnapshotParameters) -> Void
    @State private var seconds = "1"
    @State private var count = "3"

    var body: some View {
        TextField("Every N seconds", text: $seconds)
        Button("Every N seconds") {
            if let seconds = Double(seconds) { update(SnapshotParameters(mode: .every(seconds: seconds))) }
        }
        TextField("Count", text: $count)
        Button("Spread a count") {
            if let count = Int(count) { update(SnapshotParameters(mode: .count(count))) }
        }
        Text("Files are named Name-snap-001.jpg.")
            .font(.caption)
    }
}

private struct BleepPanel: View {
    var value: BleepParameters
    var update: (BleepParameters) -> Void
    @State private var word = ""
    @State private var start = "0"
    @State private var end = "0.2"

    var body: some View {
        TextField("Word search", text: $word)
            .onChange(of: word) { newValue in
                var copy = value
                copy.word = newValue
                update(copy)
            }
        Text("If recognition fails, mark the ranges by hand.")
            .font(.caption)
        TextField("Start", text: $start)
        TextField("End", text: $end)
        Button("Add range") {
            guard let start = Double(start), let end = Double(end) else { return }
            var copy = value
            copy.ranges.append(TimeRange(start: start, end: end))
            copy.word = word
            update(copy)
        }
        ForEach(Array(value.ranges.enumerated()), id: \.offset) { _, range in
            Text("\(range.start, format: .number)–\(range.end, format: .number)s")
        }
    }
}

private struct MetadataPanel: View {
    var value: MetadataEdit
    var update: (MetadataEdit) -> Void

    var body: some View {
        field("Title", value.title) { $0.title = $1 }
        field("Author", value.author) { $0.author = $1 }
        field("Description", value.description) { $0.description = $1 }
        field("Creation date", value.creationDate) { $0.creationDate = $1 }
        Button("Clear GPS") {
            var copy = value
            copy.gps = .clear
            update(copy)
        }
        if !value.readOnlyTags.isEmpty {
            Text("Read only")
                .font(.caption)
            ForEach(value.readOnlyTags.keys.sorted(), id: \.self) { key in
                Text("\(key): \(value.readOnlyTags[key] ?? "")")
                    .font(.caption)
            }
        }
    }

    private func field(_ title: String, _ current: String, _ write: @escaping (inout MetadataEdit, String) -> Void) -> some View {
        TextField(title, text: Binding(get: { current }, set: { newValue in
            var copy = value
            write(&copy, newValue)
            update(copy)
        }))
    }
}

private struct SplitPDFPanel: View {
    var value: SplitPDFParameters
    var update: (SplitPDFParameters) -> Void
    @State private var ranges = "1-2"

    var body: some View {
        TextField("Page ranges", text: $ranges)
        Button("Split ranges") { update(SplitPDFParameters(mode: .ranges(ranges))) }
        Button("One file per page") { update(SplitPDFParameters(mode: .eachPage)) }
    }
}

private struct ReorganizePanel: View {
    var value: ReorganizeParameters
    var update: (ReorganizeParameters) -> Void

    var body: some View {
        ForEach(Array(value.pages.enumerated()), id: \.element.id) { index, page in
            HStack {
                Text("Page \(page.id + 1)")
                if page.deleted {
                    Text("Deleted").foregroundStyle(.secondary)
                }
                Button("Rotate") {
                    var pages = value.pages
                    pages[index].rotation = (pages[index].rotation + 90) % 360
                    update(ReorganizeParameters(pages: pages))
                }
                Button(page.deleted ? "Restore" : "Delete") {
                    var pages = value.pages
                    pages[index].deleted.toggle()
                    update(ReorganizeParameters(pages: pages))
                }
                if index > 0 {
                    Button("Up") {
                        var pages = value.pages
                        pages.swapAt(index, index - 1)
                        update(ReorganizeParameters(pages: pages))
                    }
                }
            }
        }
    }
}

private struct ImagesToPDFPanel: View {
    var value: ImagesToPDFParameters
    var update: (ImagesToPDFParameters) -> Void

    var body: some View {
        Text("Order follows the drag. A drop fits each image on the page.")
        Picker("Page", selection: Binding(get: { value.mode }, set: { mode in
            update(ImagesToPDFParameters(mode: mode))
        })) {
            ForEach(PDFFitMode.allCases, id: \.self) { mode in
                Text(mode.title).tag(mode)
            }
        }
    }
}

private struct CollagePanel: View {
    var value: CollageParameters
    var update: (CollageParameters) -> Void

    var body: some View {
        Picker("Layout", selection: Binding(get: { value.layout }, set: { layout in
            var copy = value
            copy.layout = layout
            update(copy)
        })) {
            ForEach(CollageLayout.allCases, id: \.self) { layout in
                Text(layout.title).tag(layout)
            }
        }
        Stepper("Gap \(Int(value.gap))", value: Binding(get: { value.gap }, set: { gap in
            var copy = value
            copy.gap = gap
            update(copy)
        }), in: 0...80)
    }
}

private struct PackPanel: View {
    var value: PackParameters
    var fileCount: Int
    var includesFolder: Bool
    var update: (PackParameters) -> Void

    var body: some View {
        Picker("Format", selection: Binding(get: { value.format }, set: { format in
            update(PackParameters(format: format))
        })) {
            ForEach(ArchiveFormat.allCases, id: \.self) { format in
                Text(format.title).tag(format)
            }
        }
        if value.format == .gz && (fileCount != 1 || includesFolder) {
            Text("gz can only pack a single file.")
                .foregroundStyle(.red)
        }
    }
}
#endif
