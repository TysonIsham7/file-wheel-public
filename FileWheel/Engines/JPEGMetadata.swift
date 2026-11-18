import Foundation

public struct GPSFix: Equatable, Sendable {
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

public struct JPEGTagSet: Equatable, Sendable {
    public var title: String
    public var author: String
    public var description: String
    public var creationDate: String
    public var gps: GPSFix?
    public var readOnly: [String: String]

    public init(title: String = "", author: String = "", description: String = "", creationDate: String = "", gps: GPSFix? = nil, readOnly: [String: String] = [:]) {
        self.title = title
        self.author = author
        self.description = description
        self.creationDate = creationDate
        self.gps = gps
        self.readOnly = readOnly
    }
}

public enum JPEGMetadata {
    public static func gps(in data: Data) -> GPSFix? {
        read(data)?.gps
    }

    public static func read(_ data: Data) -> JPEGTagSet? {
        guard let app1 = app1Payload(data) else { return JPEGTagSet() }
        return parseTIFF(app1)
    }

    public static func strip(_ data: Data) -> Data {
        removeSegments(data, markers: [0xE1, 0xE2])
    }

    public static func write(_ data: Data, tags: JPEGTagSet) -> Data {
        let stripped = strip(data)
        guard let app1 = encodeAPP1(tags) else { return stripped }
        var output = Data()
        output.append(0xFF)
        output.append(0xD8)
        output.append(app1)
        if stripped.count > 2 {
            output.append(stripped.dropFirst(2))
        }
        return output
    }

    public static func injectGPS(_ data: Data, gps: GPSFix) -> Data {
        var tags = read(data) ?? JPEGTagSet()
        tags.gps = gps
        return write(data, tags: tags)
    }

    private static func app1Payload(_ data: Data) -> Data? {
        var index = 2
        let bytes = [UInt8](data)
        guard bytes.count > 4, bytes[0] == 0xFF, bytes[1] == 0xD8 else { return nil }
        while index + 4 < bytes.count {
            if bytes[index] != 0xFF {
                return nil
            }
            let marker = bytes[index + 1]
            if marker == 0xDA || marker == 0xD9 {
                return nil
            }
            let length = Int(bytes[index + 2]) << 8 | Int(bytes[index + 3])
            guard length >= 2, index + 2 + length <= bytes.count else { return nil }
            if marker == 0xE1 {
                let payload = Data(bytes[(index + 4)..<(index + 2 + length)])
                if payload.starts(with: Data("Exif\0\0".utf8)) {
                    return payload.dropFirst(6)
                }
            }
            index += 2 + length
        }
        return nil
    }

    private static func removeSegments(_ data: Data, markers: Set<UInt8>) -> Data {
        let bytes = [UInt8](data)
        guard bytes.count > 2, bytes[0] == 0xFF, bytes[1] == 0xD8 else { return data }
        var output = Data([0xFF, 0xD8])
        var index = 2
        while index + 1 < bytes.count {
            if bytes[index] != 0xFF {
                output.append(contentsOf: bytes[index...])
                break
            }
            let marker = bytes[index + 1]
            if marker == 0xDA {
                output.append(contentsOf: bytes[index...])
                break
            }
            if marker == 0xD9 {
                output.append(contentsOf: bytes[index...])
                break
            }
            guard index + 4 <= bytes.count else { break }
            let length = Int(bytes[index + 2]) << 8 | Int(bytes[index + 3])
            guard length >= 2, index + 2 + length <= bytes.count else { break }
            if !markers.contains(marker) {
                output.append(contentsOf: bytes[index..<(index + 2 + length)])
            }
            index += 2 + length
        }
        return output
    }

    private static func parseTIFF(_ tiff: Data) -> JPEGTagSet {
        let bytes = [UInt8](tiff)
        guard bytes.count > 8, bytes[0] == 0x49, bytes[1] == 0x49, bytes[2] == 42, bytes[3] == 0 else {
            return JPEGTagSet()
        }
        let ifd = intLE(bytes, 4)
        var tags = JPEGTagSet()
        var gpsOffset: Int?
        guard let entries = readIFD(bytes, ifd) else { return tags }
        for entry in entries {
            switch entry.tag {
            case 0x010D:
                tags.title = ascii(bytes, entry) ?? tags.title
            case 0x013B:
                tags.author = ascii(bytes, entry) ?? tags.author
            case 0x010E:
                tags.description = ascii(bytes, entry) ?? tags.description
            case 0x0132:
                tags.creationDate = ascii(bytes, entry) ?? tags.creationDate
            case 0x8825:
                gpsOffset = intValue(entry)
            case 0x0131:
                tags.readOnly["Software"] = ascii(bytes, entry) ?? ""
            default:
                break
            }
        }
        if let gpsOffset, let gpsEntries = readIFD(bytes, gpsOffset) {
            var latRef = "N"
            var lonRef = "E"
            var lat: Double?
            var lon: Double?
            for entry in gpsEntries {
                switch entry.tag {
                case 1:
                    latRef = ascii(bytes, entry) ?? latRef
                case 3:
                    lonRef = ascii(bytes, entry) ?? lonRef
                case 2:
                    lat = rational3(bytes, entry)
                case 4:
                    lon = rational3(bytes, entry)
                default:
                    break
                }
            }
            if let lat, let lon {
                tags.gps = GPSFix(
                    latitude: latRef == "S" ? -lat : lat,
                    longitude: lonRef == "W" ? -lon : lon
                )
            }
        }
        return tags
    }

    private struct IFDEntry {
        var tag: UInt16
        var type: UInt16
        var count: Int
        var value: Int
    }

    private static func readIFD(_ bytes: [UInt8], _ offset: Int) -> [IFDEntry]? {
        guard offset + 2 <= bytes.count else { return nil }
        let count = Int(int16(bytes, offset))
        guard offset + 2 + count * 12 <= bytes.count else { return nil }
        var entries: [IFDEntry] = []
        for index in 0..<count {
            let start = offset + 2 + index * 12
            entries.append(IFDEntry(
                tag: int16(bytes, start),
                type: int16(bytes, start + 2),
                count: intLE(bytes, start + 4),
                value: intLE(bytes, start + 8)
            ))
        }
        return entries
    }

    private static func ascii(_ bytes: [UInt8], _ entry: IFDEntry) -> String? {
        let count = entry.count
        let raw: [UInt8]
        if count <= 4 {
            var inline: [UInt8] = []
            var value = UInt32(entry.value)
            for _ in 0..<count {
                inline.append(UInt8(value & 0xFF))
                value >>= 8
            }
            raw = inline
        } else {
            let offset = entry.value
            guard offset >= 0, offset + count <= bytes.count else { return nil }
            raw = Array(bytes[offset..<(offset + count)])
        }
        let text = String(data: Data(raw), encoding: .ascii) ?? ""
        return text.replacingOccurrences(of: "\0", with: "")
    }

    private static func rational3(_ bytes: [UInt8], _ entry: IFDEntry) -> Double? {
        let offset = entry.value
        guard offset + 24 <= bytes.count else { return nil }
        func rational(_ index: Int) -> Double {
            let base = offset + index * 8
            let numerator = UInt32(intLE(bytes, base))
            let denominator = UInt32(intLE(bytes, base + 4))
            if denominator == 0 { return 0 }
            return Double(numerator) / Double(denominator)
        }
        return rational(0) + rational(1) / 60 + rational(2) / 3600
    }

    private static func intValue(_ entry: IFDEntry) -> Int { entry.value }

    private static func int16(_ bytes: [UInt8], _ offset: Int) -> UInt16 {
        UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
    }

    private static func intLE(_ bytes: [UInt8], _ offset: Int) -> Int {
        Int(bytes[offset]) | Int(bytes[offset + 1]) << 8 | Int(bytes[offset + 2]) << 16 | Int(bytes[offset + 3]) << 24
    }

    private static func encodeAPP1(_ tags: JPEGTagSet) -> Data? {
        var tiff = Data()
        func append16(_ value: UInt16) {
            tiff.append(UInt8(value & 0xFF))
            tiff.append(UInt8(value >> 8))
        }
        func append32(_ value: UInt32) {
            tiff.append(UInt8(value & 0xFF))
            tiff.append(UInt8((value >> 8) & 0xFF))
            tiff.append(UInt8((value >> 16) & 0xFF))
            tiff.append(UInt8((value >> 24) & 0xFF))
        }
        tiff.append(contentsOf: [0x49, 0x49, 42, 0])
        append32(8)
        var entries: [(UInt16, String)] = []
        if !tags.title.isEmpty { entries.append((0x010D, tags.title)) }
        if !tags.description.isEmpty { entries.append((0x010E, tags.description)) }
        if !tags.creationDate.isEmpty { entries.append((0x0132, tags.creationDate)) }
        if !tags.author.isEmpty { entries.append((0x013B, tags.author)) }
        let gps = tags.gps
        let entryCount = entries.count + (gps == nil ? 0 : 1)
        append16(UInt16(entryCount))
        let entriesStart = tiff.count
        tiff.append(Data(repeating: 0, count: entryCount * 12 + 4))
        var extra = Data()
        func putEntry(index: Int, tag: UInt16, type: UInt16, count: Int, value: UInt32) {
            var encoded = Data()
            func a16(_ value: UInt16) {
                encoded.append(UInt8(value & 0xFF))
                encoded.append(UInt8(value >> 8))
            }
            func a32(_ value: UInt32) {
                encoded.append(UInt8(value & 0xFF))
                encoded.append(UInt8((value >> 8) & 0xFF))
                encoded.append(UInt8((value >> 16) & 0xFF))
                encoded.append(UInt8((value >> 24) & 0xFF))
            }
            a16(tag)
            a16(type)
            a32(UInt32(count))
            a32(value)
            let start = entriesStart + index * 12
            tiff.replaceSubrange(start..<(start + 12), with: encoded)
        }
        for (index, entry) in entries.enumerated() {
            let raw = Array(entry.1.utf8) + [0]
            let value: UInt32
            if raw.count <= 4 {
                var inline: UInt32 = 0
                for (offset, byte) in raw.enumerated() {
                    inline |= UInt32(byte) << (8 * offset)
                }
                value = inline
            } else {
                value = UInt32(8 + 2 + entryCount * 12 + 4 + extra.count)
                extra.append(contentsOf: raw)
            }
            putEntry(index: index, tag: entry.0, type: 2, count: raw.count, value: value)
        }
        if let gps {
            let gpsOffset = 8 + 2 + entryCount * 12 + 4 + extra.count
            putEntry(index: entries.count, tag: 0x8825, type: 4, count: 1, value: UInt32(gpsOffset))
            extra.append(gpsIFD(gps, absoluteOffset: gpsOffset))
        }
        tiff.append(extra)
        var app1 = Data("Exif\0\0".utf8)
        app1.append(tiff)
        let length = app1.count + 2
        guard length < 65_000 else { return nil }
        var segment = Data([0xFF, 0xE1, UInt8((length >> 8) & 0xFF), UInt8(length & 0xFF)])
        segment.append(app1)
        return segment
    }

    private static func gpsIFD(_ gps: GPSFix, absoluteOffset: Int) -> Data {
        func u16(_ value: UInt16) -> Data {
            Data([UInt8(value & 0xFF), UInt8(value >> 8)])
        }
        func u32(_ value: UInt32) -> Data {
            Data([
                UInt8(value & 0xFF),
                UInt8((value >> 8) & 0xFF),
                UInt8((value >> 16) & 0xFF),
                UInt8((value >> 24) & 0xFF)
            ])
        }
        func entry(tag: UInt16, type: UInt16, count: UInt32, value: UInt32) -> Data {
            var encoded = Data()
            encoded.append(u16(tag))
            encoded.append(u16(type))
            encoded.append(u32(count))
            encoded.append(u32(value))
            return encoded
        }
        func coordinate(_ degrees: Double) -> Data {
            var whole = abs(degrees)
            let d = floor(whole)
            whole = (whole - d) * 60
            let m = floor(whole)
            let s = (whole - m) * 60
            var encoded = Data()
            for value in [d, m, s] {
                encoded.append(u32(UInt32(value * 1000)))
                encoded.append(u32(1000))
            }
            return encoded
        }
        let header = 2 + 4 * 12 + 4
        let latOffset = UInt32(absoluteOffset + header)
        let lonOffset = latOffset + 24
        let latRef = UInt32(gps.latitude < 0 ? 83 : 78)
        let lonRef = UInt32(gps.longitude < 0 ? 87 : 69)
        var data = Data()
        data.append(u16(4))
        data.append(entry(tag: 1, type: 2, count: 2, value: latRef))
        data.append(entry(tag: 2, type: 5, count: 3, value: latOffset))
        data.append(entry(tag: 3, type: 2, count: 2, value: lonRef))
        data.append(entry(tag: 4, type: 5, count: 3, value: lonOffset))
        data.append(u32(0))
        data.append(coordinate(gps.latitude))
        data.append(coordinate(gps.longitude))
        return data
    }
}
