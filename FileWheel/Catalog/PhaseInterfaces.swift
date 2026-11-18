import Foundation

public enum WheelMode: String, Sendable, Equatable {
    case convert
    case tools
}

/// Phase 1 implements this with the radial wheel. Menu-bar Convert selection and the
/// Services menu both call it. The stand-in in `PhaseOneWheelStandIn` is only here so
/// this branch runs before the wheel lands.
public protocol WheelPresenting: AnyObject {
    func present(files: [FileInput], mode: WheelMode)
}

public protocol FinderSelecting {
    func selectionURLs() throws -> [URL]
}

public struct ConvertSelectionCommand {
    public var selection: FinderSelecting
    public var wheel: WheelPresenting

    public init(selection: FinderSelecting, wheel: WheelPresenting) {
        self.selection = selection
        self.wheel = wheel
    }

    public func run() throws {
        let urls = try selection.selectionURLs()
        let files = urls.map { MediaClassifier.classify($0) }
        wheel.present(files: files, mode: .convert)
    }
}

/// Phases 2 and 3 perform a directed pair. Tool execution does not go through this type.
public protocol ConversionPerforming: AnyObject {
    func convert(pair: DirectedPair, files: [FileInput], settings: FileWheelSettings) throws -> [URL]
}

public protocol QRDetecting {
    func codes(in imageURL: URL) throws -> [String]
}

public struct FixedQRDetector: QRDetecting {
    public var codes: [String]

    public init(codes: [String]) {
        self.codes = codes
    }

    public func codes(in imageURL: URL) throws -> [String] {
        codes
    }
}

public struct SpeechRecognitionError: Error, Equatable {
    public init() {}
}

public protocol SpeechRangeFinding {
    func ranges(in mediaURL: URL, word: String) throws -> [TimeRange]
}

public struct TimeRange: Equatable, Sendable {
    public var start: Double
    public var end: Double

    public init(start: Double, end: Double) {
        self.start = start
        self.end = end
    }

    public var isValid: Bool { end > start && start >= 0 }
}

public struct FailingSpeechFinder: SpeechRangeFinding {
    public init() {}

    public func ranges(in mediaURL: URL, word: String) throws -> [TimeRange] {
        throw SpeechRecognitionError()
    }
}

public protocol LoginItemManaging {
    func setEnabled(_ enabled: Bool) throws
    func isEnabled() -> Bool
}

public struct DisabledLoginItem: LoginItemManaging {
    public init() {}
    public func setEnabled(_ enabled: Bool) throws {}
    public func isEnabled() -> Bool { false }
}
