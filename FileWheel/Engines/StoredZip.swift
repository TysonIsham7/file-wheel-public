import Foundation

/// ZIP writer and reader for the store method (compression method 0).
/// OOXML packages are written this way so a DOCX does not need Word installed.
/// Deflated user archives are read by ZIPFoundation in `ArchiveEngine`.
enum StoredZip {
    struct Item {
        var path: String
        var data: Data
        var modified: ZipDOSDate
    }

    static func data(items: [Item]) throws -> Data {
        var local = Data()
        var central = Data()
        var records: [(item: Item, offset: UInt32, crc: UInt32)] = []

        for item in items {
            let path = try safePath(item.path)
            let name = Data(path.utf8)
            guard name.count <= Int(UInt16.max), item.data.count <= Int(UInt32.max), local.count <= Int(UInt32.max) else {
                throw FileWheelError("This file is too large to pack.")
            }
            let crc = CRC32.hash(item.data)
            let offset = UInt32(local.count)
            let (time, date) = item.modified.encoded
            local.appendLE32(0x0403_4B50)
            local.appendLE16(20)
            local.appendLE16(0x0800)
            local.appendLE16(0)
            local.appendLE16(time)
            local.appendLE16(date)
            local.appendLE32(crc)
            local.appendLE32(UInt32(item.data.count))
            local.appendLE32(UInt32(item.data.count))
            local.appendLE16(UInt16(name.count))
            local.appendLE16(0)
            local.append(name)
            local.append(item.data)
            records.append((item, offset, crc))
        }

        for record in records {
            let path = try safePath(record.item.path)
            let name = Data(path.utf8)
            let (time, date) = record.item.modified.encoded
            central.appendLE32(0x0201_4B50)
            central.appendLE16(0x0314)
            central.appendLE16(20)
            central.appendLE16(0x0800)
            central.appendLE16(0)
            central.appendLE16(time)
            central.appendLE16(date)
            central.appendLE32(record.crc)
            let size = UInt32(record.item.data.count)
            central.appendLE32(size)
            central.appendLE32(size)
            central.appendLE16(UInt16(name.count))
            central.appendLE16(0)
            central.appendLE16(0)
            central.appendLE16(0)
            central.appendLE16(0)
            central.appendLE32(UInt32(0o100644) << 16)
            central.appendLE32(record.offset)
            central.append(name)
        }

        guard local.count <= Int(UInt32.max), central.count <= Int(UInt32.max), records.count <= Int(UInt16.max) else {
            throw FileWheelError("This file is too large to pack.")
        }
        var end = Data()
        end.appendLE32(0x0605_4B50)
        end.appendLE16(0)
        end.appendLE16(0)
        end.appendLE16(UInt16(records.count))
        end.appendLE16(UInt16(records.count))
        end.appendLE32(UInt32(central.count))
        end.appendLE32(UInt32(local.count))
        end.appendLE16(0)

        var archive = local
        archive.append(central)
        archive.append(end)
        return archive
    }

    static func items(in archive: Data) throws -> [Item] {
        guard let eocd = endOfCentralDirectory(in: archive) else {
            throw FileWheelError(FileWheelMessages.archiveUnreadable)
        }
        var items: [Item] = []
        var cursor = eocd.offset
        for _ in 0..<eocd.count {
            guard archive.le32(at: cursor) == 0x0201_4B50 else {
                throw FileWheelError(FileWheelMessages.archiveUnreadable)
            }
            let method = archive.le16(at: cursor + 10)
            let crc = archive.le32(at: cursor + 16)
            let compressed = archive.le32(at: cursor + 20)
            let uncompressed = archive.le32(at: cursor + 24)
            let nameLength = Int(archive.le16(at: cursor + 28))
            let extraLength = Int(archive.le16(at: cursor + 30))
            let commentLength = Int(archive.le16(at: cursor + 32))
            let localOffset = Int(archive.le32(at: cursor + 42))
            let nameStart = cursor + 46
            guard archive.count >= nameStart + nameLength else {
                throw FileWheelError(FileWheelMessages.archiveUnreadable)
            }
            let nameData = archive.subdata(in: nameStart..<(nameStart + nameLength))
            guard let path = String(data: nameData, encoding: .utf8) else {
                throw FileWheelError(FileWheelMessages.archiveUnreadable)
            }
            if method != 0 {
                throw FileWheelError("This ZIP entry is compressed.")
            }
            if compressed != uncompressed {
                throw FileWheelError(FileWheelMessages.archiveUnreadable)
            }
            let data = try storedData(in: archive, localOffset: localOffset, size: Int(uncompressed), crc: crc)
            items.append(Item(path: path, data: data, modified: .epoch))
            cursor = nameStart + nameLength + extraLength + commentLength
        }
        return items
    }

    private static func storedData(in archive: Data, localOffset: Int, size: Int, crc: UInt32) throws -> Data {
        guard archive.le32(at: localOffset) == 0x0403_4B50 else {
            throw FileWheelError(FileWheelMessages.archiveUnreadable)
        }
        let nameLength = Int(archive.le16(at: localOffset + 26))
        let extraLength = Int(archive.le16(at: localOffset + 28))
        let start = localOffset + 30 + nameLength + extraLength
        let end = start + size
        guard start >= 0, end <= archive.count else {
            throw FileWheelError(FileWheelMessages.archiveUnreadable)
        }
        let data = archive.subdata(in: start..<end)
        if CRC32.hash(data) != crc {
            throw FileWheelError(FileWheelMessages.archiveUnreadable)
        }
        return data
    }

    private static func endOfCentralDirectory(in archive: Data) -> (offset: Int, count: Int)? {
        guard archive.count >= 22 else { return nil }
        let minimum = max(0, archive.count - 22 - 65_535)
        var index = archive.count - 22
        while index >= minimum {
            if archive.le32(at: index) == 0x0605_4B50 {
                let count = Int(archive.le16(at: index + 10))
                let offset = Int(archive.le32(at: index + 16))
                return (offset, count)
            }
            if index == 0 { break }
            index -= 1
        }
        return nil
    }

    private static func safePath(_ path: String) throws -> String {
        if !ArchivePathSafety.isSafe(path) {
            throw FileWheelError(FileWheelMessages.unsafeArchivePath)
        }
        return path
    }
}

enum CRC32 {
    static func hash(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            let index = Int((crc ^ UInt32(byte)) & 0xFF)
            crc = table[index] ^ (crc >> 8)
        }
        return crc ^ 0xFFFF_FFFF
    }

    private static let table: [UInt32] = (0..<256).map { entry in
        var value = UInt32(entry)
        for _ in 0..<8 {
            if value & 1 == 1 {
                value = 0xEDB8_8320 ^ (value >> 1)
            } else {
                value >>= 1
            }
        }
        return value
    }
}

struct ZipDOSDate: Equatable {
    var year: Int
    var month: Int
    var day: Int
    var hour: Int
    var minute: Int
    var second: Int

    static let epoch = ZipDOSDate(year: 1980, month: 1, day: 1, hour: 0, minute: 0, second: 0)

    static func now() -> ZipDOSDate {
        let parts = Calendar(identifier: .gregorian).dateComponents(in: TimeZone(secondsFromGMT: 0)!, from: Date())
        return ZipDOSDate(
            year: max(1980, parts.year ?? 1980),
            month: parts.month ?? 1,
            day: parts.day ?? 1,
            hour: parts.hour ?? 0,
            minute: parts.minute ?? 0,
            second: parts.second ?? 0
        )
    }

    var encoded: (time: UInt16, date: UInt16) {
        let yearOffset = UInt16(max(0, min(127, year - 1980)))
        let date = (yearOffset << 9) | (UInt16(month) << 5) | UInt16(day)
        let time = (UInt16(hour) << 11) | (UInt16(minute) << 5) | UInt16(second / 2)
        return (time, date)
    }
}

enum ArchivePathSafety {
    static func isSafe(_ path: String) -> Bool {
        if path.isEmpty || path.hasPrefix("/") || path.hasPrefix("\\") { return false }
        if path.contains("\0") { return false }
        let pieces = path.split(separator: "/", omittingEmptySubsequences: false)
        if pieces.contains("..") { return false }
        if path.contains("\\") { return false }
        return true
    }
}

private extension Data {
    mutating func appendLE16(_ value: UInt16) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
    }

    mutating func appendLE32(_ value: UInt32) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8((value >> 16) & 0xFF))
        append(UInt8((value >> 24) & 0xFF))
    }

    func le16(at offset: Int) -> UInt16 {
        guard offset >= 0, offset + 2 <= count else { return 0 }
        return UInt16(self[offset]) | (UInt16(self[offset + 1]) << 8)
    }

    func le32(at offset: Int) -> UInt32 {
        guard offset >= 0, offset + 4 <= count else { return 0 }
        return UInt32(self[offset])
            | (UInt32(self[offset + 1]) << 8)
            | (UInt32(self[offset + 2]) << 16)
            | (UInt32(self[offset + 3]) << 24)
    }
}
