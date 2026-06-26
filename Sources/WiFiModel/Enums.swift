import Foundation

/// Radio band a channel lives in. Raw value is the nominal GHz figure used in the UI.
public enum Band: String, Codable, Sendable, CaseIterable, Hashable {
    case ghz2_4 = "2.4 GHz"
    case ghz5 = "5 GHz"
    case ghz6 = "6 GHz"
    case unknown = "Unknown"

    /// Classify a (band-hint, channel-number) pair into a band.
    ///
    /// CoreWLAN exposes a `channelBand` already, but IE-only parses (DS Parameter Set,
    /// HT/HE operation) give us a bare channel number, so we infer from the number.
    public static func from(channel: Int) -> Band {
        switch channel {
        case 1...14: return .ghz2_4
        case 32...177: return .ghz5
        // 6 GHz uses channels 1...233 too, so a bare number is ambiguous; callers that
        // know the band should pass it explicitly. This is a best-effort fallback.
        default: return .unknown
        }
    }
}

/// Channel width in MHz. Matches `CWChannelWidth` plus 320 MHz for Wi-Fi 7.
public enum ChannelWidth: Int, Codable, Sendable, CaseIterable, Hashable {
    case unknown = 0
    case mhz20 = 20
    case mhz40 = 40
    case mhz80 = 80
    case mhz160 = 160
    case mhz320 = 320

    public var label: String {
        self == .unknown ? "—" : "\(rawValue) MHz"
    }
}

/// 802.11 PHY generation. Ordered oldest -> newest so `>` means "newer".
public enum PHYGeneration: Int, Codable, Sendable, CaseIterable, Comparable, Hashable {
    case unknown = 0
    case legacy11b = 1   // 802.11b
    case legacy11a = 2   // 802.11a
    case legacy11g = 3   // 802.11g
    case n = 4           // 802.11n   (Wi-Fi 4)
    case ac = 5          // 802.11ac  (Wi-Fi 5)
    case ax = 6          // 802.11ax  (Wi-Fi 6/6E)
    case be = 7          // 802.11be  (Wi-Fi 7)

    public static func < (lhs: PHYGeneration, rhs: PHYGeneration) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// Short standard label, e.g. "802.11ax".
    public var standardLabel: String {
        switch self {
        case .unknown: return "—"
        case .legacy11b: return "802.11b"
        case .legacy11a: return "802.11a"
        case .legacy11g: return "802.11g"
        case .n: return "802.11n"
        case .ac: return "802.11ac"
        case .ax: return "802.11ax"
        case .be: return "802.11be"
        }
    }

    /// Marketing label, e.g. "Wi-Fi 6".
    public var wifiLabel: String {
        switch self {
        case .n: return "Wi-Fi 4"
        case .ac: return "Wi-Fi 5"
        case .ax: return "Wi-Fi 6"
        case .be: return "Wi-Fi 7"
        default: return standardLabel
        }
    }
}

/// Link-layer security. Mirrors `CWSecurity` groupings.
public enum SecurityMode: String, Codable, Sendable, CaseIterable, Hashable {
    case open = "Open"
    case wep = "WEP"
    case wpaPersonal = "WPA Personal"
    case wpaEnterprise = "WPA Enterprise"
    case wpa2Personal = "WPA2 Personal"
    case wpa2Enterprise = "WPA2 Enterprise"
    case wpa3Personal = "WPA3 Personal"
    case wpa3Enterprise = "WPA3 Enterprise"
    case wpa2wpa3Personal = "WPA2/WPA3 Personal"
    case enhancedOpen = "Enhanced Open (OWE)"
    case unknown = "Unknown"

    /// Whether the network is unencrypted from a client's perspective.
    public var isOpen: Bool {
        self == .open
    }
}
