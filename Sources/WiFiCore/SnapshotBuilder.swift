#if canImport(CoreWLAN)
import CoreWLAN
import Foundation
import WiFiModel
import IEParser
import OUIResolver
import WdutilBridge

/// Fuses the three data sources (spec §2 net design principle) into model types:
/// CoreWLAN identity + live stats, parsed IE capabilities, and `wdutil` PHY metrics.
public enum SnapshotBuilder {

    /// Build one `BSSObservation` from a scanned `CWNetwork`, decoding its raw IEs.
    public static func observation(from net: CWNetwork, resolver: OUIResolver) -> BSSObservation {
        let channel = CWMappers.channel(net.wlanChannel)
        let ieBytes: [UInt8] = net.informationElementData.map { Array($0) } ?? []
        let parsed = IEParser.parse(ieBytes, band: channel.band)

        // Prefer CoreWLAN's channel; fall back to the DS Parameter Set from IEs.
        var resolvedChannel = channel
        if resolvedChannel.number == 0, let dsCh = parsed.primaryChannel {
            resolvedChannel = ChannelInfo(number: dsCh)
        }

        return BSSObservation(
            ssid: net.ssid,
            bssid: net.bssid,
            vendor: resolver.vendor(for: net.bssid),
            rssi: net.rssiValue,
            noise: net.noiseMeasurement,
            channel: resolvedChannel,
            security: CWMappers.networkSecurity(net),
            phyGeneration: parsed.generation,
            beaconInterval: net.beaconInterval,
            isIBSS: net.ibss,
            countryCode: net.countryCode ?? parsed.countryCode,
            bssLoad: parsed.bssLoad,
            capabilities: parsed.capabilities,
            maxTheoreticalRate: parsed.maxTheoreticalRate,
            rawIEs: parsed.elements
        )
    }

    /// Merge `wdutil` PHY metrics into a CoreWLAN-derived `ConnectionInfo`.
    /// Identity fields stay from CoreWLAN; PHY fields (MCS/NSS/GI/CCA) come from wdutil.
    public static func merge(_ base: ConnectionInfo, with m: WdutilMetrics) -> ConnectionInfo {
        var out = base
        out.mcsIndex = m.mcsIndex
        out.nss = m.nss
        out.guardInterval = m.guardIntervalNS
        out.cca = m.cca
        // wdutil may know a newer PHY generation than CoreWLAN (ax/be).
        if let phy = m.phyMode, phy > base.phyMode { out.phyMode = phy }
        // Refine width/band if CoreWLAN was unsure.
        if base.channel.width == .unknown, let w = m.channelWidth {
            out.channel.width = w
        }
        if base.countryCode == nil { out.countryCode = m.countryCode }

        // Derive the theoretical max rate now that we know MCS/NSS/width/GI.
        if let mcs = m.mcsIndex, let nss = m.nss {
            out.maxTheoreticalRate = PHYRate.maxRateMbps(
                generation: out.phyMode,
                mcs: mcs,
                nss: nss,
                width: out.channel.width,
                guardIntervalNS: m.guardIntervalNS
            )
        }
        return out
    }
}
#endif
