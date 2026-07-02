import Foundation

/// The 802.11 frame-control type field (management/control/data), or unknown for reserved values.
public enum Dot11Type: Equatable, Sendable { case management, control, data, unknown }

/// Parsed fields from an 802.11 MAC header.
public struct Dot11Header: Equatable, Sendable {
    public var type: Dot11Type
    public var subtype: UInt8
    public var isRetry: Bool
    public var isProtected: Bool
    public var addr1: String?
    public var addr2: String?
    public var addr3: String?
    public var taggedBodyRange: Range<Int>?
}

/// Well-known management-frame subtype values.
public enum Dot11Subtype {
    public static let assocReq: UInt8 = 0, assocResp: UInt8 = 1
    public static let reassocReq: UInt8 = 2, reassocResp: UInt8 = 3
    public static let probeReq: UInt8 = 4, probeResp: UInt8 = 5
    public static let beacon: UInt8 = 8
}

/// Parse the 802.11 MAC header. Bounds-checked: returns nil if the mandatory 24-byte header
/// isn't fully present.
public enum Dot11FrameParser {
    private static let macHeaderLength = 24
    // Management subtypes whose body begins with 12 bytes of fixed params before the IEs.
    private static let fixedParamSubtypes: Set<UInt8> =
        [Dot11Subtype.beacon, Dot11Subtype.probeResp,
         Dot11Subtype.assocResp, Dot11Subtype.reassocResp]

    public static func parse(_ bytes: [UInt8]) -> Dot11Header? {
        guard bytes.count >= macHeaderLength else { return nil }
        let fc0 = bytes[0], fc1 = bytes[1]
        let type: Dot11Type
        switch (fc0 >> 2) & 0x3 {
        case 0: type = .management
        case 1: type = .control
        case 2: type = .data
        default: type = .unknown
        }
        let subtype = (fc0 >> 4) & 0xF
        let isRetry = (fc1 & 0x08) != 0
        let isProtected = (fc1 & 0x40) != 0

        func mac(_ start: Int) -> String {
            bytes[start..<start+6].map { String(format: "%02X", $0) }.joined(separator: ":")
        }
        let addr1 = mac(4), addr2 = mac(10), addr3 = mac(16)

        // Body offset: management frames put IEs after the 24-byte header, plus 12 fixed
        // bytes for the subtypes that carry them (beacon/probe-resp/assoc-resp).
        var bodyStart = macHeaderLength
        if type == .management, fixedParamSubtypes.contains(subtype) { bodyStart += 12 }
        let taggedBodyRange: Range<Int>? =
            (type == .management && bodyStart <= bytes.count) ? bodyStart..<bytes.count : nil

        return Dot11Header(type: type, subtype: subtype, isRetry: isRetry,
                           isProtected: isProtected, addr1: addr1, addr2: addr2,
                           addr3: addr3, taggedBodyRange: taggedBodyRange)
    }
}
