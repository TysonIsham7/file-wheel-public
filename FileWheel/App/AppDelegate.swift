import AppKit
import FileWheelKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static let shared = AppDelegate()

    private let queue = ConversionQueue()
    private let drag = DragMonitor()
    private let settingsStore = JSONSettingsStore(fileURL: JSONSettingsStore.applicationSupportURL())
    private let apiKeys = LayeredAPIKeyStore(primary: KeychainAPIKeyStore())
    private let loginItem = MacLoginItem()
    private let services = ServicesProvider()
    private var status: StatusItemController?
    private var progress: ProgressWindowController?
    private var about: AboutPanel?
    private var report: CapabilityReport?
    private var aboutContent: AboutContent?
    private var session: FFmpegSession?
    private var settings = FileWheelSettings.default
    private var settingsPanel: NSPanel?
    private var toolPanel: NSPanel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let progress = ProgressWindowController(queue: queue)
        let about = AboutPanel()
        drag.environment = { [weak self] in
            WheelEnvironment(
                capabilities: self?.session?.capabilities ?? .missing,
                imageIO: .current(),
                ffmpegURL: self?.session?.url
            )
        }
        settings = settingsStore.load()
        queue.updateSettings(settings)
        queue.onToolOutcome = { [weak self] outcome in
            guard !outcome.qrCodes.isEmpty else { return }
            self?.showQR(outcome.qrCodes)
        }
        queue.onPasswordProtected = { [weak self] url in
            self?.offerUnlock(for: url)
        }
        services.presenter = SelectionPresenter(drag: drag)
        NSApp.servicesProvider = services
        drag.onConvert = { [weak self] urls, entry in
            self?.begin(urls: urls, entry: entry)
        }
        drag.onBlocked = { [weak self] urls, action, reason in
            self?.queue.recordBlocked(files: urls, action: action, reason: reason)
            self?.progress?.show()
        }
        let status = StatusItemController(
            queue: queue,
            onConvertSelection: { [weak self] in self?.convertSelection() },
            onShowQueue: { [weak progress] in progress?.show() },
            onAbout: { [weak self] in self?.about?.show(report: self?.report, content: self?.aboutContent) },
            onTogglePause: { [weak self] in self?.togglePause() },
            onSettings: { [weak self] in self?.showSettings() }
        )
        status.install()
        drag.start()
        self.progress = progress
        self.about = about
        self.status = status
        Task {
            let session = await FFmpegSession.launch()
            let merged = CapabilityReportBuilder.make(
                entries: ConversionCatalog.wheelEntries,
                capabilities: session.capabilities,
                imageIO: .current()
            )
            let check = FFmpegLocator.check(executable: session.url, runner: FoundationCommandRunner())
            let capabilities = EngineCapabilities(
                canEncodeWMA: session.capabilities.hasEncoder("wmav1") || session.capabilities.hasEncoder("wmav2"),
                canExtractRAR: FFmpegLocator.unar() != nil,
                ffmpegVersion: check.foundVersion
            )
            let content = AboutContent.make(capabilities: capabilities, ffmpeg: check)
            await MainActor.run {
                self.session = session
                self.report = merged
                self.aboutContent = content
                self.queue.updateSession(session)
            }
        }
    }

    private func begin(urls: [URL], entry: CatalogEntry) {
        if entry.engine == .tool, let tool = toolID(entry.target) {
            let inputs = urls.map { MediaClassifier.classify($0) }
            let presentation = self.presentation(for: entry.target, tool: tool, files: inputs)
            if presentation == .openPanel {
                let parameters = ToolParameterDefaults.make(
                    tool: tool,
                    files: inputs,
                    settings: settings,
                    channel: channel(entry.target),
                    pdfAccess: pdfAccess(entry.target)
                )
                let view = ToolPanelView(tool: tool, files: inputs, parameters: parameters, onSubmit: { [weak self] chosen in
                    self?.toolPanel?.close()
                    self?.queue.start(files: urls, entry: entry, toolParameters: chosen)
                    self?.progress?.show()
                }, onCancel: { [weak self] in
                    self?.toolPanel?.close()
                })
                let title = pdfAccess(entry.target)?.title ?? tool.title
                toolPanel = host(title: title, view: AnyView(view), size: panelSize(for: tool))
                return
            }
        }
        queue.start(files: urls, entry: entry)
        progress?.show()
    }

    private func togglePause() {
        if queue.isPaused {
            queue.resume()
        } else {
            queue.pause()
        }
    }

    private func showSettings() {
        let view = SettingsView(store: settingsStore, keys: apiKeys, login: loginItem) { [weak self] updated in
            self?.settings = updated
            self?.queue.updateSettings(updated)
        }
        settingsPanel = host(title: "Settings", view: AnyView(view), size: NSSize(width: 480, height: 640))
    }

    private func host(title: String, view: AnyView, size: NSSize) -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        panel.title = title
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.contentView = NSHostingView(rootView: view)
        panel.center()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        return panel
    }

    private func toolID(_ target: String) -> ToolID? {
        if let tool = ToolID(rawValue: target) { return tool }
        if target.hasPrefix("channels.") { return .channels }
        if target == "ocrPDF.options" { return .ocrPDF }
        if target.hasPrefix("protectPDF.") { return .protectPDF }
        return nil
    }

    private func channel(_ target: String) -> ChannelMode? {
        guard target.hasPrefix("channels.") else { return nil }
        return ChannelMode(rawValue: String(target.dropFirst("channels.".count)))
    }

    private func pdfAccess(_ target: String) -> PDFLockAction? {
        guard target.hasPrefix("protectPDF.") else { return nil }
        return PDFLockAction(rawValue: String(target.dropFirst("protectPDF.".count)))
    }

    private func presentation(for target: String, tool: ToolID, files: [FileInput]) -> ToolPresentation {
        if target == "ocrPDF.options" { return .openPanel }
        return ToolCatalog.presentation(tool, for: files)
    }

    private func panelSize(for tool: ToolID) -> NSSize {
        switch tool {
        case .signPDF:
            return NSSize(width: 560, height: 720)
        case .protectPDF:
            return NSSize(width: 440, height: 420)
        case .ocrPDF:
            return NSSize(width: 440, height: 320)
        default:
            return NSSize(width: 420, height: 360)
        }
    }

    private func offerUnlock(for url: URL) {
        let inputs = [MediaClassifier.classify(url)]
        let parameters = ToolParameterDefaults.make(tool: .protectPDF, files: inputs, settings: settings, pdfAccess: .unlock)
        let entry = CatalogEntry(source: "tool", target: "protectPDF.unlock", kind: .pdf, label: "Unlock PDF", engine: .tool)
        let view = ToolPanelView(tool: .protectPDF, files: inputs, parameters: parameters, onSubmit: { [weak self] chosen in
            self?.toolPanel?.close()
            self?.queue.start(files: [url], entry: entry, toolParameters: chosen)
            self?.progress?.show()
        }, onCancel: { [weak self] in
            self?.toolPanel?.close()
        })
        toolPanel = host(title: "Unlock PDF", view: AnyView(view), size: panelSize(for: .protectPDF))
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard queue.hasRunningWork else { return .terminateNow }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "A conversion is still running."
        alert.informativeText = "Quit and stop it? The unfinished file will not be written."
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Continue")
        if alert.runModal() == .alertFirstButtonReturn {
            queue.cancelAll()
            return .terminateNow
        }
        return .terminateCancel
    }

    private func convertSelection() {
        let urls = finderSelection()
        if urls.isEmpty {
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = "Finder has no selection."
            alert.informativeText = "Select one or more files in Finder, then try again."
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return
        }
        drag.showSelection(urls)
    }

    private func finderSelection() -> [URL] {
        let source = """
        tell application "Finder"
          set theSelection to selection
          set output to {}
          repeat with f in theSelection
            set end of output to POSIX path of (f as alias)
          end repeat
          return output
        end tell
        """
        var error: NSDictionary?
        guard let result = NSAppleScript(source: source)?.executeAndReturnError(&error) else {
            if let message = error?[NSAppleScript.errorMessage] as? String {
                present(message)
            }
            return []
        }
        guard result.numberOfItems > 0 else {
            if let path = result.stringValue, !path.isEmpty {
                return [URL(fileURLWithPath: path)]
            }
            return []
        }
        var urls: [URL] = []
        for index in 1...result.numberOfItems {
            if let path = result.atIndex(index)?.stringValue, !path.isEmpty {
                urls.append(URL(fileURLWithPath: path))
            }
        }
        return urls
    }

    private func showQR(_ codes: [String]) {
        let view = QRResultPanel(codes: codes, onCopy: { text in
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }, onSave: { [weak self] in
            self?.saveQR(codes)
        }, onClose: { [weak self] in
            self?.toolPanel?.close()
        })
        toolPanel = host(title: "Read QR", view: AnyView(view), size: NSSize(width: 420, height: 280))
    }

    private func saveQR(_ codes: [String]) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "QR codes.txt"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? codes.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    private func present(_ message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "File Wheel could not read the Finder selection."
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

final class SelectionPresenter: WheelPresenting {
    private weak var drag: DragMonitor?

    init(drag: DragMonitor) {
        self.drag = drag
    }

    func present(files: [FileInput], mode: FileWheelKit.WheelMode) {
        _ = mode
        let urls = files.map(\.url)
        let drag = self.drag
        Task { @MainActor in
            drag?.showSelection(urls)
        }
    }
}
