import Foundation
import ZIPFoundation

enum DocxPackage {
    static func readDocumentXML(at url: URL) throws -> Data {
        let archive: Archive
        do {
            archive = try Archive(url: url, accessMode: .read)
        } catch {
            throw FileWheelError(FileWheelMessages.docxUnreadable)
        }
        guard let entry = archive.first(where: { $0.path == "word/document.xml" }) else {
            throw FileWheelError(FileWheelMessages.docxUnreadable)
        }
        var data = Data()
        do {
            _ = try archive.extract(entry) { chunk in
                data.append(chunk)
            }
        } catch {
            throw FileWheelError(FileWheelMessages.docxUnreadable)
        }
        if data.isEmpty {
            throw FileWheelError(FileWheelMessages.docxUnreadable)
        }
        return data
    }
}
