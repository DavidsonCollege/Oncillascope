import Foundation

/// Bounds-checked sequential reader over a byte slice. Every accessor returns nil
/// past the end rather than trapping — IE blobs from the wild are often truncated.
struct ByteReader {
    let bytes: [UInt8]
    private(set) var offset: Int

    init(_ bytes: [UInt8], offset: Int = 0) {
        self.bytes = bytes
        self.offset = offset
    }

    var remaining: Int { max(0, bytes.count - offset) }
    var isAtEnd: Bool { offset >= bytes.count }

    mutating func u8() -> UInt8? {
        guard offset < bytes.count else { return nil }
        defer { offset += 1 }
        return bytes[offset]
    }

    /// Little-endian 16-bit.
    mutating func u16() -> UInt16? {
        guard offset + 1 < bytes.count else { return nil }
        defer { offset += 2 }
        return UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
    }

    /// Little-endian 32-bit.
    mutating func u32() -> UInt32? {
        guard offset + 3 < bytes.count else { return nil }
        defer { offset += 4 }
        return UInt32(bytes[offset])
            | (UInt32(bytes[offset + 1]) << 8)
            | (UInt32(bytes[offset + 2]) << 16)
            | (UInt32(bytes[offset + 3]) << 24)
    }

    mutating func take(_ n: Int) -> [UInt8]? {
        guard n >= 0, offset + n <= bytes.count else { return nil }
        defer { offset += n }
        return Array(bytes[offset ..< offset + n])
    }

    mutating func skip(_ n: Int) {
        offset = min(bytes.count, offset + n)
    }
}

extension UInt16 {
    func bit(_ i: Int) -> Bool { (self >> i) & 1 == 1 }
    /// Extract `count` bits starting at `start` (LSB = bit 0).
    func bits(_ start: Int, _ count: Int) -> Int {
        let mask = (UInt16(1) << count) - 1
        return Int((self >> start) & mask)
    }
}

extension UInt32 {
    func bit(_ i: Int) -> Bool { (self >> i) & 1 == 1 }
    func bits(_ start: Int, _ count: Int) -> Int {
        let mask = (UInt32(1) << count) - 1
        return Int((self >> start) & mask)
    }
}
