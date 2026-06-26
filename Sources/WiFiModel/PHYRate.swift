import Foundation

/// Computes the theoretical max PHY data rate of an OFDM Wi-Fi link.
///
/// Uses the standard OFDM rate equation:
///
///     rate(Mb/s) = NSS · N_SD · N_BPSCS · R / T_sym(µs)
///
/// where N_SD is the data-subcarrier count (a function of width + generation),
/// N_BPSCS is bits-per-subcarrier (the modulation), R is the coding rate, and T_sym
/// is the OFDM symbol duration including the guard interval. Verified against the
/// published HT/VHT/HE/EHT MCS rate tables.
public enum PHYRate {

    /// (bits-per-subcarrier, coding-rate) for each MCS index.
    /// MCS 0–9 are HT/VHT; 10–11 add 1024-QAM (HE); 12–13 add 4096-QAM (EHT).
    static let mcsTable: [(bits: Double, coding: Double)] = [
        (1, 1.0 / 2),   // 0  BPSK 1/2
        (2, 1.0 / 2),   // 1  QPSK 1/2
        (2, 3.0 / 4),   // 2  QPSK 3/4
        (4, 1.0 / 2),   // 3  16-QAM 1/2
        (4, 3.0 / 4),   // 4  16-QAM 3/4
        (6, 2.0 / 3),   // 5  64-QAM 2/3
        (6, 3.0 / 4),   // 6  64-QAM 3/4
        (6, 5.0 / 6),   // 7  64-QAM 5/6
        (8, 3.0 / 4),   // 8  256-QAM 3/4
        (8, 5.0 / 6),   // 9  256-QAM 5/6
        (10, 3.0 / 4),  // 10 1024-QAM 3/4
        (10, 5.0 / 6),  // 11 1024-QAM 5/6
        (12, 3.0 / 4),  // 12 4096-QAM 3/4
        (12, 5.0 / 6),  // 13 4096-QAM 5/6
    ]

    /// Data-subcarrier count for HT/VHT (legacy 3.2 µs symbol).
    static func vhtSubcarriers(width: ChannelWidth) -> Int? {
        switch width {
        case .mhz20: return 52
        case .mhz40: return 108
        case .mhz80: return 234
        case .mhz160: return 468
        default: return nil
        }
    }

    /// Data-subcarrier count for HE/EHT (12.8 µs symbol).
    static func heSubcarriers(width: ChannelWidth) -> Int? {
        switch width {
        case .mhz20: return 234
        case .mhz40: return 468
        case .mhz80: return 980
        case .mhz160: return 1960
        case .mhz320: return 3920
        default: return nil
        }
    }

    /// Theoretical max rate in Mb/s, or nil if inputs are out of range.
    ///
    /// - Parameters:
    ///   - generation: PHY generation; selects the symbol model.
    ///   - mcs: MCS index (0...13).
    ///   - nss: number of spatial streams (>= 1).
    ///   - width: channel width.
    ///   - guardIntervalNS: guard interval in nanoseconds (400/800 for HT/VHT;
    ///     800/1600/3200 for HE/EHT). Defaults to the long GI for the generation.
    public static func maxRateMbps(
        generation: PHYGeneration,
        mcs: Int,
        nss: Int,
        width: ChannelWidth,
        guardIntervalNS: Int? = nil
    ) -> Double? {
        guard nss >= 1, mcs >= 0, mcs < mcsTable.count else { return nil }
        let (bits, coding) = mcsTable[mcs]

        switch generation {
        case .legacy11b:
            return 11
        case .legacy11a, .legacy11g:
            return 54
        case .n, .ac:
            // HT caps MCS at 9 per stream (8/9 are VHT 256-QAM; n tops at MCS7 per
            // stream but the math is identical, callers pass a valid MCS).
            guard let nSD = vhtSubcarriers(width: width) else { return nil }
            let gi = Double(guardIntervalNS ?? 800)
            let tSym = 3.2 + gi / 1000.0   // µs
            return Double(nss) * Double(nSD) * bits * coding / tSym
        case .ax, .be:
            guard let nSD = heSubcarriers(width: width) else { return nil }
            let gi = Double(guardIntervalNS ?? 800)
            let tSym = 12.8 + gi / 1000.0  // µs
            return Double(nss) * Double(nSD) * bits * coding / tSym
        case .unknown:
            return nil
        }
    }
}
