import Foundation

public protocol SettingsStoring: AnyObject {
    func load() -> FileWheelSettings
    func save(_ settings: FileWheelSettings) throws
}

public final class JSONSettingsStore: SettingsStoring {
    public let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(fileURL: URL) {
        self.fileURL = fileURL
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder
        self.decoder = JSONDecoder()
    }

    public static func applicationSupportURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("File Wheel", isDirectory: true).appendingPathComponent("settings.json")
    }

    public func load() -> FileWheelSettings {
        guard let data = try? Data(contentsOf: fileURL),
              let settings = try? decoder.decode(FileWheelSettings.self, from: data) else {
            return .default
        }
        return settings.clamped()
    }

    public func save(_ settings: FileWheelSettings) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try encoder.encode(settings.clamped())
        try data.write(to: fileURL, options: .atomic)
    }
}

public protocol APIKeyStoring: AnyObject {
    func read() -> String?
    func save(_ value: String) throws
    func clear() throws
}

public final class MemoryAPIKeyStore: APIKeyStoring {
    public var value: String?

    public init(value: String? = nil) {
        self.value = value
    }

    public func read() -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    public func save(_ value: String) throws {
        self.value = value
    }

    public func clear() throws {
        value = nil
    }
}

/// Keychain first. When that item is empty, `XAI_API_KEY` from the environment.
public final class LayeredAPIKeyStore: APIKeyStoring {
    public let primary: APIKeyStoring
    public var environment: [String: String]

    public init(primary: APIKeyStoring, environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.primary = primary
        self.environment = environment
    }

    public func read() -> String? {
        if let key = primary.read(), !key.isEmpty {
            return key
        }
        if let env = environment["XAI_API_KEY"], !env.isEmpty {
            return env
        }
        return nil
    }

    public func save(_ value: String) throws {
        try primary.save(value)
    }

    public func clear() throws {
        try primary.clear()
    }
}
