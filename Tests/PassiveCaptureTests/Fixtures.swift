import Foundation

/// Hand-crafted, byte-exact fixtures. See inline comments for field derivations.
enum Fixtures {
    /// 16-byte radiotap header:
    /// version=0, pad=0, it_len=16, present=0x6E (Flags|Rate|Channel|dBmSignal|dBmNoise).
    /// Flags=0x00 (FCS ok), Rate=0x0C (12*500kbps = 6 Mbps),
    /// Channel freq=2412 (LE 6C 09), channel flags=0x00C0,
    /// signal=-50 dBm (0xCE), noise=-95 dBm (0xA1).
    static let radiotapHeader: [UInt8] = [
        0x00, 0x00,             // version, pad
        0x10, 0x00,             // it_len = 16
        0x6E, 0x00, 0x00, 0x00, // it_present
        0x00,                   // Flags
        0x0C,                   // Rate (6 Mbps)
        0x6C, 0x09,             // Channel frequency 2412
        0xC0, 0x00,             // Channel flags
        0xCE,                   // signal -50 dBm
        0xA1,                   // noise -95 dBm
    ]

    /// 802.11 beacon MAC header + fixed params + one SSID IE ("Test").
    /// FC=0x8000 (mgmt/beacon), dur=0, addr1=broadcast, addr2=addr3=00:11:22:33:44:55,
    /// seq=0, timestamp=0, interval=0x0064, caps=0x0001, SSID IE = 00 04 "Test".
    static let beaconVisible: [UInt8] = [
        0x80, 0x00,                         // frame control (beacon)
        0x00, 0x00,                         // duration
        0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, // addr1 (DA broadcast)
        0x00, 0x11, 0x22, 0x33, 0x44, 0x55, // addr2 (SA)
        0x00, 0x11, 0x22, 0x33, 0x44, 0x55, // addr3 (BSSID)
        0x00, 0x00,                         // sequence control
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // timestamp
        0x64, 0x00,                         // beacon interval
        0x01, 0x00,                         // capabilities
        0x00, 0x04, 0x54, 0x65, 0x73, 0x74, // SSID IE: "Test"
    ]

    /// Same beacon but with a zero-length (hidden) SSID IE.
    static let beaconHidden: [UInt8] = Array(beaconVisible[0..<36]) + [0x00, 0x00]

    /// A retried beacon: FC flags byte (octet 1) has the Retry bit (0x08) set.
    static let beaconVisibleRetry: [UInt8] = {
        var f = beaconVisible; f[1] = 0x08; return f
    }()

    /// A probe request from a client 66:77:88:99:AA:BB carrying SSID "Test".
    /// FC=0x4000 (mgmt/probe-req, subtype 4). No fixed params; body is IEs.
    static let probeRequest: [UInt8] = [
        0x40, 0x00,                         // frame control (probe request)
        0x00, 0x00,                         // duration
        0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, // addr1 (broadcast)
        0x66, 0x77, 0x88, 0x99, 0xAA, 0xBB, // addr2 (client)
        0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, // addr3
        0x00, 0x00,                         // sequence control
        0x00, 0x04, 0x54, 0x65, 0x73, 0x74, // SSID IE: "Test"
    ]

    /// Prepend the radiotap header to an 802.11 frame to form a full captured frame.
    static func frame(_ dot11: [UInt8]) -> [UInt8] { radiotapHeader + dot11 }
}
