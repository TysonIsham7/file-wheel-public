import Foundation

struct XAIVoice: Equatable, Decodable, Identifiable {
    let voiceID: String
    let name: String
    var id: String { voiceID }

    enum CodingKeys: String, CodingKey {
        case voiceID = "voice_id"
        case name
    }
}

struct TTSRequestBody: Encodable, Equatable {
    var text: String
    var voiceID: String
    var language: String
    var textNormalization: Bool
    var codec: String
    var sampleRate: Int
    var bitRate: Int
    var speed: Double

    enum CodingKeys: String, CodingKey {
        case text
        case voiceID = "voice_id"
        case language
        case textNormalization = "text_normalization"
        case outputFormat = "output_format"
        case speed
    }

    enum OutputKeys: String, CodingKey {
        case codec
        case sampleRate = "sample_rate"
        case bitRate = "bit_rate"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(text, forKey: .text)
        try container.encode(voiceID, forKey: .voiceID)
        try container.encode(language, forKey: .language)
        try container.encode(textNormalization, forKey: .textNormalization)
        try container.encode(speed, forKey: .speed)
        var output = container.nestedContainer(keyedBy: OutputKeys.self, forKey: .outputFormat)
        try output.encode(codec, forKey: .codec)
        try output.encode(sampleRate, forKey: .sampleRate)
        try output.encode(bitRate, forKey: .bitRate)
    }

    static func make(text: String, voiceID: String, language: String, speed: Double) -> TTSRequestBody {
        TTSRequestBody(
            text: text,
            voiceID: voiceID.isEmpty ? "ara" : voiceID,
            language: ReadAloudLanguage.normalize(language),
            textNormalization: true,
            codec: "mp3",
            sampleRate: 44_100,
            bitRate: 192_000,
            speed: min(1.5, max(0.7, speed))
        )
    }

    func jsonData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }
}

enum XAITTSEndpoint {
    static let tts = URL(string: "https://api.x.ai/v1/tts")!
    static let voices = URL(string: "https://api.x.ai/v1/tts/voices")!

    static func isAllowed(_ url: URL) -> Bool {
        guard url.scheme == "https", url.host == "api.x.ai" else { return false }
        return url.path == "/v1/tts" || url.path == "/v1/tts/voices"
    }
}

struct TTSResponse {
    var status: Int
    var contentType: String?
    var body: Data
}

protocol XAITTSTransport {
    func send(_ request: URLRequest) async throws -> TTSResponse
}

enum MP3Bytes {
    static func isAudio(_ data: Data, contentType: String?) -> Bool {
        let type = contentType?.lowercased() ?? ""
        if type.contains("json") || type.contains("text/") { return false }
        if data.isEmpty { return false }
        if type.contains("audio") || type.contains("mpeg") || type.contains("mp3") { return true }
        if data.starts(with: [0x49, 0x44, 0x33]) { return true }
        if data.count >= 2, data[0] == 0xFF, data[1] & 0xE0 == 0xE0 { return true }
        if type.isEmpty || type.contains("octet-stream") { return false }
        return false
    }
}

/// HTTPS client for Read aloud. The only hosts it will call are the two TTS endpoints.
struct XAITTSClient {
    var transport: XAITTSTransport
    var apiKey: () -> String?

    func synthesize(_ body: TTSRequestBody) async throws -> Data {
        guard let key = apiKey(), !key.isEmpty else {
            throw FileWheelError(FileWheelMessages.missingAPIKey)
        }
        var request = URLRequest(url: XAITTSEndpoint.tts)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.httpBody = try body.jsonData()
        request.timeoutInterval = 180
        let response = try await send(request)
        if response.status == 401 {
            throw FileWheelError(FileWheelMessages.xaiKeyRejected, unauthorized: true)
        }
        guard response.status == 200, MP3Bytes.isAudio(response.body, contentType: response.contentType) else {
            throw FileWheelError(FileWheelMessages.xaiNotAudio)
        }
        return response.body
    }

    func listVoices() async throws -> [XAIVoice] {
        guard let key = apiKey(), !key.isEmpty else {
            throw FileWheelError(FileWheelMessages.missingAPIKey)
        }
        var request = URLRequest(url: XAITTSEndpoint.voices)
        request.httpMethod = "GET"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        let response = try await send(request)
        if response.status == 401 {
            throw FileWheelError(FileWheelMessages.xaiKeyRejected, unauthorized: true)
        }
        guard response.status == 200 else {
            throw FileWheelError(FileWheelMessages.xaiNotAudio)
        }
        let decoded = try JSONDecoder().decode(VoiceList.self, from: response.body)
        return decoded.voices
    }

    private func send(_ request: URLRequest) async throws -> TTSResponse {
        guard let url = request.url, XAITTSEndpoint.isAllowed(url) else {
            throw FileWheelError("Read aloud can only contact api.x.ai.")
        }
        return try await transport.send(request)
    }
}

private struct VoiceList: Decodable {
    var voices: [XAIVoice]
}

final class URLSessionXAITTSTransport: NSObject, XAITTSTransport, URLSessionTaskDelegate {
    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }()

    func send(_ request: URLRequest) async throws -> TTSResponse {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw FileWheelError(FileWheelMessages.xaiNotAudio)
        }
        return TTSResponse(
            status: http.statusCode,
            contentType: http.value(forHTTPHeaderField: "Content-Type"),
            body: data
        )
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        if let url = request.url, XAITTSEndpoint.isAllowed(url) {
            completionHandler(request)
        } else {
            completionHandler(nil)
        }
    }
}
