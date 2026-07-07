import Foundation

/// Resolves the helpdesk email recipient and validates addresses. Pure so it can be unit
/// tested; lives in Telemetry alongside `Exporter` (the export machinery it serves).
public enum HelpdeskRecipient {
    /// Baked default when no managed preference is set.
    public static let defaultAddress = "ti@davidson.edu"
    /// Managed-preference key IT can set (MDM profile / `defaults write`).
    public static let defaultsKey = "helpdeskEmail"

    /// Managed preference (if a non-blank string) else the baked default.
    public static func resolve(_ defaults: UserDefaults) -> String {
        if let v = defaults.string(forKey: defaultsKey) {
            let trimmed = v.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return defaultAddress
    }

    /// Minimal syntactic check: non-empty local part, "@", a domain with a dot, no spaces.
    public static func isValid(_ email: String) -> Bool {
        let parts = email.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return false }
        let local = parts[0], domain = parts[1]
        guard !local.isEmpty, !domain.isEmpty else { return false }
        guard !email.contains(" ") else { return false }
        // domain must have a dot with non-empty labels on both sides
        let labels = domain.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2, labels.allSatisfy({ !$0.isEmpty }) else { return false }
        return true
    }
}
