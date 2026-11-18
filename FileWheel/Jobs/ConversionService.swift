import Foundation

/// One heavy job at a time. Phase 1's queue can call `run` directly and drop this gate.
actor SerialGate {
    private var running = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func acquire() async {
        if !running {
            running = true
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        if waiters.isEmpty {
            running = false
        } else {
            waiters.removeFirst().resume()
        }
    }
}

/// Drop handler for Phase 3 wedges. Phase 1's wheel calls `perform(urls:entry:)`.
@MainActor
final class ConversionService {
    static let shared = ConversionService()

    private let gate = SerialGate()
    private var active: Task<Void, Never>?
    private var activeToken: UUID?
    private(set) var isBusy = false

    func perform(urls: [URL], entry: Phase3Entry) {
        Task { [weak self] in
            guard let self else { return }
            await self.gate.acquire()
            let token = UUID()
            let job = Task { [weak self] in
                guard let self else { return }
                await self.execute(urls: urls, entry: entry)
            }
            self.active = job
            self.activeToken = token
            self.isBusy = true
            await job.value
            self.isBusy = false
            if self.activeToken == token {
                self.active = nil
                self.activeToken = nil
            }
            await self.gate.release()
        }
    }

    func cancelActive() {
        active?.cancel()
    }

    private func execute(urls: [URL], entry: Phase3Entry) async {
        let scopes = urls.map { url in
            (url, url.startAccessingSecurityScopedResource())
        }
        defer {
            for (url, started) in scopes where started {
                url.stopAccessingSecurityScopedResource()
            }
        }
        let settings = Phase3SettingsStore.shared
        let output = settings.output
        let fileName = urls.count == 1 ? urls[0].lastPathComponent : "\(urls.count) files"
        if entry.kind == .readAloud {
            await runReadAloud(urls: urls, fileName: fileName, settings: settings, output: output)
            return
        }
        let (model, relay) = ProgressWindow.present(fileName: fileName, action: entry.progressTitle) { [weak self] in
            self?.cancelActive()
        }
        var reserved: Set<URL> = []
        var outputs: [URL] = []
        for url in urls {
            if Task.isCancelled { break }
            let directory = output.directory(forSource: url)
            model.fileName = url.lastPathComponent
            model.message = entry.progressTitle
            do {
                let written: [URL]
                switch entry.kind {
                case .document:
                    written = try await DocumentEngine.convert(
                        source: url,
                        entry: entry,
                        destinationDirectory: directory,
                        pageSizeName: output.pageSizeName,
                        reserved: &reserved
                    )
                case .archive:
                    written = [try await ArchiveEngine.convert(
                        source: url,
                        entry: entry,
                        destinationDirectory: directory,
                        reserved: &reserved
                    )]
                case .readAloud:
                    written = []
                }
                outputs.append(contentsOf: written)
                model.addLog("\(url.lastPathComponent) done")
            } catch is CancellationError {
                break
            } catch {
                let message = (error as? FileWheelError)?.message ?? error.localizedDescription
                model.addLog("\(url.lastPathComponent): \(message)")
            }
            relay.update(message: model.message, fraction: nil)
        }
        model.outputs = outputs
        model.finished = true
        model.indeterminate = false
        model.fraction = 1
        model.message = Task.isCancelled ? "Cancelled." : (outputs.isEmpty ? "Nothing was written." : "Done")
        if output.revealInFinder, !outputs.isEmpty, !Task.isCancelled {
            model.reveal()
        }
    }

    private func runReadAloud(
        urls: [URL],
        fileName: String,
        settings: Phase3SettingsStore,
        output: OutputPreferences
    ) async {
        var configuration = settings.readAloud
        if configuration.engine == .localModel && !LocalModelSpeechEngine.isInstalled(path: configuration.localModelPath) {
            let (model, _) = ProgressWindow.present(fileName: fileName, action: "Listen (MP3)") {}
            model.message = FileWheelMessages.noLocalModel
            model.finished = true
            model.addLog(FileWheelMessages.noLocalModel)
            return
        }
        let preparation = SpeechSynthesis.prepare(urls, engine: configuration.engine)
        if preparation.files.isEmpty {
            let (model, _) = ProgressWindow.present(fileName: fileName, action: "Listen (MP3)") {}
            model.finished = true
            model.indeterminate = false
            preparation.failures.forEach { model.addLog("\($0.url.lastPathComponent): \($0.message)") }
            model.message = preparation.failures.first?.message ?? FileWheelMessages.noTextToRead
            return
        }
        if !configuration.shouldSkipConfirmPanel {
            let result = await ReadAloudConfirmPanel.ask(preparation: preparation, configuration: configuration)
            guard result.confirmed else { return }
            configuration = configuration.keepingCurrentChoice(result.keepChoice)
            settings.readAloud = configuration
        }
        let (model, relay) = ProgressWindow.present(fileName: fileName, action: "Listen (MP3)") { [weak self] in
            self?.cancelActive()
        }
        for failure in preparation.failures {
            model.addLog("\(failure.url.lastPathComponent): \(failure.message)")
        }
        let client = XAITTSClient(transport: URLSessionXAITTSTransport(), apiKey: { XAIKeychain.currentKey() })
        var reserved: Set<URL> = []
        var outputs: [URL] = []
        for file in preparation.files {
            if Task.isCancelled { break }
            model.fileName = file.url.lastPathComponent
            let directory = output.directory(forSource: file.url)
            do {
                let written = try await SpeechSynthesis.render(
                    file,
                    configuration: configuration,
                    destinationDirectory: directory,
                    client: client,
                    progress: relay,
                    reserved: &reserved
                )
                outputs.append(written)
                model.addLog("\(file.url.lastPathComponent) done")
            } catch is CancellationError {
                break
            } catch {
                let message = (error as? FileWheelError)?.message ?? error.localizedDescription
                model.addLog("\(file.url.lastPathComponent): \(message)")
                model.message = message
            }
        }
        model.outputs = outputs
        model.finished = true
        model.indeterminate = false
        model.fraction = 1
        if Task.isCancelled {
            model.message = "Cancelled."
        } else if outputs.isEmpty, let last = model.log.last {
            model.message = last.text
        } else {
            model.message = "Done"
        }
        if output.revealInFinder, !outputs.isEmpty, !Task.isCancelled {
            model.reveal()
        }
    }
}
