import AppKit
import AVFoundation
import SwiftUI

struct ProgressLogLine: Identifiable {
    let id = UUID()
    var text: String
}

final class ProgressRelay: ConversionProgress {
    private let apply: @Sendable (String, Double?) -> Void

    init(apply: @escaping @Sendable (String, Double?) -> Void) {
        self.apply = apply
    }

    func update(message: String, fraction: Double?) {
        apply(message, fraction)
    }
}

@MainActor
final class ProgressModel: ObservableObject {
    @Published var fileName: String
    @Published var action: String
    @Published var message: String
    @Published var fraction: Double
    @Published var indeterminate: Bool
    @Published var finished = false
    @Published var outputs: [URL] = []
    @Published var log: [ProgressLogLine] = []
    var onCancel: () -> Void = {}
    private var player: AVAudioPlayer?

    init(fileName: String, action: String) {
        self.fileName = fileName
        self.action = action
        self.message = action
        self.fraction = 0
        self.indeterminate = true
    }

    var canPlay: Bool {
        outputs.contains { $0.pathExtension.lowercased() == "mp3" }
    }

    func addLog(_ text: String) {
        log.append(ProgressLogLine(text: text))
    }

    func play() {
        guard let url = outputs.last(where: { $0.pathExtension.lowercased() == "mp3" }) else { return }
        player = try? AVAudioPlayer(contentsOf: url)
        player?.play()
    }

    func reveal() {
        guard !outputs.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(outputs)
    }
}

struct ProgressWindowView: View {
    @ObservedObject var model: ProgressModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(model.fileName).font(.headline).lineLimit(1)
            Text(model.action).foregroundStyle(.secondary)
            if model.indeterminate {
                ProgressView()
            } else {
                ProgressView(value: model.fraction)
            }
            Text(model.message).font(.callout)
            ForEach(model.log) { line in
                Text(line.text).font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Button("Cancel", action: model.onCancel).disabled(model.finished)
                Spacer()
                if model.canPlay {
                    Button("Play", action: model.play)
                }
                Button("Show in Finder", action: model.reveal).disabled(model.outputs.isEmpty)
            }
        }
        .padding(16)
        .frame(width: 420)
    }
}

@MainActor
enum ProgressWindow {
    private static var panel: NSPanel?
    private static var model: ProgressModel?

    static func present(fileName: String, action: String, onCancel: @escaping () -> Void) -> (ProgressModel, ProgressRelay) {
        let model = ProgressModel(fileName: fileName, action: action)
        model.onCancel = onCancel
        self.model = model
        let host = NSHostingController(rootView: ProgressWindowView(model: model))
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 220),
            styleMask: [.titled, .closable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "File Wheel"
        panel.contentViewController = host
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel
        let relay = ProgressRelay { message, fraction in
            DispatchQueue.main.async {
                model.message = message
                if let fraction {
                    model.indeterminate = false
                    model.fraction = fraction
                }
            }
        }
        return (model, relay)
    }
}
