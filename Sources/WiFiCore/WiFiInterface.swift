#if canImport(CoreWLAN)
import CoreWLAN
import Foundation
import WiFiModel
import IEParser
import OUIResolver

/// Thin wrapper over `CWInterface` for the current connection and scanning.
///
/// All blocking CoreWLAN calls (notably `scanForNetworks`) are designed to be invoked
/// from a background task so the UI never stalls (spec §5).
public struct WiFiInterface: Sendable {

    /// Whether a Wi-Fi interface is present and powered on.
    public static var isAvailable: Bool {
        CWWiFiClient.shared().interface()?.powerOn() ?? false
    }

    public init() {}

    private var interface: CWInterface? { CWWiFiClient.shared().interface() }

    // MARK: - Current connection (CoreWLAN-only fields)

    /// Build the CoreWLAN portion of the current connection (no `wdutil` fusion yet).
    public func currentConnection(resolver: OUIResolver = .shared) -> ConnectionInfo? {
        guard let i = interface, i.powerOn(), i.serviceActive() else { return nil }
        let bssid = i.bssid()
        return ConnectionInfo(
            ssid: i.ssid(),
            bssid: bssid,
            vendor: resolver.vendor(for: bssid),
            rssi: i.rssiValue(),
            noise: i.noiseMeasurement(),
            txRate: i.transmitRate(),
            phyMode: CWMappers.phyMode(i.activePHYMode()),
            channel: CWMappers.channel(i.wlanChannel()),
            security: CWMappers.security(i.security()),
            transmitPower: i.transmitPower(),
            countryCode: i.countryCode()
        )
    }

    /// Channels the radio supports, for the channel-map view (spec §3.1).
    public func supportedChannels() -> [ChannelInfo] {
        guard let set = interface?.supportedWLANChannels() else { return [] }
        return set.map { CWMappers.channel($0) }.sorted { $0.number < $1.number }
    }

    /// Radio bands this Mac's Wi-Fi hardware supports, derived from the supported
    /// channel set. Empty when the interface is unavailable (treat as "unknown",
    /// not "unsupported"). Lets the UI distinguish "no 6 GHz networks" from "this
    /// Mac has no 6 GHz radio".
    public func supportedBands() -> Set<Band> {
        guard let set = interface?.supportedWLANChannels() else { return [] }
        return Set(set.map { CWMappers.band($0.channelBand) }).subtracting([.unknown])
    }

    // MARK: - Scan

    public enum ScanError: Error, Sendable { case noInterface; case failed(String) }

    /// Active scan for all nearby networks. Blocking — call off the main thread.
    /// Returns fully-fused `BSSObservation`s (CoreWLAN + IE parse + OUI).
    public func scan(resolver: OUIResolver = .shared) throws -> [BSSObservation] {
        guard let i = interface else { throw ScanError.noInterface }
        let networks: Set<CWNetwork>
        do {
            networks = try i.scanForNetworks(withName: nil)
        } catch {
            throw ScanError.failed(error.localizedDescription)
        }
        return networks.map { SnapshotBuilder.observation(from: $0, resolver: resolver) }
    }

    /// Cached scan results — instant, no radio retune. Used as a fallback / fast path.
    public func cachedScan(resolver: OUIResolver = .shared) -> [BSSObservation] {
        guard let networks = interface?.cachedScanResults() else { return [] }
        return networks.map { SnapshotBuilder.observation(from: $0, resolver: resolver) }
    }
}
#endif
