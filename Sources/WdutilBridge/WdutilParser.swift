import Foundation
import WiFiModel

/// PHY-layer metrics parsed from the `WIFI` block of `wdutil info`.
///
/// These are the fields CoreWLAN cannot return (spec §3.3): MCS index, NSS, guard
/// interval, and CCA. Identity fields (SSID/BSSID/MAC) are intentionally ignored —
/// `wdutil` redacts them and CoreWLAN is the source of truth there.
public struct WdutilMetrics: Sendable, Equatable {
    public var mcsIndex: Int?
    public var nss: Int?
    public var guardIntervalNS: Int?
    public var cca: Int?
    public var txRateMbps: Double?
    public var phyMode: PHYGeneration?
    public var channelNumber: Int?
    public var channelWidth: ChannelWidth?
    public var band: Band?
    public var countryCode: String?
    public var scanCacheCount: Int?

    public init() {}

    /// True when none of the PHY-specific fields were found (e.g. not associated, or
    /// the output format changed). Lets the UI show a clear "no data" state.
    public var isEmpty: Bool {
        mcsIndex == nil && nss == nil && guardIntervalNS == nil && cca == nil
            && txRateMbps == nil && phyMode == nil && channelNumber == nil
    }
}

/// Defensive, version-tolerant parser for `wdutil info` text.
///
/// `wdutil`'s format is undocumented and shifts between macOS releases, so the parser
/// is key-driven and whitespace/case tolerant rather than positional.
public enum WdutilParser {

    /// Parse the full `wdutil info` text. Only the WIFI-relevant keys are extracted.
    public static func parse(_ text: String) -> WdutilMetrics {
        var m = WdutilMetrics()

        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            guard !value.isEmpty else { continue }

            switch normalizeKey(key) {
            case "mcsindex", "mcs":
                m.mcsIndex = firstInt(value)
            case "nss", "numberofspatialstreams", "spatialstreams":
                m.nss = firstInt(value)
            case "guardinterval", "gi":
                m.guardIntervalNS = firstInt(value)   // wdutil reports ns
            case "cca", "channelutilization":
                m.cca = firstInt(value)
            case "txrate", "transmitrate", "rate":
                m.txRateMbps = firstDouble(value)
            case "phymode", "phy", "mode":
                m.phyMode = phyMode(value)
            case "channel":
                let parsed = parseChannel(value)
                m.channelNumber = parsed.number
                m.channelWidth = parsed.width
                m.band = parsed.band
            case "countrycode", "country":
                m.countryCode = String(value.prefix(2)).uppercased()
            case "scancachecount", "scancache":
                m.scanCacheCount = firstInt(value)
            default:
                break
            }
        }
        return m
    }

    // MARK: - Helpers

    /// Strip spaces/underscores/hyphens so "MCS Index", "MCS_Index", "mcs-index" match.
    static func normalizeKey(_ key: String) -> String {
        key.filter { !" _-".contains($0) }
    }

    static func firstInt(_ s: String) -> Int? {
        var digits = ""
        for ch in s {
            if ch.isNumber { digits.append(ch) }
            else if !digits.isEmpty { break }
        }
        return Int(digits)
    }

    static func firstDouble(_ s: String) -> Double? {
        var num = ""
        for ch in s {
            if ch.isNumber || ch == "." { num.append(ch) }
            else if !num.isEmpty { break }
        }
        return Double(num)
    }

    static func phyMode(_ s: String) -> PHYGeneration? {
        let v = s.lowercased()
        if v.contains("be") { return .be }
        if v.contains("ax") { return .ax }
        if v.contains("ac") { return .ac }
        if v.contains("11n") || v == "n" || v.contains(" n") { return .n }
        if v.contains("11g") { return .legacy11g }
        if v.contains("11a") { return .legacy11a }
        if v.contains("11b") { return .legacy11b }
        return nil
    }

    /// Parse a channel value like "36 (80 MHz)" or "6 (20MHz, 2.4GHz)" or "157/80".
    static func parseChannel(_ s: String) -> (number: Int?, width: ChannelWidth?, band: Band?) {
        let number = firstInt(s)
        var width: ChannelWidth?
        let lower = s.lowercased()
        for w in [ChannelWidth.mhz320, .mhz160, .mhz80, .mhz40, .mhz20] {
            if lower.contains("\(w.rawValue)mhz") || lower.contains("\(w.rawValue) mhz") {
                width = w; break
            }
        }
        var band: Band?
        if lower.contains("6ghz") || lower.contains("6 ghz") { band = .ghz6 }
        else if lower.contains("5ghz") || lower.contains("5 ghz") { band = .ghz5 }
        else if lower.contains("2.4") { band = .ghz2_4 }
        else if let number { band = Band.from(channel: number) }
        return (number, width, band)
    }
}
