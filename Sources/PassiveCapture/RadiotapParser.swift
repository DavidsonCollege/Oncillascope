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

    private enum Bit { static let flags = 1, rate = 2, channel = 3, signal = 5, noise = 6 }
    private static let flagBadFCS: UInt8 = 0x40

    /// (bit, align, size) for radiotap fields 0...6 — enough to correctly position the
    /// fields we read. Fields at bits > 6 follow those, so they don't shift our offsets.
    private static let fieldLayout: [(bit: Int, align: Int, size: Int)] = [
        (0, 8, 8),  // TSFT
        (1, 1, 1),  // Flags
        (2, 1, 1),  // Rate
        (3, 2, 4),  // Channel (u16 freq + u16 flags)
        (4, 2, 2),  // FHSS
        (5, 1, 1),  // dBm antenna signal
        (6, 1, 1),  // dBm antenna noise
    ]

    public static func parse(_ bytes: [UInt8]) -> RadiotapInfo? {
        guard bytes.count >= 8 else { return nil }
        let itLen = Int(bytes[2]) | (Int(bytes[3]) << 8)
        guard itLen >= 8 else { return nil }

        // Read the (possibly chained) presence bitmaps; fields begin after all of them.
        var present = UInt32(bytes[4]) | (UInt32(bytes[5]) << 8)
                    | (UInt32(bytes[6]) << 16) | (UInt32(bytes[7]) << 24)
        var offset = 8
        while (present & (1 << 31)) != 0 {
            guard offset + 4 <= bytes.count else { return RadiotapInfo(headerLength: itLen) }
            present = UInt32(bytes[offset]) | (UInt32(bytes[offset+1]) << 8)
                    | (UInt32(bytes[offset+2]) << 16) | (UInt32(bytes[offset+3]) << 24)
            offset += 4
        }

        // Advance past EVERY present field that precedes the ones we read (TSFT, FHSS, …),
        // or later offsets are wrong. Clamp reads to it_len: radiotap fields never extend
        // past the header into the 802.11 frame that follows in the same buffer.
        let limit = min(itLen, bytes.count)
        var info = RadiotapInfo(headerLength: itLen)
        for f in fieldLayout where (present & (1 << f.bit)) != 0 {
            if offset % f.align != 0 { offset += f.align - (offset % f.align) }
            guard offset + f.size <= limit else { break }
            switch f.bit {
            case Bit.flags:   info.badFCS = (bytes[offset] & flagBadFCS) != 0
            case Bit.rate:    info.rateMbps = Double(bytes[offset]) * 0.5
            case Bit.channel: info.frequencyMHz = Int(bytes[offset]) | (Int(bytes[offset+1]) << 8)
            case Bit.signal:  info.signalDBm = Int(Int8(bitPattern: bytes[offset]))
            case Bit.noise:   info.noiseDBm = Int(Int8(bitPattern: bytes[offset]))
            default: break
            }
            offset += f.size
        }
        return info
    }
}
