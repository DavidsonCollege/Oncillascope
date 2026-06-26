import Foundation

/// A Wi-Fi channel: number, width, and band.
public struct ChannelInfo: Codable, Sendable, Hashable {
    public var number: Int
    public var width: ChannelWidth
    public var band: Band

    public init(number: Int, width: ChannelWidth = .unknown, band: Band = .unknown) {
        self.number = number
        self.width = width
        // If the caller did not specify a band, infer from the channel number.
        self.band = band == .unknown ? Band.from(channel: number) : band
    }

    /// Human label, e.g. "36 (80 MHz)".
    public var label: String {
        width == .unknown ? "\(number)" : "\(number) (\(width.rawValue) MHz)"
    }

    /// Center frequency in MHz for the primary 20 MHz channel.
    ///
    /// 6 GHz and 2.4/5 GHz use different formulas. 6 GHz channels share the 1...233
    /// numbering with 5 GHz, so the band must be known to disambiguate.
    public var primaryCenterMHz: Int? {
        switch band {
        case .ghz2_4:
            if number == 14 { return 2484 }
            guard (1...13).contains(number) else { return nil }
            return 2407 + number * 5
        case .ghz5:
            guard (1...196).contains(number) else { return nil }
            return 5000 + number * 5
        case .ghz6:
            guard (1...233).contains(number) else { return nil }
            return 5950 + number * 5
        case .unknown:
            return nil
        }
    }

    /// The span of frequencies this channel occupies, used by the channel-map view to
    /// draw overlap. Returns (lowMHz, highMHz) for the full bonded width.
    public var frequencySpanMHz: (low: Int, high: Int)? {
        guard let center = primaryCenterMHz else { return nil }
        // For bonded channels the primary-channel center is offset from the bonded
        // center, but for an occupancy overlap view, anchoring the full width on the
        // primary center is a good-enough advisory visualization.
        let half = max(width.rawValue, 20) / 2
        return (center - half, center + half)
    }
}
