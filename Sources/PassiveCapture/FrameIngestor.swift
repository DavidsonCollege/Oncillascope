import Foundation
import WiFiModel
import IEParser

public struct CapturedFrame: Sendable {
    public var radiotap: RadiotapInfo
    public var header: Dot11Header
    public var channel: Int?
    public var ies: ParsedIEs?
    public var rawLength: Int
}

/// Orchestrates the decode of one raw captured frame (radiotap + 802.11). Reuses the
/// existing `IEParser` for management-frame tagged parameters — no IE decoding is
/// duplicated here.
public enum FrameIngestor {
    public static func ingest(_ raw: [UInt8]) -> CapturedFrame? {
        guard let rt = RadiotapParser.parse(raw),
              rt.headerLength <= raw.count else { return nil }
        let dot11 = Array(raw[rt.headerLength...])
        guard let header = Dot11FrameParser.parse(dot11) else { return nil }

        let channel = rt.frequencyMHz.flatMap(channelNumber(forFrequencyMHz:))
        let bnd = rt.frequencyMHz.flatMap(band(forFrequencyMHz:)) ?? .unknown

        var ies: ParsedIEs?
        if let r = header.taggedBodyRange, r.lowerBound <= dot11.count {
            let clamped = r.lowerBound..<min(r.upperBound, dot11.count)
            ies = IEParser.parse(Array(dot11[clamped]), band: bnd)
        }
        return CapturedFrame(radiotap: rt, header: header, channel: channel,
                             ies: ies, rawLength: raw.count)
    }
}
