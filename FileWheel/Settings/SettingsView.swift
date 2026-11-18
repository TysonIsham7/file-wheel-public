import Foundation

#if canImport(SwiftUI)
import SwiftUI

public struct SettingsView: View {
    @State private var settings: FileWheelSettings
    private let store: SettingsStoring
    private let keys: APIKeyStoring
    private let login: LoginItemManaging
    private let onChange: (FileWheelSettings) -> Void

    public init(store: SettingsStoring, keys: APIKeyStoring, login: LoginItemManaging, onChange: @escaping (FileWheelSettings) -> Void = { _ in }) {
        self.store = store
        self.keys = keys
        self.login = login
        self.onChange = onChange
        _settings = State(initialValue: store.load())
    }

    public var body: some View {
        Form {
            Section("Output") {
                Picker("Folder", selection: outputChoice) {
                    Text("Beside the original").tag(0)
                    Text("One chosen folder").tag(1)
                }
                if case .folder(let path) = settings.output {
                    TextField("Folder", text: folderBinding(path))
                }
                Toggle("Reveal in Finder after success", isOn: binding(\.revealInFinder))
                Toggle("Sound on completion", isOn: binding(\.soundOnCompletion))
            }
            Section("Images and video") {
                Slider(value: binding(\.jpegQuality), in: 0.1...1) {
                    Text("JPEG quality \(settings.jpegQuality, format: .number.precision(.fractionLength(2)))")
                }
                Picker("Video codec", selection: binding(\.videoCodec)) {
                    ForEach(VideoCodecChoice.allCases, id: \.self) { codec in
                        Text(codec.title).tag(codec)
                    }
                }
                Stepper("Long edge \(settings.videoLongEdge) px", value: binding(\.videoLongEdge), in: 240...4320, step: 10)
                Stepper("CRF \(settings.videoCRF)", value: binding(\.videoCRF), in: 0...51)
                Picker("SVG rasterize DPI", selection: binding(\.svgRasterDPI)) {
                    Text("72").tag(72)
                    Text("144").tag(144)
                    Text("300").tag(300)
                }
                Toggle("Hardware encoder", isOn: binding(\.hardwareEncoder))
            }
            Section("Startup") {
                Toggle("Launch at login", isOn: launchBinding)
            }
            Section("Read aloud") {
                Picker("Engine", selection: readAloudBinding(\.engine)) {
                    ForEach(ReadAloudEngine.allCases, id: \.self) { engine in
                        Text(engine.title).tag(engine)
                    }
                }
                TextField("xAI voice", text: readAloudBinding(\.voiceID))
                TextField("Language", text: readAloudBinding(\.language))
                Slider(value: readAloudBinding(\.speed), in: 0.7...1.5) {
                    Text("Speed \(settings.readAloud.speed, format: .number.precision(.fractionLength(2)))")
                }
                TextField("macOS voice identifier (blank is the system voice)", text: optionalVoice)
                SecureField("xAI API key", text: keyBinding)
                Text("The key is stored in the Keychain. If that item is empty, File Wheel reads XAI_API_KEY.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(8)
        .frame(width: 460)
    }

    private var outputChoice: Binding<Int> {
        Binding {
            if case .folder = settings.output { return 1 }
            return 0
        } set: { choice in
            settings.output = choice == 0 ? .besideOriginal : .folder(currentFolder())
            persist()
        }
    }

    private var launchBinding: Binding<Bool> {
        Binding {
            settings.launchAtLogin
        } set: { enabled in
            settings.launchAtLogin = enabled
            try? login.setEnabled(enabled)
            persist()
        }
    }

    private var keyBinding: Binding<String> {
        Binding {
            keys.read() ?? ""
        } set: { value in
            if value.isEmpty {
                try? keys.clear()
            } else {
                try? keys.save(value)
            }
        }
    }

    private var optionalVoice: Binding<String> {
        Binding {
            settings.readAloud.macOSVoiceIdentifier ?? ""
        } set: { value in
            settings.readAloud.macOSVoiceIdentifier = value.isEmpty ? nil : value
            persist()
        }
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<FileWheelSettings, Value>) -> Binding<Value> {
        Binding {
            settings[keyPath: keyPath]
        } set: { newValue in
            settings[keyPath: keyPath] = newValue
            persist()
        }
    }

    private func readAloudBinding<Value>(_ keyPath: WritableKeyPath<ReadAloudSettings, Value>) -> Binding<Value> {
        Binding {
            settings.readAloud[keyPath: keyPath]
        } set: { newValue in
            settings.readAloud[keyPath: keyPath] = newValue
            persist()
        }
    }

    private func folderBinding(_ path: String) -> Binding<String> {
        Binding {
            path
        } set: { newValue in
            settings.output = .folder(newValue)
            persist()
        }
    }

    private func currentFolder() -> String {
        if case .folder(let path) = settings.output { return path }
        return ""
    }

    private func persist() {
        let next = settings.clamped()
        settings = next
        try? store.save(next)
        onChange(next)
    }
}
#endif
