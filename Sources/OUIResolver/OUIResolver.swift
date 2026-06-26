import Foundation

/// Offline MAC OUI → manufacturer resolver.
///
/// Resolution is fully local (spec §3.6, §5 privacy): the lookup table is loaded once
/// from a bundled CSV and never touches the network. Locally-administered / multicast
/// addresses are reported as such rather than mis-resolved.
public final class OUIResolver: @unchecked Sendable {

    /// Shared resolver backed by the bundled curated database.
    public static let shared = OUIResolver()

    private var table: [String: String]

    /// Load from the bundled `oui.csv`. Falls back to an empty table if missing.
    public init() {
        self.table = Self.loadBundled()
    }

    /// Load from an explicit table (used in tests, or for a user-supplied full DB).
    public init(table: [String: String]) {
        self.table = table
    }

    /// Number of OUI entries loaded.
    public var count: Int { table.count }

    /// Merge a larger IEEE registry on top of the bundled set at runtime.
    public func merge(_ extra: [String: String]) {
        table.merge(extra) { _, new in new }
    }

    /// Resolve a BSSID/MAC string ("aa:bb:cc:dd:ee:ff", "AABBCC...", etc.) to a vendor.
    /// Returns nil when unknown; returns a descriptive label for special MACs.
    public func vendor(for mac: String?) -> String? {
        guard let mac, let prefix = Self.normalizedPrefix(mac) else { return nil }

        // A known OUI always wins, even if the I/G or U/L bit is set (multi-BSSID APs
        // sometimes use locally-administered virtual BSSIDs over a real vendor OUI).
        if let known = table[prefix] { return known }

        // Otherwise classify special first-octet bits per IEEE 802 semantics.
        if let firstOctet = UInt8(prefix.prefix(2), radix: 16) {
            if firstOctet & 0x01 == 0x01 { return "Multicast/Group" }
            if firstOctet & 0x02 == 0x02 { return "Locally administered (randomized)" }
        }
        return nil
    }

    // MARK: - Parsing

    /// Normalize a full MAC string to a 6-hex-char uppercase OUI prefix.
    ///
    /// Requires a plausible MAC: only hex digits plus `:`/`-`/space separators, and at
    /// least 12 hex digits (48 bits). This rejects junk like "<redacted>" or "ab",
    /// which would otherwise yield stray hex characters.
    static func normalizedPrefix(_ mac: String) -> String? {
        let allowed = Set("0123456789abcdefABCDEF:- ")
        guard mac.allSatisfy({ allowed.contains($0) }) else { return nil }
        let hex = mac.filter(\.isHexDigit).uppercased()
        guard hex.count >= 12 else { return nil }
        return String(hex.prefix(6))
    }

    /// Parse "HEX6,Vendor" CSV lines into a lookup table. Lines starting with `#` and
    /// blank lines are ignored; vendor fields may themselves contain commas.
    public static func parseCSV(_ text: String) -> [String: String] {
        var out: [String: String] = [:]
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            guard let comma = line.firstIndex(of: ",") else { continue }
            let key = line[..<comma].trimmingCharacters(in: .whitespaces).uppercased()
            let value = line[line.index(after: comma)...].trimmingCharacters(in: .whitespaces)
            guard key.count == 6, key.allSatisfy(\.isHexDigit), !value.isEmpty else { continue }
            out[key] = value
        }
        return out
    }

    private static func loadBundled() -> [String: String] {
        guard let url = Bundle.module.url(forResource: "oui", withExtension: "csv"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return [:]
        }
        return parseCSV(text)
    }
}
