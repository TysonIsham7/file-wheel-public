import AppKit
import SwiftUI

struct ReadAloudConfirmResult {
    var confirmed: Bool
    var keepChoice: Bool
}

/// The only place a Read aloud job can start. Cancel writes nothing.
@MainActor
enum ReadAloudConfirmPanel {
    static func ask(
        preparation: ReadAloudPreparation,
        configuration: ReadAloudConfiguration
    ) async -> ReadAloudConfirmResult {
        await withCheckedContinuation { continuation in
            let model = ConfirmModel(preparation: preparation, configuration: configuration)
            model.finish = { result in
                continuation.resume(returning: result)
            }
            let view = ReadAloudConfirmView(model: model) { result in
                continuation.resume(returning: result)
            }
            let host = NSHostingController(rootView: view)
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 460, height: 320),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            panel.title = "Listen (MP3)"
            panel.contentViewController = host
            panel.isReleasedWhenClosed = false
            panel.level = .floating
            panel.hidesOnDeactivate = false
            panel.center()
            model.panel = panel
            let closer = PanelCloseProxy { model.complete(false) }
            model.closer = closer
            panel.delegate = closer
            if #available(macOS 14.0, *) {
                NSApp.activate()
            } else {
                NSApp.activate(ignoringOtherApps: true)
            }
            panel.makeKeyAndOrderFront(nil)
        }
    }
}

@MainActor
private final class ConfirmModel: ObservableObject {
    let preparation: ReadAloudPreparation
    let configuration: ReadAloudConfiguration
    @Published var keepChoice: Bool
    weak var panel: NSPanel?
    var closer: PanelCloseProxy?
    var finish: ((ReadAloudConfirmResult) -> Void)?
    private var finished = false

    init(preparation: ReadAloudPreparation, configuration: ReadAloudConfiguration) {
        self.preparation = preparation
        self.configuration = configuration
        self.keepChoice = configuration.keepChoice
    }

    var fileLine: String {
        if preparation.files.count == 1 {
            return preparation.files[0].url.lastPathComponent
        }
        return "\(preparation.files.count) files"
    }

    var voiceLabel: String {
        switch configuration.engine {
        case .xai:
            return configuration.voiceID.isEmpty ? "ara" : configuration.voiceID
        case .macos:
            if let identifier = configuration.macOSVoiceIdentifier,
               let voice = MacVoiceInventory.installed().first(where: { $0.identifier == identifier }) {
                return voice.name
            }
            return "System voice"
        case .localModel:
            let path = configuration.localModelPath.trimmingCharacters(in: .whitespacesAndNewlines)
            if path.isEmpty { return "Local model" }
            return URL(fileURLWithPath: path).lastPathComponent
        }
    }

    var disclosure: String {
        configuration.engine == .xai ? FileWheelMessages.sentToXAI : FileWheelMessages.spokenOnThisMac
    }

    func complete(_ confirmed: Bool) {
        guard !finished else { return }
        finished = true
        panel?.close()
        finish?(ReadAloudConfirmResult(confirmed: confirmed, keepChoice: keepChoice))
    }
}

private struct ReadAloudConfirmView: View {
    @ObservedObject var model: ConfirmModel
    var onFinish: (ReadAloudConfirmResult) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(model.fileLine)
                .font(.headline)
            LabeledContent("Characters", value: formatted(model.preparation.characterCount))
            LabeledContent("Voice", value: model.voiceLabel)
            LabeledContent("Engine", value: model.configuration.engine.title)
            LabeledContent("Speed", value: String(format: "%.1f", model.configuration.clampedSpeed))
            if model.configuration.engine == .xai {
                LabeledContent("Chunks", value: formatted(model.preparation.chunkCount))
                LabeledContent("Language", value: model.configuration.language)
            }
            Text(model.disclosure)
                .fixedSize(horizontal: false, vertical: true)
            Toggle("Keep this choice", isOn: $model.keepChoice)
            HStack {
                Spacer()
                Button("Cancel") { finish(false) }
                Button("Confirm") { finish(true) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 460)
        .onAppear { model.finish = onFinish }
    }

    private func finish(_ confirmed: Bool) {
        model.complete(confirmed)
    }

    private func formatted(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }
}

private final class PanelCloseProxy: NSObject, NSWindowDelegate {
    let onClose: () -> Void
    init(onClose: @escaping () -> Void) { self.onClose = onClose }
    func windowWillClose(_ notification: Notification) { onClose() }
}
