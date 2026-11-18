import Foundation

public struct EngineJob: Sendable {
    public let source: URL
    public let tempOutput: URL
    public let entry: CatalogEntry
    public let options: ConversionOptions
    public let cancel: ConversionCancel

    public init(
        source: URL,
        tempOutput: URL,
        entry: CatalogEntry,
        options: ConversionOptions = .specDefaults,
        cancel: ConversionCancel
    ) {
        self.source = source
        self.tempOutput = tempOutput
        self.entry = entry
        self.options = options
        self.cancel = cancel
    }
}
