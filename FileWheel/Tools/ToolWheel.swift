import FileWheelKit
import Foundation

enum ToolWheel {
    static func wedges(for urls: [URL]) -> [Wedge] {
        let inputs = urls.map { MediaClassifier.classify($0) }
        return ToolCatalog.wheelEntries(for: inputs).map { entry in
            Wedge(
                entry: CatalogEntry(
                    source: "tool",
                    target: entry.id,
                    kind: inputs.first?.kind ?? .unknown,
                    label: entry.title,
                    engine: .tool
                ),
                state: .enabled
            )
        }
    }
}
