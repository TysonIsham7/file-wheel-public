import Foundation

/// Runs a Phase 3 document, archive, or Listen wedge selected from the Phase 2 catalog.
@MainActor
public enum IntegratedJobs {
    public static func run(urls: [URL], entry: CatalogEntry) async -> BatchResult {
        switch entry.engine {
        case .readAloud:
            return await readAloud(urls)
        case .document, .archive:
            return await convert(urls: urls, entry: entry)
        default:
            return BatchResult(outputs: [], failures: [FileFailure(source: urls.first ?? URL(fileURLWithPath: "/"), reason: "This action is not a document or archive conversion.")], cancelled: false)
        }
    }

    public static func apply(settings: FileWheelSettings) {
        let store = Phase3SettingsStore.shared
        let folder: String
        let mode: OutputMode
        switch settings.output {
        case .besideOriginal:
            mode = .besideSource
            folder = ""
        case .folder(let path):
            mode = .folder
            folder = path
        }
        store.output = OutputPreferences(
            mode: mode,
            folderPath: folder,
            revealInFinder: settings.revealInFinder,
            pageSizeName: "letter"
        )
        var configuration = store.readAloud
        switch settings.readAloud.engine {
        case .xai:
            configuration.engine = .xai
        case .macOS:
            configuration.engine = .macos
        case .localModel:
            configuration.engine = .localModel
        }
        configuration.voiceID = settings.readAloud.voiceID
        configuration.language = settings.readAloud.language
        configuration.speed = settings.readAloud.speed
        configuration.macOSVoiceIdentifier = settings.readAloud.macOSVoiceIdentifier
        configuration.localModelPath = settings.readAloud.localModelIdentifier ?? ""
        configuration.keepChoice = settings.readAloud.keepChoice
        store.readAloud = configuration
    }

    private static func phase3ID(_ entry: CatalogEntry) -> String {
        if entry.engine == .readAloud { return "listen.mp3" }
        return "\(entry.source).\(entry.target)"
    }

    private static func convert(urls: [URL], entry: CatalogEntry) async -> BatchResult {
        let identifier = phase3ID(entry)
        guard let phase = Phase3Catalog.entries.first(where: { $0.id == identifier }) ?? packEntry(entry) else {
            return BatchResult(outputs: [], failures: urls.map { FileFailure(source: $0, reason: "This conversion is not available.") }, cancelled: false)
        }
        let output = Phase3SettingsStore.shared.output
        var reserved: Set<URL> = []
        var outputs: [URL] = []
        var failures: [FileFailure] = []
        for url in urls {
            let directory = output.directory(forSource: url)
            do {
                switch phase.kind {
                case .document:
                    outputs += try await DocumentEngine.convert(
                        source: url,
                        entry: phase,
                        destinationDirectory: directory,
                        pageSizeName: output.pageSizeName,
                        reserved: &reserved
                    )
                case .archive:
                    outputs.append(try await ArchiveEngine.convert(
                        source: url,
                        entry: phase,
                        destinationDirectory: directory,
                        reserved: &reserved
                    ))
                case .readAloud:
                    break
                }
            } catch is CancellationError {
                return BatchResult(outputs: outputs, failures: failures, cancelled: true)
            } catch {
                let message = (error as? FileWheelError)?.message ?? error.localizedDescription
                failures.append(FileFailure(source: url, reason: message))
            }
        }
        return BatchResult(outputs: outputs, failures: failures, cancelled: false)
    }

    private static func packEntry(_ entry: CatalogEntry) -> Phase3Entry? {
        guard entry.source == "pack" else { return nil }
        return Phase3Catalog.entries.first { $0.id == "pack.\(entry.target)" }
    }

    private static func readAloud(_ urls: [URL]) async -> BatchResult {
        let settings = Phase3SettingsStore.shared
        var configuration = settings.readAloud
        if configuration.engine == .localModel && !LocalModelSpeechEngine.isInstalled(path: configuration.localModelPath) {
            return BatchResult(outputs: [], failures: urls.map { FileFailure(source: $0, reason: FileWheelMessages.noLocalModel) }, cancelled: false)
        }
        let preparation = SpeechSynthesis.prepare(urls, engine: configuration.engine)
        var failures = preparation.failures.map { FileFailure(source: $0.url, reason: $0.message) }
        if preparation.files.isEmpty {
            if failures.isEmpty {
                failures = urls.map { FileFailure(source: $0, reason: FileWheelMessages.noTextToRead) }
            }
            return BatchResult(outputs: [], failures: failures, cancelled: false)
        }
        if !configuration.shouldSkipConfirmPanel {
            let result = await ReadAloudConfirmPanel.ask(preparation: preparation, configuration: configuration)
            guard result.confirmed else {
                return BatchResult(outputs: [], failures: [], cancelled: true)
            }
            configuration = configuration.keepingCurrentChoice(result.keepChoice)
            settings.readAloud = configuration
        }
        let client = XAITTSClient(transport: URLSessionXAITTSTransport(), apiKey: { XAIKeychain.currentKey() })
        let output = settings.output
        var reserved: Set<URL> = []
        var outputs: [URL] = []
        for file in preparation.files {
            if Task.isCancelled {
                return BatchResult(outputs: outputs, failures: failures, cancelled: true)
            }
            let directory = output.directory(forSource: file.url)
            do {
                let written = try await SpeechSynthesis.render(
                    file,
                    configuration: configuration,
                    destinationDirectory: directory,
                    client: client,
                    progress: nil,
                    reserved: &reserved
                )
                outputs.append(written)
            } catch is CancellationError {
                return BatchResult(outputs: outputs, failures: failures, cancelled: true)
            } catch {
                let message = (error as? FileWheelError)?.message ?? error.localizedDescription
                failures.append(FileFailure(source: file.url, reason: message))
            }
        }
        return BatchResult(outputs: outputs, failures: failures, cancelled: false)
    }
}
