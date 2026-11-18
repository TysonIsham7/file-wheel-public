import Foundation

#if canImport(SwiftUI)
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

struct OCROptionsPanel: View {
    var value: OCRParameters
    var update: (OCRParameters) -> Void

    var body: some View {
        Picker("Language", selection: Binding(get: { value.language }, set: { language in
            var copy = value
            copy.language = language
            update(copy)
        })) {
            ForEach(OCRLanguage.choices) { choice in
                Text(choice.title).tag(choice.id)
            }
        }
        Toggle("Force OCR", isOn: Binding(get: { value.forceOCR }, set: { force in
            var copy = value
            copy.forceOCR = force
            update(copy)
        }))
        Text("A drop uses auto-detect and skips a page that already has more than 20 characters of extractable text. Recognition stays on this Mac. Nothing is sent.")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

struct ProtectPDFPanel: View {
    var value: ProtectPDFParameters
    var update: (ProtectPDFParameters) -> Void

    var body: some View {
        SecureField("Password", text: binding(\.password))
        SecureField("Confirm password", text: binding(\.confirm))
        SecureField("Owner password (optional)", text: binding(\.ownerPassword))
        Toggle("Allow printing", isOn: binding(\.allowPrinting))
        Toggle("Allow copying", isOn: binding(\.allowCopying))
        Text("Leave the owner password empty to use the same password. It is kept in memory for this attempt only and is not saved or logged. The copy uses AES-256 when this Mac can write it.")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private func binding(_ keyPath: WritableKeyPath<ProtectPDFParameters, String>) -> Binding<String> {
        Binding(get: { value[keyPath: keyPath] }, set: { newValue in
            var copy = value
            copy[keyPath: keyPath] = newValue
            update(copy)
        })
    }

    private func binding(_ keyPath: WritableKeyPath<ProtectPDFParameters, Bool>) -> Binding<Bool> {
        Binding(get: { value[keyPath: keyPath] }, set: { newValue in
            var copy = value
            copy[keyPath: keyPath] = newValue
            update(copy)
        })
    }
}

struct UnlockPDFPanel: View {
    var value: UnlockPDFParameters
    var update: (UnlockPDFParameters) -> Void

    var body: some View {
        SecureField("Current password", text: Binding(get: { value.password }, set: { password in
            var copy = value
            copy.password = password
            update(copy)
        }))
        Text("The password is used only to write the unlocked copy. It is not saved or logged.")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

struct SignPDFPanel: View {
    var files: [FileInput]
    var value: SignPDFParameters
    var update: (SignPDFParameters) -> Void

    @State private var pages: [PDFPageMetrics] = []
    @State private var strokes: [SignatureStroke] = []
    @State private var activeStroke = false
    @State private var typed = ""
    @State private var signatureName = "Signature"
    @State private var saved: [SavedSignature] = []
    @State private var baseSize = FWSize(width: 180, height: 60)
    @State private var scale = 1.0
    @State private var notice = ""
    @State private var pngForStore: Data?
    @State private var importing = false
    @State private var padSize = CGSize(width: 420, height: 120)

    private var pageSize: FWSize {
        let index = min(max(0, value.pageIndex), max(0, pages.count - 1))
        if pages.indices.contains(index) {
            return pages[index].size
        }
        return PageSize.usLetter
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("This is a visual signature drawn on the page. It is not a cryptographic digital signature.")
                    .font(.callout)
                if !notice.isEmpty {
                    Text(notice)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Text("Saved signatures")
                    .font(.headline)
                if saved.isEmpty {
                    Text("Saved signatures stay in Application Support on this Mac.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(saved) { signature in
                        HStack {
                            Text(signature.name)
                            Spacer()
                            Button("Use") { useSaved(signature) }
                            Button("Delete") { deleteSaved(signature) }
                        }
                    }
                }
                Text("Draw")
                    .font(.headline)
                signaturePad
                HStack {
                    Button("Clear drawing") {
                        strokes = []
                    }
                    Button("Use this drawing") { useDrawing(size: padSize) }
                }
                Text("Type")
                    .font(.headline)
                TextField("Typed signature", text: $typed)
                    .font(.system(size: 28, design: .serif).italic())
                Button("Use typed signature") { useTyped() }
                Button("Import image") { importing = true }
                Text("An imported image has its near-white background removed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Name for Save", text: $signatureName)
                Button("Save signature") { saveCurrent() }
                Text("Place")
                    .font(.headline)
                if pages.count > 1 {
                    Stepper("Page \(value.pageIndex + 1) of \(pages.count)", value: Binding(get: { value.pageIndex }, set: { index in
                        var copy = value
                        copy.pageIndex = index
                        copy.placement = nil
                        update(copy)
                    }), in: 0...max(0, pages.count - 1))
                } else {
                    Text("Page 1")
                        .font(.caption)
                }
                Text("Click the page to place the signature, then resize it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                placementPad
                if value.placement != nil {
                    Slider(value: Binding(get: { scale }, set: { newValue in
                        scale = newValue
                        resize(to: newValue)
                    }), in: 0.25...3) {
                        Text("Size")
                    }
                }
                TextField("Text", text: Binding(get: { value.text }, set: { text in
                    var copy = value
                    copy.text = text
                    update(copy)
                }))
                Toggle("Add today's date", isOn: Binding(get: { !value.date.isEmpty }, set: { include in
                    var copy = value
                    copy.date = include ? Self.today() : ""
                    update(copy)
                }))
                if !value.date.isEmpty {
                    Text(value.date)
                        .font(.caption)
                }
            }
        }
        .frame(maxHeight: 560)
        .onAppear {
            loadPages()
            reloadSaved()
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.png, .jpeg, .tiff, .heic]) { result in
            importImage(result)
        }
    }

    private var signaturePad: some View {
        GeometryReader { geo in
            Canvas { context, _ in
                for stroke in strokes {
                    var path = Path()
                    guard let first = stroke.points.first else { continue }
                    path.move(to: CGPoint(x: first.x, y: first.y))
                    for point in stroke.points.dropFirst() {
                        path.addLine(to: CGPoint(x: point.x, y: point.y))
                    }
                    context.stroke(path, with: .color(.black), lineWidth: 2)
                }
            }
            .background(Color.white)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary))
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                let point = FWPoint(x: value.location.x, y: value.location.y)
                if !activeStroke {
                    strokes.append(SignatureStroke(points: [point]))
                    activeStroke = true
                } else if !strokes.isEmpty {
                    strokes[strokes.count - 1].points.append(point)
                }
                padSize = geo.size
            }.onEnded { _ in
                activeStroke = false
                padSize = geo.size
                useDrawing(size: geo.size)
            })
        }
        .frame(height: 120)
    }

    private var placementPad: some View {
        GeometryReader { geo in
            let viewSize = FWSize(width: geo.size.width, height: geo.size.height)
            Canvas { context, _ in
                let page = CGRect(x: 1, y: 1, width: max(1, geo.size.width - 2), height: max(1, geo.size.height - 2))
                context.fill(Path(page), with: .color(.white.opacity(0.9)))
                context.stroke(Path(page), with: .color(.gray), lineWidth: 1)
                if let placement = value.placement {
                    let mapped = SignaturePlacementMath.viewRect(placement.rect(), page: pageSize, view: viewSize)
                    let mark = CGRect(x: mapped.x, y: mapped.y, width: max(1, mapped.width), height: max(1, mapped.height))
                    context.stroke(Path(mark), with: .color(.blue), lineWidth: 1.5)
                }
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onEnded { value in
                let point = SignaturePlacementMath.pagePoint(
                    viewPoint: FWPoint(x: value.location.x, y: value.location.y),
                    viewSize: viewSize,
                    pageSize: pageSize
                )
                var copy = self.value
                let placed = SignatureTransform.placing(click: point, baseSize: baseSize, page: pageSize)
                copy.placement = placed
                scale = placed.scale
                update(copy)
            })
        }
        .frame(height: 200)
    }

    private func loadPages() {
        guard let file = files.first, let data = try? Data(contentsOf: file.url) else {
            notice = "Could not read this PDF."
            return
        }
        if PDFLockProbe.looksEncrypted(data) {
            notice = ToolError.passwordProtected.message
            return
        }
        if let parsed = try? SimplePDF.read(data), !parsed.pages.isEmpty {
            pages = parsed.pages.map { PDFPageMetrics(width: $0.width, height: $0.height) }
            return
        }
        if let document = PDFDocument(data: data), !document.isLocked, document.pageCount > 0 {
            pages = (0..<document.pageCount).compactMap { index in
                guard let page = document.page(at: index) else { return nil }
                let bounds = page.bounds(for: .mediaBox)
                return PDFPageMetrics(width: bounds.width, height: bounds.height)
            }
        }
    }

    private func reloadSaved() {
        saved = (try? SignatureStore(directory: SignatureStore.applicationSupportDirectory()).load()) ?? []
    }

    private func useDrawing(size: CGSize) {
        let bitmap = SignatureEncoding.bitmap(strokes: strokes, width: Int(size.width), height: Int(size.height))
        guard strokes.contains(where: { !$0.points.isEmpty }) else {
            notice = "Draw a signature first."
            return
        }
        apply(bitmap)
    }

    private func useTyped() {
        guard let bitmap = SignatureEncoding.bitmap(text: typed) else {
            notice = "Type a signature first."
            return
        }
        apply(bitmap)
    }

    private func useSaved(_ signature: SavedSignature) {
        do {
            let bitmap = try SignatureEncoding.bitmap(imageData: signature.png)
            apply(bitmap)
            signatureName = signature.name
        } catch let error as ToolError {
            notice = error.message
        } catch {
            notice = "Could not read that signature."
        }
    }

    private func deleteSaved(_ signature: SavedSignature) {
        let store = SignatureStore(directory: SignatureStore.applicationSupportDirectory())
        try? store.delete(id: signature.id)
        reloadSaved()
    }

    private func saveCurrent() {
        guard let png = pngForStore else {
            notice = "Draw, type, or import a signature first."
            return
        }
        let signature = SavedSignature(id: UUID(), name: signatureName, png: png)
        do {
            try SignatureStore(directory: SignatureStore.applicationSupportDirectory()).save(signature)
            reloadSaved()
            notice = ""
        } catch let error as ToolError {
            notice = error.message
        } catch {
            notice = "Could not save the signature."
        }
    }

    private func importImage(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else {
            notice = "Could not read that image."
            return
        }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else {
            notice = "Could not read that image."
            return
        }
        do {
            var bitmap = try SignatureEncoding.bitmap(imageData: data)
            SignatureBackground.removeNearWhite(&bitmap.rgba)
            apply(bitmap)
        } catch let error as ToolError {
            notice = error.message
        } catch {
            notice = "Could not read that image."
        }
    }

    private func apply(_ bitmap: SignatureBitmap) {
        do {
            let prepared = try SignatureEncoding.prepare(bitmap)
            let aspect = Double(prepared.pixelHeight) / Double(max(1, prepared.pixelWidth))
            baseSize = FWSize(width: 180, height: max(24, 180 * aspect))
            var copy = value
            copy.imageJPEG = prepared.jpeg
            copy.alpha = prepared.alpha
            copy.pixelWidth = prepared.pixelWidth
            copy.pixelHeight = prepared.pixelHeight
            pngForStore = prepared.png
            if let placement = copy.placement {
                let adjusted = placement.replacingBaseSize(baseSize, page: pageSize)
                copy.placement = adjusted
                scale = adjusted.scale
            }
            update(copy)
            notice = ""
        } catch let error as ToolError {
            notice = error.message
        } catch {
            notice = "Could not prepare the signature image."
        }
    }

    private func resize(to newScale: Double) {
        guard let placement = value.placement else { return }
        var copy = value
        let adjusted = placement.scaled(to: newScale, page: pageSize)
        copy.placement = adjusted
        scale = adjusted.scale
        update(copy)
    }

    private static func today() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}

private struct PDFPageMetrics: Equatable {
    var width: Double
    var height: Double
    var size: FWSize { FWSize(width: width, height: height) }
}
#endif
