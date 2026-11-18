import Foundation

public struct FFmpegVersionCheck: Equatable, Sendable {
    public var executable: URL?
    public var foundVersion: String?
    public var pinnedVersion: String
    public var matchesPin: Bool
    public var summary: String
    public var canEncodeWMA: Bool
    public var hardwareH264: Bool

    public init(executable: URL?, foundVersion: String?, pinnedVersion: String, matchesPin: Bool, summary: String, canEncodeWMA: Bool, hardwareH264: Bool) {
        self.executable = executable
        self.foundVersion = foundVersion
        self.pinnedVersion = pinnedVersion
        self.matchesPin = matchesPin
        self.summary = summary
        self.canEncodeWMA = canEncodeWMA
        self.hardwareH264 = hardwareH264
    }
}
