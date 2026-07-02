import WiFiModel

/// Map a radiotap primary-channel frequency (MHz) to an 802.11 channel number.
/// Returns nil for frequencies outside the known 2.4/5/6 GHz plans.
public func channelNumber(forFrequencyMHz freq: Int) -> Int? {
    switch freq {
    case 2484:              return 14
    case 2412...2472:       return (freq - 2407) / 5
    case 5160...5885:       return (freq - 5000) / 5
    case 5955...7115:       return (freq - 5950) / 5
    default:                return nil
    }
}

/// Band for a primary-channel frequency (MHz), or nil if unknown.
public func band(forFrequencyMHz freq: Int) -> Band? {
    switch freq {
    case 2412...2484:       return .ghz2_4
    case 5160...5885:       return .ghz5
    case 5955...7115:       return .ghz6
    default:                return nil
    }
}
