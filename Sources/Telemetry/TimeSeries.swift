import Foundation
import WiFiModel

/// One sampled point of the current-connection metrics, for charting.
public struct TelemetrySample: Codable, Sendable, Hashable {
    public var timestamp: Date
    public var rssi: Int
    public var noise: Int
    public var txRate: Double
    public var mcsIndex: Int?
    public var cca: Int?
    public var bssid: String?
    public var channel: Int

    public var snr: Int { rssi - noise }

    public init(timestamp: Date, rssi: Int, noise: Int, txRate: Double,
                mcsIndex: Int? = nil, cca: Int? = nil, bssid: String? = nil, channel: Int = 0) {
        self.timestamp = timestamp
        self.rssi = rssi
        self.noise = noise
        self.txRate = txRate
        self.mcsIndex = mcsIndex
        self.cca = cca
        self.bssid = bssid
        self.channel = channel
    }

    /// Build a sample from a fused connection snapshot.
    public init(timestamp: Date, connection: ConnectionInfo) {
        self.init(
            timestamp: timestamp,
            rssi: connection.rssi,
            noise: connection.noise,
            txRate: connection.txRate,
            mcsIndex: connection.mcsIndex,
            cca: connection.cca,
            bssid: connection.bssid,
            channel: connection.channel.number
        )
    }
}

/// A "roam" or "channel change" marker placed on the time axis (spec §4.2).
public struct TimelineMarker: Codable, Sendable, Hashable, Identifiable {
    public enum Kind: String, Codable, Sendable { case roam, channelChange }
    public var id: Date { timestamp }
    public var timestamp: Date
    public var kind: Kind
    public var detail: String

    public init(timestamp: Date, kind: Kind, detail: String) {
        self.timestamp = timestamp
        self.kind = kind
        self.detail = detail
    }
}

/// Rolling store of telemetry samples + auto-detected roam/channel markers.
public final class TelemetryStore: @unchecked Sendable {
    private var buffer: RingBuffer<TelemetrySample>
    private(set) public var markers: [TimelineMarker] = []
    private var lastBSSID: String?
    private var lastChannel: Int?

    /// - Parameter capacity: max samples retained. At 1 Hz, 3600 ≈ one hour.
    public init(capacity: Int = 3600) {
        self.buffer = RingBuffer(capacity: capacity)
    }

    public var samples: [TelemetrySample] { buffer.elements }
    public var count: Int { buffer.count }

    /// Record a sample, auto-emitting a marker on BSSID (roam) or channel change.
    public func record(_ sample: TelemetrySample) {
        if let last = lastBSSID, let now = sample.bssid, last != now {
            markers.append(TimelineMarker(timestamp: sample.timestamp, kind: .roam,
                                          detail: "\(last) → \(now)"))
        }
        if let last = lastChannel, last != sample.channel, sample.channel != 0 {
            markers.append(TimelineMarker(timestamp: sample.timestamp, kind: .channelChange,
                                          detail: "ch \(last) → \(sample.channel)"))
        }
        if let b = sample.bssid { lastBSSID = b }
        if sample.channel != 0 { lastChannel = sample.channel }
        buffer.append(sample)
    }

    /// Samples within the last `window` seconds (for the 1/5/15/60-min selector).
    public func samples(inLast window: TimeInterval, now: Date) -> [TelemetrySample] {
        let cutoff = now.addingTimeInterval(-window)
        return buffer.elements.filter { $0.timestamp >= cutoff }
    }

    public func reset() {
        buffer.removeAll()
        markers.removeAll()
        lastBSSID = nil
        lastChannel = nil
    }
}
