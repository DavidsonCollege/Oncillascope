import Foundation
import WiFiModel

/// Decoded result of parsing a BSS's full Information Element blob.
public struct ParsedIEs: Sendable {
    public var elements: [InformationElement] = []
    public var ssid: String?
    public var primaryChannel: Int?
    public var countryCode: String?
    public var bssLoad: BSSLoad?
    public var capabilities: CapabilitySet?
    public var generation: PHYGeneration = .unknown
    /// Theoretical max PHY rate (Mb/s) derived from the highest-generation caps present.
    public var maxTheoreticalRate: Double?
}

/// Pure-Swift 802.11 Information Element decoder.
///
/// Parses the `[id][len][payload]` TLV stream (Extension elements use id 255 with the
/// first payload byte as the extension id), produces a decoded element tree for the
/// inspector, and fuses the capability elements into a single `CapabilitySet` plus a
/// derived theoretical PHY rate.
public enum IEParser {

    /// Walk the raw blob into a flat list of decoded elements. Truncated trailing
    /// elements are dropped rather than throwing.
    public static func parseElements(_ data: [UInt8]) -> [InformationElement] {
        var reader = ByteReader(data)
        var out: [InformationElement] = []
        while reader.remaining >= 2 {
            guard let id = reader.u8(), let len = reader.u8() else { break }
            guard let payload = reader.take(Int(len)) else { break }  // truncated → stop

            var extID: Int?
            var body = payload
            if id == 255, let first = payload.first {
                extID = Int(first)
                body = Array(payload.dropFirst())
            }
            let name = ElementNames.name(id: Int(id), extID: extID)
            let summary = summarize(id: Int(id), extID: extID, payload: body)
            out.append(InformationElement(
                elementID: Int(id),
                extensionID: extID,
                name: name,
                bytes: body,
                summary: summary
            ))
        }
        return out
    }

    /// Full parse: element tree + fused capabilities + derived metrics.
    /// - Parameter band: the band from CoreWLAN, used to disambiguate 6 GHz.
    public static func parse(_ data: [UInt8], band: Band = .unknown) -> ParsedIEs {
        let elements = parseElements(data)
        var result = ParsedIEs(elements: elements)

        var ht: Decoders.HTInfo?
        var vht: Decoders.VHTInfo?
        var he: Decoders.HEInfo?
        var sawHE6GHz = false
        var ehtWidth: ChannelWidth?
        var sawEHT = false

        for el in elements {
            switch (el.elementID, el.extensionID) {
            case (0, _):
                result.ssid = String(bytes: el.bytes, encoding: .utf8)
            case (3, _):
                result.primaryChannel = Decoders.dsParameterChannel(el.bytes)
            case (7, _):
                result.countryCode = Decoders.country(el.bytes)?.code
            case (11, _):
                result.bssLoad = Decoders.bssLoad(el.bytes)
            case (45, _):
                ht = Decoders.htCapabilities(el.bytes)
            case (191, _):
                vht = Decoders.vhtCapabilities(el.bytes)
            case (255, 35):
                he = Decoders.heCapabilities(el.bytes)
            case (255, 59):
                sawHE6GHz = true
            case (255, 106):
                sawEHT = true
                ehtWidth = Decoders.ehtOperationWidth(el.bytes)
            case (255, 108):
                sawEHT = true
            default:
                break
            }
        }

        // Pick the newest generation present and build the fused capability set.
        if sawEHT {
            result.generation = .be
            let width = ehtWidth ?? he?.width ?? vht?.width ?? .mhz160
            let nss = he?.nss ?? vht?.nss ?? 1
            result.capabilities = CapabilitySet(
                generation: .be, spatialStreams: nss, maxMCS: 13, maxWidth: width,
                shortGuardInterval: false, supportsMUMIMO: vht?.muMIMO ?? true,
                supportsOFDMA: true, supports160MHz: width.rawValue >= 160
            )
            result.maxTheoreticalRate = PHYRate.maxRateMbps(
                generation: .be, mcs: 13, nss: nss, width: width, guardIntervalNS: 800)
        } else if let he {
            result.generation = .ax
            result.capabilities = CapabilitySet(
                generation: .ax, spatialStreams: he.nss, maxMCS: he.maxMCS, maxWidth: he.width,
                shortGuardInterval: false, supportsMUMIMO: vht?.muMIMO ?? true,
                supportsOFDMA: he.ofdma, supports160MHz: he.supports160)
            result.maxTheoreticalRate = PHYRate.maxRateMbps(
                generation: .ax, mcs: he.maxMCS, nss: he.nss, width: he.width, guardIntervalNS: 800)
            _ = sawHE6GHz
        } else if let vht {
            result.generation = .ac
            result.capabilities = CapabilitySet(
                generation: .ac, spatialStreams: vht.nss, maxMCS: vht.maxMCS, maxWidth: vht.width,
                shortGuardInterval: vht.shortGI, supportsMUMIMO: vht.muMIMO,
                supportsOFDMA: false, supports160MHz: vht.width.rawValue >= 160)
            result.maxTheoreticalRate = PHYRate.maxRateMbps(
                generation: .ac, mcs: vht.maxMCS, nss: vht.nss, width: vht.width,
                guardIntervalNS: vht.shortGI ? 400 : 800)
        } else if let ht {
            result.generation = .n
            result.capabilities = CapabilitySet(
                generation: .n, spatialStreams: ht.nss, maxMCS: ht.maxMCS, maxWidth: ht.width,
                shortGuardInterval: ht.shortGI, supportsMUMIMO: false, supportsOFDMA: false,
                supports160MHz: false)
            result.maxTheoreticalRate = PHYRate.maxRateMbps(
                generation: .n, mcs: ht.maxMCS, nss: ht.nss, width: ht.width,
                guardIntervalNS: ht.shortGI ? 400 : 800)
        }

        _ = band  // reserved for 6 GHz channel disambiguation by callers
        return result
    }

    // MARK: - Per-element human-readable summaries (for the inspector)

    static func summarize(id: Int, extID: Int?, payload: [UInt8]) -> [String] {
        switch (id, extID) {
        case (0, _):
            let ssid = String(bytes: payload, encoding: .utf8) ?? ""
            return [ssid.isEmpty ? "<hidden / broadcast>" : "SSID: \(ssid)"]
        case (1, _), (50, _):
            let rates = Decoders.supportedRates(payload)
            return rates.map { "\($0.mbps) Mb/s\($0.basic ? " (basic)" : "")" }
        case (3, _):
            return Decoders.dsParameterChannel(payload).map { ["Primary channel: \($0)"] } ?? []
        case (7, _):
            return Decoders.country(payload)?.lines ?? []
        case (11, _):
            guard let load = Decoders.bssLoad(payload) else { return [] }
            return [
                "Stations: \(load.stationCount)",
                "Channel utilization: \(load.channelUtilization)%",
                "Admission capacity: \(load.availableAdmissionCapacity)",
            ]
        case (45, _):
            guard let ht = Decoders.htCapabilities(payload) else { return [] }
            return [
                "Spatial streams: \(ht.nss)", "Max MCS: \(ht.maxMCS)",
                "Channel width: \(ht.width.label)", "Short GI: \(ht.shortGI ? "yes" : "no")",
            ]
        case (191, _):
            guard let v = Decoders.vhtCapabilities(payload) else { return [] }
            return [
                "Spatial streams: \(v.nss)", "Max MCS: \(v.maxMCS)",
                "Channel width: \(v.width.label)", "Short GI: \(v.shortGI ? "yes" : "no")",
                "MU-MIMO: \(v.muMIMO ? "yes" : "no")",
            ]
        case (192, _):
            return Decoders.vhtOperationWidth(payload).map { ["Operating width: \($0.label)"] } ?? []
        case (255, 35):
            guard let he = Decoders.heCapabilities(payload) else { return ["802.11ax (Wi-Fi 6)"] }
            return [
                "Spatial streams: \(he.nss)", "Max MCS: \(he.maxMCS)",
                "Channel width: \(he.width.label)", "160 MHz: \(he.supports160 ? "yes" : "no")",
                "OFDMA: yes",
            ]
        case (255, 36):
            return ["802.11ax operation"]
        case (255, 106), (255, 108):
            let w = Decoders.ehtOperationWidth(payload)?.label
            return ["802.11be (Wi-Fi 7)"] + (w.map { ["Operating width: \($0)"] } ?? [])
        case (221, _):
            return [Decoders.vendor(payload).label]
        default:
            return []
        }
    }
}
