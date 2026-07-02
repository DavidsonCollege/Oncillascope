import WiFiModel

public enum ChannelMapping {
    /// Map a radiotap primary-channel frequency (MHz) to an 802.11 channel number.
    /// Covers the common 2.4/5/6 GHz channel plans (5 GHz up to the US U-NII channel
    /// 177 / 5885 MHz). Returns nil for frequencies outside those plans.
    public static func channelNumber(forFrequencyMHz freq: Int) -> Int? {
        switch freq {
        case 2484:              return 14
        case 2412...2472:       return (freq - 2407) / 5
        case 5160...5885:       return (freq - 5000) / 5
        case 5955...7115:       return (freq - 5950) / 5
        default:                return nil
        }
    }

    /// Band for a primary-channel frequency (MHz), or nil if unknown.
    /// Covers the common 2.4/5/6 GHz channel plans; the 5 GHz upper bound is the
    /// US U-NII plan (channel 177 / 5885 MHz) — frequencies above it return nil by design.
    public static func band(forFrequencyMHz freq: Int) -> Band? {
        switch freq {
        case 2412...2472, 2484:  return .ghz2_4
        case 5160...5885:        return .ghz5
        case 5955...7115:        return .ghz6
        default:                 return nil
        }
    }
}
