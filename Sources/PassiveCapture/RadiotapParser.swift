import Foundation

public struct RadiotapInfo: Equatable, Sendable {
    public var headerLength: Int
    public var frequencyMHz: Int?
    public var signalDBm: Int?
    public var noiseDBm: Int?
    public var rateMbps: Double?
    public var badFCS: Bool

    public init(headerLength: Int, frequencyMHz: Int? = nil, signalDBm: Int? = nil,
                noiseDBm: Int? = nil, rateMbps: Double? = nil, badFCS: Bool = false) {
        self.headerLength = headerLength
        self.frequencyMHz = frequencyMHz
        self.signalDBm = signalDBm
        self.noiseDBm = noiseDBm
        self.rateMbps = rateMbps
        self.badFCS = badFCS
    }
}

/// Decode the little-endian radiotap header. Fields are laid out in bit order with
/// per-field alignment; we honor `it_len` and read only the fields we use, skipping the
/// rest. Any read past the end degrades to nil rather than trapping.
public enum RadiotapParser {

    // Radiotap "present" bit positions we care about.
    private enum Bit {
        static let flags = 1, rate = 2, channel = 3, signal = 5, noise = 6
    }
    // Field flag: 0x40 in the Flags field means the FCS failed.
    private static let flagBadFCS: UInt8 = 0x40

    public static func parse(_ bytes: [UInt8]) -> RadiotapInfo? {
        guard bytes.count >= 8 else { return nil }
        let itLen = Int(bytes[2]) | (Int(bytes[3]) << 8)
        guard itLen >= 8 else { return nil }

        // Read the (possibly chained) presence bitmaps.
        var present = UInt32(bytes[4]) | (UInt32(bytes[5]) << 8)
                    | (UInt32(bytes[6]) << 16) | (UInt32(bytes[7]) << 24)
        var offset = 8
        // Extended-presence: high bit set → another 32-bit word follows.
        while (present & (1 << 31)) != 0 {
            guard offset + 4 <= bytes.count else { break }
            present = UInt32(bytes[offset]) | (UInt32(bytes[offset+1]) << 8)
                    | (UInt32(bytes[offset+2]) << 16) | (UInt32(bytes[offset+3]) << 24)
            offset += 4
        }

        var info = RadiotapInfo(headerLength: itLen)
        func has(_ bit: Int) -> Bool { (present & (1 << bit)) != 0 }
        func align(_ n: Int) { if offset % n != 0 { offset += n - (offset % n) } }
        func u8() -> UInt8? { guard offset < bytes.count else { return nil }; defer { offset += 1 }; return bytes[offset] }
        func u16() -> Int? {
            align(2)
            guard offset + 2 <= bytes.count else { return nil }
            defer { offset += 2 }
            return Int(bytes[offset]) | (Int(bytes[offset+1]) << 8)
        }

        if has(Bit.flags) { if let f = u8() { info.badFCS = (f & flagBadFCS) != 0 } }
        if has(Bit.rate)  { if let r = u8() { info.rateMbps = Double(r) * 0.5 } }
        if has(Bit.channel) {
            info.frequencyMHz = u16()
            _ = u16() // channel flags — skipped
        }
        if has(Bit.signal) { if let s = u8() { info.signalDBm = Int(Int8(bitPattern: s)) } }
        if has(Bit.noise)  { if let n = u8() { info.noiseDBm = Int(Int8(bitPattern: n)) } }

        return info
    }
}
