import FileWheelKit
import Foundation

#if canImport(AppKit)
import AppKit

public final class ServicesProvider: NSObject {
    public weak var presenter: WheelPresenting?

    public override init() {
        super.init()
    }

    @objc(convertSelection:userData:error:)
    public func convertSelection(_ pasteboard: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        if urls.isEmpty {
            error.pointee = "File Wheel did not receive any files." as NSString
            return
        }
        let files = urls.map { MediaClassifier.classify($0) }
        presenter?.present(files: files, mode: .convert)
    }
}

public struct FinderSelectionReader: FinderSelecting {
    public init() {}

    public func selectionURLs() throws -> [URL] {
        let source = """
        tell application "Finder"
            if (count of Finder windows) is 0 then return ""
            set selectedItems to selection
            set output to ""
            repeat with oneItem in selectedItems
                set output to output & POSIX path of (oneItem as alias) & linefeed
            end repeat
            return output
        end tell
        """
        var errorInfo: NSDictionary?
        guard let script = NSAppleScript(source: source) else {
            throw ToolError.message("Could not read the Finder selection.")
        }
        let result = script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            let message = errorInfo[NSAppleScript.errorMessage] as? String ?? "Could not read the Finder selection."
            throw ToolError.message(message)
        }
        let text = result.stringValue ?? ""
        return text.split(whereSeparator: \.isNewline).map { URL(fileURLWithPath: String($0)) }
    }
}
#endif
