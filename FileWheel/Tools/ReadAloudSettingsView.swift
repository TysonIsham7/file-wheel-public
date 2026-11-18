import AppKit
import SwiftUI

/// Read aloud keys, the xAI key, and the output folder Phase 3 writes into.
/// Phase 4 can extend this panel. The key is stored in the Keychain, not in defaults.
struct ReadAloudSettingsView: View {
    @State private var engine: ReadAloudEngineKind
    @State private var voiceID: String
    @State private var language: String
    @State private var speed: Double
    @State private var macOSVoiceIdentifier: String
    @State private var localModelPath: String
    @State private var outputMode: OutputMode
    @State private var outputFolder: String
    @State private var revealInFinder: Bool
    @State private var apiKey: String = ""
    @State private var keyStatus: String
    @State private var voices: [XAIVoice] = []
    @State private var voiceError: String?

    private let settings: Phase3SettingsStore
    private let macVoices: [MacVoice]

    init(settings: Phase3SettingsStore = .shared) {
        self.settings = settings
        let read = settings.readAloud
        let output = settings.output
        _engine = State(initialValue: read.engine)
        _voiceID = State(initialValue: read.voiceID)
        _language = State(initialValue: read.language)
        _speed = State(initialValue: read.clampedSpeed)
        _macOSVoiceIdentifier = State(initialValue: read.macOSVoiceIdentifier ?? "")
        _localModelPath = State(initialValue: read.localModelPath)
        _outputMode = State(initialValue: output.mode)
        _outputFolder = State(initialValue: output.folderPath)
        _revealInFinder = State(initialValue: output.revealInFinder)
        macVoices = MacVoiceInventory.installed()
        if XAIKeychain.read()?.isEmpty == false {
            _keyStatus = State(initialValue: "Saved in the Keychain")
        } else if ProcessInfo.processInfo.environment["XAI_API_KEY"]?.isEmpty == false {
            _keyStatus = State(initialValue: "Using XAI_API_KEY from the environment")
        } else {
            _keyStatus = State(initialValue: "No key")
        }
    }

    var body: some View {
        Form {
            Picker("Output", selection: $outputMode) {
                Text("Beside the original").tag(OutputMode.besideSource)
                Text("One folder").tag(OutputMode.folder)
            }
            if outputMode == .folder {
                HStack {
                    TextField("Folder", text: $outputFolder)
                    Button("Choose…") { chooseFolder() }
                }
            }
            Toggle("Reveal in Finder", isOn: $revealInFinder)

            Picker("Read aloud", selection: $engine) {
                Text("xAI").tag(ReadAloudEngineKind.xai)
                Text("macOS voice").tag(ReadAloudEngineKind.macos)
                Text("Local model").tag(ReadAloudEngineKind.localModel)
                    .disabled(!LocalModelSpeechEngine.isInstalled(path: localModelPath))
            }
            HStack {
                TextField("Local model executable", text: $localModelPath)
                Button("Choose…") { chooseModel() }
            }

            switch engine {
            case .xai:
                TextField("Voice", text: $voiceID)
                if !voices.isEmpty {
                    Picker("Voices", selection: $voiceID) {
                        ForEach(voices) { voice in
                            Text("\(voice.name) (\(voice.voiceID))").tag(voice.voiceID)
                        }
                    }
                }
                Button("Load voices") { Task { await loadVoices() } }
                if let voiceError {
                    Text(voiceError).foregroundStyle(.red)
                }
                Picker("Language", selection: $language) {
                    ForEach(ReadAloudLanguage.allCases) { code in
                        Text(code.rawValue).tag(code.rawValue)
                    }
                }
                SecureField("xAI API key", text: $apiKey)
                HStack {
                    Text(keyStatus).foregroundStyle(.secondary)
                    Button("Save key") { saveKey() }
                    Button("Remove key") { removeKey() }
                }
            case .macos:
                Picker("Voice", selection: $macOSVoiceIdentifier) {
                    Text("System voice").tag("")
                    ForEach(macVoices) { voice in
                        Text("\(voice.name) · \(voice.language)").tag(voice.identifier)
                    }
                }
            case .localModel:
                if !LocalModelSpeechEngine.isInstalled(path: localModelPath) {
                    Text(FileWheelMessages.noLocalModel).foregroundStyle(.red)
                }
            }

            HStack {
                Slider(value: $speed, in: 0.7...1.5, step: 0.1)
                Text(String(format: "%.1f", speed)).frame(width: 36)
            }
        }
        .padding(20)
        .frame(width: 480)
        .onChange(of: engine) { _ in persist() }
        .onChange(of: voiceID) { _ in persist() }
        .onChange(of: language) { _ in persist() }
        .onChange(of: speed) { _ in persist() }
        .onChange(of: macOSVoiceIdentifier) { _ in persist() }
        .onChange(of: localModelPath) { _ in persist() }
        .onChange(of: outputMode) { _ in persist() }
        .onChange(of: outputFolder) { _ in persist() }
        .onChange(of: revealInFinder) { _ in persist() }
    }

    private func persist() {
        var read = settings.readAloud
        let previous = read.signature
        read.engine = engine
        read.voiceID = voiceID.isEmpty ? "ara" : voiceID
        read.language = language
        read.speed = speed
        read.macOSVoiceIdentifier = macOSVoiceIdentifier.isEmpty ? nil : macOSVoiceIdentifier
        read.localModelPath = localModelPath
        if read.signature != previous {
            read.keptSignature = nil
        }
        settings.readAloud = read
        settings.output = OutputPreferences(
            mode: outputMode,
            folderPath: outputFolder,
            revealInFinder: revealInFinder,
            pageSizeName: settings.output.pageSizeName
        )
    }

    private func saveKey() {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if XAIKeychain.save(trimmed) {
            keyStatus = "Saved in the Keychain"
            apiKey = ""
        } else {
            keyStatus = "The key could not be saved"
        }
    }

    private func removeKey() {
        _ = XAIKeychain.delete()
        apiKey = ""
        keyStatus = ProcessInfo.processInfo.environment["XAI_API_KEY"]?.isEmpty == false
            ? "Using XAI_API_KEY from the environment"
            : "No key"
    }

    private func loadVoices() async {
        let client = XAITTSClient(transport: URLSessionXAITTSTransport(), apiKey: { XAIKeychain.currentKey() })
        do {
            voices = try await client.listVoices()
            voiceError = nil
        } catch {
            voiceError = (error as? FileWheelError)?.message ?? error.localizedDescription
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            outputFolder = url.path
            persist()
        }
    }

    private func chooseModel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            localModelPath = url.path
            persist()
        }
    }
}

enum SettingsPanel {
    @MainActor
    static func show() {
        let host = NSHostingController(rootView: ReadAloudSettingsView())
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 460),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.title = "File Wheel Settings"
        panel.contentViewController = host
        panel.center()
        panel.isReleasedWhenClosed = false
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
        panel.makeKeyAndOrderFront(nil)
        SettingsPanelBox.panel = panel
    }
}

private enum SettingsPanelBox {
    static var panel: NSPanel?
}
