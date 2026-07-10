import Foundation

/// Merges successive scan passes into one stable view of the RF neighborhood.
///
/// CoreWLAN active scans are lossy: a marginal-signal BSS is routinely heard on one
/// pass and missed on the next, so replacing the network list wholesale per scan makes
/// weak networks flicker in and out of the UI. The aggregator instead keeps every BSS
/// for `ttl` seconds after it was last heard (commercial analyzers do the same),
/// updating entries in place when a fresh observation arrives and exposing per-entry
/// staleness so the UI can dim rows that missed the latest pass.
public struct ScanAggregator: Sendable {

    /// How long a BSS survives after it was last heard.
    public let ttl: TimeInterval

    /// Entries older than this are "stale" — still listed, but missed at least the
    /// most recent scan pass (default auto-scan cadence is 20 s).
    public let freshWindow: TimeInterval

    private var entries: [String: (obs: BSSObservation, lastSeen: Date)] = [:]

    public init(ttl: TimeInterval = 90, freshWindow: TimeInterval = 25) {
        self.ttl = ttl
        self.freshWindow = freshWindow
    }

    /// Merge one scan pass: fresh observations replace their previous entry (latest
    /// data wins), and anything not heard within `ttl` of `now` is evicted.
    public mutating func ingest(_ scan: [BSSObservation], at now: Date) {
        for obs in scan {
            entries[obs.id] = (obs, now)
        }
        entries = entries.filter { now.timeIntervalSince($0.value.lastSeen) <= ttl }
    }

    /// All live entries as of `now` (entries past `ttl` are excluded even if no scan
    /// has run since they expired — aging applies when scanning stops too).
    public func observations(at now: Date) -> [BSSObservation] {
        entries.values
            .filter { now.timeIntervalSince($0.lastSeen) <= ttl }
            .map(\.obs)
    }

    public func lastSeen(id: String) -> Date? {
        entries[id]?.lastSeen
    }

    /// True when the BSS was heard, but not within the fresh window (i.e. it missed
    /// the most recent pass and is coasting on its ttl).
    public func isStale(id: String, at now: Date) -> Bool {
        guard let seen = entries[id]?.lastSeen else { return false }
        return now.timeIntervalSince(seen) > freshWindow
    }

    public mutating func reset() {
        entries.removeAll()
    }
}
