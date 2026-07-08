import Foundation
import WiFiModel

/// CSV / JSON export for scans and time-series (spec §4.6, acceptance criterion 5).
public enum Exporter {

    // MARK: - JSON

    private static func jsonEncoder() -> JSONEncoder {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        enc.dateEncodingStrategy = .iso8601
        return enc
    }

    public static func json(_ snapshot: WiFiSnapshot) throws -> Data {
        try jsonEncoder().encode(snapshot)
    }

    public static func json(_ samples: [TelemetrySample]) throws -> Data {
        try jsonEncoder().encode(samples)
    }

    // MARK: - CSV

    /// CSV for the nearby-networks table. One row per BSS; columns match the table view.
    public static func networksCSV(_ networks: [BSSObservation]) -> String {
        let header = [
            "ssid", "bssid", "vendor", "band", "channel", "width_mhz", "rssi_dbm",
            "noise_dbm", "snr_db", "security", "phy", "channel_util_pct",
            "station_count", "beacon_interval", "country", "max_phy_rate_mbps",
        ]
        var rows = [header.joined(separator: ",")]
        for n in networks {
            let row: [String] = [
                n.ssid ?? "",
                n.bssid ?? "",
                n.vendor ?? "",
                n.channel.band.rawValue,
                String(n.channel.number),
                n.channel.width == .unknown ? "" : String(n.channel.width.rawValue),
                String(n.rssi),
                String(n.noise),
                String(n.snr),
                n.security.rawValue,
                n.phyGeneration.standardLabel,
                n.bssLoad.map { String($0.channelUtilization) } ?? "",
                n.bssLoad.map { String($0.stationCount) } ?? "",
                String(n.beaconInterval),
                n.countryCode ?? "",
                n.maxTheoreticalRate.map { String(format: "%.1f", $0) } ?? "",
            ]
            rows.append(row.map(escape).joined(separator: ","))
        }
        return rows.joined(separator: "\n") + "\n"
    }

    /// CSV for the time-series buffer.
    public static func samplesCSV(_ samples: [TelemetrySample]) -> String {
        let header = ["timestamp", "rssi_dbm", "noise_dbm", "snr_db", "tx_rate_mbps",
                      "mcs_index", "cca_pct", "bssid", "channel"]
        let iso = ISO8601DateFormatter()
        var rows = [header.joined(separator: ",")]
        for s in samples {
            let row: [String] = [
                iso.string(from: s.timestamp),
                String(s.rssi),
                String(s.noise),
                String(s.snr),
                String(format: "%.1f", s.txRate),
                s.mcsIndex.map(String.init) ?? "",
                s.cca.map(String.init) ?? "",
                s.bssid ?? "",
                String(s.channel),
            ]
            rows.append(row.map(escape).joined(separator: ","))
        }
        return rows.joined(separator: "\n") + "\n"
    }

    /// RFC-4180 field escaping plus spreadsheet formula defusing.
    ///
    /// Fields a spreadsheet would evaluate as a formula (leading `=`, `+`, `-`, `@`,
    /// tab, or CR — e.g. a hostile SSID broadcast near the user) are prefixed with a
    /// single quote, the standard CSV-injection mitigation. Plain numbers are exempt
    /// so numeric columns like RSSI ("-70") stay chartable. Then wrap in quotes and
    /// double internal quotes when the field contains a comma, quote, or newline.
    static func escape(_ field: String) -> String {
        var out = field
        if let first = out.first, "=+-@\t\r".contains(first), Double(out) == nil {
            out = "'" + out
        }
        guard out.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else {
            return out
        }
        return "\"" + out.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
