import AppKit
import Combine
import FileWheelKit

@MainActor
final class ConversionQueue: ObservableObject {
    struct Row: Identifiable, Equatable {
        enum Status: Equatable {
            case queued
            case running
            case success
            case failed
            case cancelled
        }

        var id: UUID
        var fileName: String
        var action: String
        var fraction: Double
        var status: Status
        var detail: String?
        var outputURL: URL?
    }

    @Published private(set) var rows: [Row] = []
    @Published private(set) var revealURLs: [URL] = []
    var onChange: (() -> Void)?

    private struct Batch {
        var rows: [Row]
        var entry: CatalogEntry
        var inputs: [URL]
        var toolParameters: ToolParameters?
    }

    private var session: FFmpegSession?
    private var pending: [Batch] = []
    private var activeCancel: ConversionCancel?
    private var pumping = false
    private var paused = false
    private var settings = FileWheelSettings.default
    var onToolOutcome: ((ToolRunOutcome) -> Void)?
    var onPasswordProtected: ((URL) -> Void)?

    var isPaused: Bool { paused }

    var queueCount: Int {
        let visible = rows.filter { $0.status == .queued || $0.status == .running }.count
        return visible + pending.reduce(0) { $0 + $1.inputs.count }
    }

    var hasRunningWork: Bool { queueCount > 0 }

    var showRevealButton: Bool {
        !revealURLs.isEmpty && !rows.contains { $0.status == .queued || $0.status == .running }
    }

    func updateSession(_ session: FFmpegSession) {
        self.session = session
    }

    func updateSettings(_ settings: FileWheelSettings) {
        self.settings = settings
        AppSettings.revealInFinder = settings.revealInFinder
        IntegratedJobs.apply(settings: settings)
    }

    func pause() {
        paused = true
        notify()
    }

    func resume() {
        paused = false
        notify()
    }

    func start(files: [URL], entry: CatalogEntry, toolParameters: ToolParameters? = nil) {
        let batch = makeBatch(files: files, entry: entry, toolParameters: toolParameters)
        if pumping {
            pending.append(batch)
            notify()
            return
        }
        begin(batch)
    }

    func recordBlocked(files: [URL], action: String, reason: String) {
        rows = files.map {
            Row(
                id: UUID(),
                fileName: $0.lastPathComponent,
                action: action,
                fraction: 1,
                status: .failed,
                detail: reason,
                outputURL: nil
            )
        }
        revealURLs = []
        notify()
    }

    func cancel(_ id: UUID) {
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
        if rows[index].status == .running {
            activeCancel?.cancel()
        } else if rows[index].status == .queued {
            rows[index].status = .cancelled
            rows[index].detail = ConversionError.cancelled.errorDescription
            rows[index].fraction = 0
            notify()
        }
    }

    func cancelAll() {
        activeCancel?.cancel()
        pending.removeAll()
        for index in rows.indices where rows[index].status == .queued {
            rows[index].status = .cancelled
            rows[index].detail = ConversionError.cancelled.errorDescription
            rows[index].fraction = 0
        }
        notify()
    }

    func reveal() {
        guard !revealURLs.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(revealURLs)
    }

    private func makeBatch(files: [URL], entry: CatalogEntry, toolParameters: ToolParameters? = nil) -> Batch {
        let rows = files.map {
            Row(
                id: UUID(),
                fileName: $0.lastPathComponent,
                action: entry.label,
                fraction: 0,
                status: .queued,
                detail: nil,
                outputURL: nil
            )
        }
        return Batch(rows: rows, entry: entry, inputs: files, toolParameters: toolParameters)
    }

    private func begin(_ batch: Batch) {
        pumping = true
        rows = batch.rows
        revealURLs = []
        let cancel = ConversionCancel()
        activeCancel = cancel
        notify()
        Task { await self.run(batch, cancel: cancel) }
    }

    private func waitWhilePaused(_ cancel: ConversionCancel) async {
        while paused && !cancel.isCancelled {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    private func run(_ batch: Batch, cancel: ConversionCancel) async {
        switch batch.entry.engine {
        case .document, .archive:
            await runEach(batch, cancel: cancel) { url in
                await IntegratedJobs.run(urls: [url], entry: batch.entry)
            }
            return
        case .readAloud:
            await runTogether(batch, cancel: cancel) {
                await IntegratedJobs.run(urls: batch.inputs, entry: batch.entry)
            }
            return
        case .tool:
            await runTogether(batch, cancel: cancel) {
                await self.runTool(batch, cancel: cancel)
            }
            return
        default:
            break
        }
        let router = EngineRouter(ffmpegURL: session?.url, imageIO: .current())
        let runner = ConversionJobRunner(router: router)
        var outputs: [URL] = []
        for index in batch.inputs.indices {
            await waitWhilePaused(cancel)
            if rows[index].status == .cancelled { continue }
            if cancel.isCancelled {
                markCancelled(from: index)
                break
            }
            rows[index].status = .running
            rows[index].fraction = 0.35
            notify()
            let url = batch.inputs[index]
            let accessed = url.startAccessingSecurityScopedResource()
            let result = await runner.run(
                ConversionRequest(inputs: [url], entry: batch.entry, options: .specDefaults),
                cancel: cancel
            )
            if accessed { url.stopAccessingSecurityScopedResource() }
            if result.cancelled || cancel.isCancelled {
                rows[index].status = .cancelled
                rows[index].detail = ConversionError.cancelled.errorDescription
                rows[index].fraction = 0
                rows[index].outputURL = nil
                markCancelled(from: index + 1)
                notify()
                break
            }
            if let output = result.outputs.first {
                rows[index].status = .success
                rows[index].fraction = 1
                rows[index].outputURL = output
                rows[index].detail = nil
                outputs.append(output)
            } else {
                rows[index].status = .failed
                rows[index].fraction = 1
                rows[index].outputURL = nil
                rows[index].detail = result.failures.first?.reason ?? "Conversion failed"
            }
            notify()
        }
        revealURLs = outputs
        if AppSettings.revealInFinder, !outputs.isEmpty {
            NSWorkspace.shared.activateFileViewerSelecting(outputs)
        }
        pumping = false
        activeCancel = nil
        notify()
        if !pending.isEmpty {
            begin(pending.removeFirst())
        }
    }

    private func runEach(
        _ batch: Batch,
        cancel: ConversionCancel,
        work: (URL) async -> BatchResult
    ) async {
        var outputs: [URL] = []
        for index in batch.inputs.indices {
            await waitWhilePaused(cancel)
            if cancel.isCancelled {
                markCancelled(from: index)
                break
            }
            rows[index].status = .running
            rows[index].fraction = 0.35
            notify()
            let url = batch.inputs[index]
            let accessed = url.startAccessingSecurityScopedResource()
            let result = await work(url)
            if accessed { url.stopAccessingSecurityScopedResource() }
            if result.cancelled || cancel.isCancelled {
                rows[index].status = .cancelled
                rows[index].detail = ConversionError.cancelled.errorDescription
                rows[index].fraction = 0
                markCancelled(from: index + 1)
                notify()
                break
            }
            if result.outputs.isEmpty, let failure = result.failures.first {
                rows[index].status = .failed
                rows[index].fraction = 1
                rows[index].detail = failure.reason
                if PasswordPrompt.shouldOfferUnlock(forFailure: failure.reason), url.pathExtension.lowercased() == "pdf" {
                    onPasswordProtected?(url)
                }
            } else {
                rows[index].status = .success
                rows[index].fraction = 1
                rows[index].outputURL = result.outputs.first
                outputs.append(contentsOf: result.outputs)
            }
            notify()
        }
        finish(outputs)
    }

    private func runTogether(
        _ batch: Batch,
        cancel: ConversionCancel,
        work: () async -> BatchResult
    ) async {
        await waitWhilePaused(cancel)
        if cancel.isCancelled {
            markCancelled(from: 0)
            finish([])
            return
        }
        for index in rows.indices {
            rows[index].status = .running
            rows[index].fraction = 0.35
        }
        notify()
        let result = await work()
        if result.cancelled || cancel.isCancelled {
            for index in rows.indices where rows[index].status == .running || rows[index].status == .queued {
                rows[index].status = .cancelled
                rows[index].detail = ConversionError.cancelled.errorDescription
                rows[index].fraction = 0
            }
            finish([])
            return
        }
        let detail = result.failures.first?.reason
        for index in rows.indices {
            if result.outputs.isEmpty && !result.failures.isEmpty {
                rows[index].status = .failed
                rows[index].detail = detail
                rows[index].fraction = 1
            } else {
                rows[index].status = .success
                rows[index].fraction = 1
                rows[index].outputURL = result.outputs.first
            }
        }
        finish(result.outputs)
    }

    private func runTool(_ batch: Batch, cancel: ConversionCancel) async -> BatchResult {
        let inputs = batch.inputs.map { MediaClassifier.classify($0) }
        guard let tool = Self.toolID(batch.entry.target) else {
            return BatchResult(outputs: [], failures: batch.inputs.map { FileFailure(source: $0, reason: "Unknown tool") }, cancelled: false)
        }
        var parameters = batch.toolParameters ?? ToolParameterDefaults.make(
            tool: tool,
            files: inputs,
            settings: settings,
            channel: Self.channel(batch.entry.target),
            pdfAccess: Self.pdfAccess(batch.entry.target)
        )
        defer { parameters = parameters.scrubbed() }
        let request = ToolRunRequest(tool: tool, files: inputs, parameters: parameters, settings: settings)
        var environment = ToolEnvironment.production()
        environment.ffmpeg = session?.url ?? environment.ffmpeg
        environment.unar = FFmpegLocator.unar() ?? environment.unar
        let outcome: ToolRunOutcome
        do {
            outcome = try await Task.detached(priority: .userInitiated) {
                try ToolExecutor.run(request, environment: environment)
            }.value
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            let suppress = batch.entry.target == "protectPDF.unlock"
            if PasswordPrompt.shouldOfferUnlock(forFailure: message, suppressForUnlockAttempt: suppress),
               let pdf = batch.inputs.first(where: { $0.pathExtension.lowercased() == "pdf" }) {
                onPasswordProtected?(pdf)
            }
            return BatchResult(outputs: [], failures: batch.inputs.map { FileFailure(source: $0, reason: message) }, cancelled: cancel.isCancelled)
        }
        if cancel.isCancelled {
            return BatchResult(outputs: [], failures: [], cancelled: true)
        }
        onToolOutcome?(outcome)
        if outcome.outputs.isEmpty && outcome.qrCodes.isEmpty {
            let message = outcome.message ?? "Nothing was written."
            return BatchResult(outputs: [], failures: batch.inputs.map { FileFailure(source: $0, reason: message) }, cancelled: false)
        }
        return BatchResult(outputs: outcome.outputs, failures: [], cancelled: false)
    }

    private static func toolID(_ target: String) -> ToolID? {
        if let tool = ToolID(rawValue: target) { return tool }
        if target.hasPrefix("channels.") { return .channels }
        if target == "ocrPDF.options" { return .ocrPDF }
        if target.hasPrefix("protectPDF.") { return .protectPDF }
        return nil
    }

    private static func channel(_ target: String) -> ChannelMode? {
        guard target.hasPrefix("channels.") else { return nil }
        return ChannelMode(rawValue: String(target.dropFirst("channels.".count)))
    }

    private static func pdfAccess(_ target: String) -> PDFLockAction? {
        guard target.hasPrefix("protectPDF.") else { return nil }
        return PDFLockAction(rawValue: String(target.dropFirst("protectPDF.".count)))
    }

    private func finish(_ outputs: [URL]) {
        revealURLs = outputs
        if AppSettings.revealInFinder, !outputs.isEmpty {
            NSWorkspace.shared.activateFileViewerSelecting(outputs)
        }
        pumping = false
        activeCancel = nil
        notify()
        if !pending.isEmpty {
            begin(pending.removeFirst())
        }
    }

    private func markCancelled(from index: Int) {
        guard index < rows.count else { return }
        for cursor in index..<rows.count where rows[cursor].status == .queued || rows[cursor].status == .running {
            rows[cursor].status = .cancelled
            rows[cursor].detail = ConversionError.cancelled.errorDescription
            rows[cursor].fraction = 0
        }
    }

    private func notify() {
        onChange?()
    }
}
