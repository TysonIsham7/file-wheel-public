import Foundation

enum ReadAloudEngineKind: String, Codable, CaseIterable, Identifiable {
    case xai
    case macos
    case localModel

    var id: String { rawValue }

    var title: String {
        switch self {
        case .xai: return "xAI"
        case .macos: return "macOS"
        case .localModel: return "Local model"
        }
    }
}

/// Languages the xAI TTS docs list. The panel offers these codes, including `auto`.
enum ReadAloudLanguage: String, CaseIterable, Identifiable {
    case auto, en
    case arEG = "ar-EG"
    case arSA = "ar-SA"
    case arAE = "ar-AE"
    case bn, zh, fr, de, hi, id, it, ja, ko
    case ptBR = "pt-BR"
    case ptPT = "pt-PT"
    case ru
    case esMX = "es-MX"
    case esES = "es-ES"
    case tr, vi

    var id: String { rawValue }

    static func normalize(_ code: String) -> String {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "en" }
        if let match = allCases.first(where: { $0.rawValue.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return match.rawValue
        }
        return "en"
    }
}

struct ReadAloudConfiguration: Equatable, Sendable {
    var engine: ReadAloudEngineKind
    var voiceID: String
    var language: String
    var speed: Double
    var macOSVoiceIdentifier: String?
    var localModelPath: String
    var keepChoice: Bool
    var keptSignature: String?

    static let `default` = ReadAloudConfiguration(
        engine: .xai,
        voiceID: "ara",
        language: "en",
        speed: 1.0,
        macOSVoiceIdentifier: nil,
        localModelPath: "",
        keepChoice: false,
        keptSignature: nil
    )

    var clampedSpeed: Double { min(1.5, max(0.7, speed)) }

    var signature: String {
        let voice: String
        switch engine {
        case .xai: voice = voiceID.isEmpty ? "ara" : voiceID
        case .macos: voice = macOSVoiceIdentifier ?? "system"
        case .localModel: voice = localModelPath
        }
        return "\(engine.rawValue)|\(voice)|\(String(format: "%.2f", clampedSpeed))|\(language)"
    }

    var shouldSkipConfirmPanel: Bool {
        keepChoice && keptSignature == signature
    }

    func keepingCurrentChoice(_ keep: Bool) -> ReadAloudConfiguration {
        var copy = self
        copy.keepChoice = keep
        copy.keptSignature = keep ? signature : nil
        return copy
    }
}

enum OutputMode: String {
    case besideSource
    case folder
}

/// Keys Phase 3 owns. Phase 4's Settings panel should read this same store.
enum SettingsKey {
    static let outputMode = "filewheel.output.mode"
    static let outputFolder = "filewheel.output.folder"
    static let revealInFinder = "filewheel.output.revealInFinder"
    static let pageSize = "filewheel.pageSize"
    static let readAloudEngine = "filewheel.readAloud.engine"
    static let xaiVoiceID = "filewheel.readAloud.xaiVoiceID"
    static let language = "filewheel.readAloud.language"
    static let speed = "filewheel.readAloud.speed"
    static let macOSVoice = "filewheel.readAloud.macOSVoice"
    static let localModelPath = "filewheel.readAloud.localModelPath"
    static let keepChoice = "filewheel.readAloud.keepChoice"
    static let keptSignature = "filewheel.readAloud.keptSignature"
}

struct OutputPreferences: Equatable {
    var mode: OutputMode
    var folderPath: String
    var revealInFinder: Bool
    /// US Letter until a later phase adds more page sizes. Text rendering reads this.
    var pageSizeName: String

    static let `default` = OutputPreferences(
        mode: .besideSource,
        folderPath: "",
        revealInFinder: true,
        pageSizeName: "letter"
    )

    func directory(forSource source: URL) -> URL {
        if mode == .folder, !folderPath.isEmpty {
            return URL(fileURLWithPath: folderPath, isDirectory: true)
        }
        return source.deletingLastPathComponent()
    }
}

final class Phase3SettingsStore {
    static let shared = Phase3SettingsStore()

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var output: OutputPreferences {
        get {
            OutputPreferences(
                mode: OutputMode(rawValue: defaults.string(forKey: SettingsKey.outputMode) ?? "") ?? .besideSource,
                folderPath: defaults.string(forKey: SettingsKey.outputFolder) ?? "",
                revealInFinder: defaults.object(forKey: SettingsKey.revealInFinder) as? Bool ?? true,
                pageSizeName: defaults.string(forKey: SettingsKey.pageSize) ?? "letter"
            )
        }
        set {
            defaults.set(newValue.mode.rawValue, forKey: SettingsKey.outputMode)
            defaults.set(newValue.folderPath, forKey: SettingsKey.outputFolder)
            defaults.set(newValue.revealInFinder, forKey: SettingsKey.revealInFinder)
            defaults.set(newValue.pageSizeName, forKey: SettingsKey.pageSize)
        }
    }

    var readAloud: ReadAloudConfiguration {
        get {
            let engine = ReadAloudEngineKind(rawValue: defaults.string(forKey: SettingsKey.readAloudEngine) ?? "") ?? .xai
            let speed = defaults.object(forKey: SettingsKey.speed) as? Double ?? 1.0
            return ReadAloudConfiguration(
                engine: engine,
                voiceID: defaults.string(forKey: SettingsKey.xaiVoiceID) ?? "ara",
                language: ReadAloudLanguage.normalize(defaults.string(forKey: SettingsKey.language) ?? "en"),
                speed: speed,
                macOSVoiceIdentifier: defaults.string(forKey: SettingsKey.macOSVoice),
                localModelPath: defaults.string(forKey: SettingsKey.localModelPath) ?? "",
                keepChoice: defaults.bool(forKey: SettingsKey.keepChoice),
                keptSignature: defaults.string(forKey: SettingsKey.keptSignature)
            )
        }
        set {
            defaults.set(newValue.engine.rawValue, forKey: SettingsKey.readAloudEngine)
            defaults.set(newValue.voiceID.isEmpty ? "ara" : newValue.voiceID, forKey: SettingsKey.xaiVoiceID)
            defaults.set(ReadAloudLanguage.normalize(newValue.language), forKey: SettingsKey.language)
            defaults.set(newValue.clampedSpeed, forKey: SettingsKey.speed)
            if let voice = newValue.macOSVoiceIdentifier, !voice.isEmpty {
                defaults.set(voice, forKey: SettingsKey.macOSVoice)
            } else {
                defaults.removeObject(forKey: SettingsKey.macOSVoice)
            }
            defaults.set(newValue.localModelPath, forKey: SettingsKey.localModelPath)
            defaults.set(newValue.keepChoice, forKey: SettingsKey.keepChoice)
            if let signature = newValue.keptSignature {
                defaults.set(signature, forKey: SettingsKey.keptSignature)
            } else {
                defaults.removeObject(forKey: SettingsKey.keptSignature)
            }
        }
    }
}
