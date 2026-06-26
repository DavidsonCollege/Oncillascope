import Foundation
import WiFiModel

/// Per-element structured decoders. Each takes the element *payload* (no id/length
/// header) and returns both human-readable summary lines and any structured data the
/// capability builder needs.
enum Decoders {

    // MARK: - DS Parameter Set (IE 3) — primary channel

    static func dsParameterChannel(_ p: [UInt8]) -> Int? {
        p.first.map(Int.init)
    }

    // MARK: - Supported Rates (IE 1 / 50)

    /// Decode rate bytes into Mb/s. High bit marks a "basic" (mandatory) rate.
    static func supportedRates(_ p: [UInt8]) -> [(mbps: Double, basic: Bool)] {
        p.map { byte in
            let basic = byte & 0x80 != 0
            let units = Double(byte & 0x7F)  // 500 kb/s units
            return (units * 0.5, basic)
        }
    }

    // MARK: - Country (IE 7)

    static func country(_ p: [UInt8]) -> (code: String, lines: [String])? {
        guard p.count >= 3 else { return nil }
        let code = String(bytes: p.prefix(2), encoding: .ascii) ?? "??"
        var lines = ["Country: \(code)"]
        // Following bytes are constraint triplets (first channel, #channels, max dBm).
        var i = 3
        while i + 2 < p.count {
            let first = Int(p[i]); let count = Int(p[i + 1]); let maxPwr = Int(p[i + 2])
            if first >= 201 { break } // operating-class triplet form; skip detail
            lines.append("Ch \(first)–\(first + count - 1): max \(maxPwr) dBm")
            i += 3
        }
        return (code, lines)
    }

    // MARK: - BSS Load (IE 11)

    static func bssLoad(_ p: [UInt8]) -> BSSLoad? {
        guard p.count >= 5 else { return nil }
        let stations = Int(p[0]) | (Int(p[1]) << 8)
        let utilRaw = Int(p[2])                 // 0...255
        let util = Double(utilRaw) / 255.0 * 100.0
        let admission = Int(p[3]) | (Int(p[4]) << 8)
        return BSSLoad(
            stationCount: stations,
            channelUtilization: (util * 10).rounded() / 10,
            availableAdmissionCapacity: admission
        )
    }

    // MARK: - HT (IE 45) — 802.11n

    struct HTInfo {
        var nss: Int
        var maxMCS: Int
        var width: ChannelWidth
        var shortGI: Bool
    }

    static func htCapabilities(_ p: [UInt8]) -> HTInfo? {
        guard p.count >= 18 else { return nil }
        let capInfo = UInt16(p[0]) | (UInt16(p[1]) << 8)
        let supports40 = capInfo.bit(1)
        let sgi = capInfo.bit(5) || capInfo.bit(6)
        // Supported MCS Set starts at byte 3, 16 bytes. First 4 bytes = MCS 0–31,
        // one stream per byte (MCS 0–7 → stream 1, 8–15 → stream 2, ...).
        let mcsBytes = Array(p[3 ..< 3 + 4])
        var nss = 0
        var maxMCS = 0
        for (stream, byte) in mcsBytes.enumerated() where byte != 0 {
            nss = stream + 1
            // highest set bit in this stream's byte → per-stream MCS (0–7)
            for bit in (0...7).reversed() where (byte >> bit) & 1 == 1 {
                maxMCS = bit
                break
            }
        }
        if nss == 0 { nss = 1 }
        return HTInfo(
            nss: nss,
            maxMCS: maxMCS,
            width: supports40 ? .mhz40 : .mhz20,
            shortGI: sgi
        )
    }

    // MARK: - VHT (IE 191) — 802.11ac

    struct VHTInfo {
        var nss: Int
        var maxMCS: Int
        var width: ChannelWidth
        var shortGI: Bool
        var muMIMO: Bool
    }

    static func vhtCapabilities(_ p: [UInt8]) -> VHTInfo? {
        guard p.count >= 12 else { return nil }
        let capInfo = UInt32(p[0]) | (UInt32(p[1]) << 8) | (UInt32(p[2]) << 16) | (UInt32(p[3]) << 24)
        let widthSet = capInfo.bits(2, 2)   // 0: 80, 1: 160, 2: 160+80+80
        let sgi80 = capInfo.bit(5)
        let sgi160 = capInfo.bit(6)
        let muBeamformee = capInfo.bit(19)
        let muBeamformer = capInfo.bit(20)// SU/MU beamforming hints
        let width: ChannelWidth = widthSet >= 1 ? .mhz160 : .mhz80

        // Rx VHT-MCS Map: bytes 4–5, 2 bits/stream, 8 streams. 3 = not supported.
        let rxMap = UInt16(p[4]) | (UInt16(p[5]) << 8)
        var nss = 0
        var maxMCS = 7
        for stream in 0..<8 {
            let code = rxMap.bits(stream * 2, 2)
            if code != 3 {
                nss = stream + 1
                maxMCS = code == 0 ? 7 : (code == 1 ? 8 : 9)
            }
        }
        if nss == 0 { nss = 1 }
        return VHTInfo(
            nss: nss,
            maxMCS: maxMCS,
            width: width,
            shortGI: sgi80 || sgi160,
            muMIMO: muBeamformee || muBeamformer
        )
    }

    static func vhtOperationWidth(_ p: [UInt8]) -> ChannelWidth? {
        guard let first = p.first else { return nil }
        switch first {
        case 0: return .mhz40   // 20 or 40 MHz
        case 1: return .mhz80
        case 2: return .mhz160
        case 3: return .mhz160  // 80+80
        default: return nil
        }
    }

    // MARK: - HE (IE 255 ext 35) — 802.11ax

    struct HEInfo {
        var nss: Int
        var maxMCS: Int
        var width: ChannelWidth
        var ofdma: Bool
        var supports160: Bool
    }

    static func heCapabilities(_ p: [UInt8]) -> HEInfo? {
        // Layout: HE MAC Cap (6) + HE PHY Cap (11) + Supported HE-MCS And NSS Set (>=4)
        guard p.count >= 6 + 11 + 4 else { return nil }
        let phy = Array(p[6 ..< 17])
        // PHY cap byte 0 channel-width-set bits (bit0 reserved):
        //  bit1: 40 MHz in 2.4 GHz; bit2: 40/80 in 5/6; bit3: 160; bit4: 160/80+80
        let widthByte = phy[0]
        let supports160 = (widthByte & 0b0000_1000) != 0 || (widthByte & 0b0001_0000) != 0
        let supports80 = (widthByte & 0b0000_0100) != 0
        let width: ChannelWidth = supports160 ? .mhz160 : (supports80 ? .mhz80 : .mhz20)

        // HE-MCS map for <= 80 MHz: 2 bytes RX + 2 bytes TX at offset 17.
        let rxMap = UInt16(p[17]) | (UInt16(p[18]) << 8)
        var nss = 0
        var maxMCS = 7
        for stream in 0..<8 {
            let code = rxMap.bits(stream * 2, 2)  // 0:MCS0-7 1:0-9 2:0-11 3:none
            if code != 3 {
                nss = stream + 1
                maxMCS = code == 0 ? 7 : (code == 1 ? 9 : 11)
            }
        }
        if nss == 0 { nss = 1 }
        return HEInfo(nss: nss, maxMCS: maxMCS, width: width, ofdma: true, supports160: supports160)
    }

    // MARK: - EHT (IE 255 ext 106 operation / 108 capabilities) — 802.11be

    /// Best-effort EHT width from the EHT Operation element's control/parameters.
    static func ehtOperationWidth(_ p: [UInt8]) -> ChannelWidth? {
        // EHT Operation: 1 byte params, then (if present) Operation Info: control byte
        // whose low 3 bits encode width: 0=20,1=40,2=80,3=160,4=320.
        guard p.count >= 2 else { return nil }
        let params = p[0]
        let infoPresent = (params & 0x01) != 0
        guard infoPresent, p.count >= 2 else { return nil }
        let control = p[1]
        switch control & 0x07 {
        case 0: return .mhz20
        case 1: return .mhz40
        case 2: return .mhz80
        case 3: return .mhz160
        case 4: return .mhz320
        default: return nil
        }
    }

    // MARK: - Vendor Specific (IE 221)

    static func vendor(_ p: [UInt8]) -> (oui: String, label: String) {
        guard p.count >= 3 else { return ("", "Vendor Specific") }
        let oui = p.prefix(3).map { String(format: "%02X", $0) }.joined(separator: "-")
        let type = p.count > 3 ? p[3] : 0
        switch (Array(p.prefix(3)), type) {
        case ([0x00, 0x50, 0xF2], 0x01): return (oui, "WPA (Microsoft)")
        case ([0x00, 0x50, 0xF2], 0x02): return (oui, "WMM/WME (QoS)")
        case ([0x00, 0x50, 0xF2], 0x04): return (oui, "WPS (Wi-Fi Protected Setup)")
        case ([0x00, 0x0F, 0xAC], _):    return (oui, "IEEE 802.11 (RSN)")
        case ([0x00, 0x17, 0xF2], _):    return (oui, "Apple")
        case ([0x50, 0x6F, 0x9A], _):    return (oui, "Wi-Fi Alliance")
        default: return (oui, "Vendor \(oui)")
        }
    }
}
