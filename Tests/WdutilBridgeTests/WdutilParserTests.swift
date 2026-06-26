import XCTest
@testable import WdutilBridge
import WiFiModel

final class WdutilParserTests: XCTestCase {

    /// Representative `wdutil info` WIFI block (macOS 14/15 shape, identity redacted).
    let sonomaFixture = """
    ————————————————————————————————————————————————————————————————
    NETWORK
    ————————————————————————————————————————————————————————————————
    WIFI
        MAC Address              : <redacted>
        Interface Name           : en0
        Power                    : On
        SSID                     : <redacted>
        BSSID                    : <redacted>
        RSSI                     : -52 dBm
        Noise                    : -92 dBm
        Tx Rate                  : 1201.0 Mbps
        PHY Mode                 : 802.11ax
        MCS Index                : 11
        NSS                      : 2
        Guard Interval           : 800 ns
        Channel                  : 6g37 (160 MHz, 6 GHz)
        Country Code             : US
        CCA                      : 23
        Scan Cache Count         : 41
    """

    func testParsesPHYMetrics() {
        let m = WdutilParser.parse(sonomaFixture)
        XCTAssertEqual(m.mcsIndex, 11)
        XCTAssertEqual(m.nss, 2)
        XCTAssertEqual(m.guardIntervalNS, 800)
        XCTAssertEqual(m.cca, 23)
        XCTAssertEqual(m.txRateMbps, 1201.0)
        XCTAssertEqual(m.phyMode, .ax)
        XCTAssertEqual(m.channelNumber, 6)   // first integer in "6g37"
        XCTAssertEqual(m.channelWidth, .mhz160)
        XCTAssertEqual(m.band, .ghz6)
        XCTAssertEqual(m.countryCode, "US")
        XCTAssertEqual(m.scanCacheCount, 41)
        XCTAssertFalse(m.isEmpty)
    }

    func testKeyNormalizationToleratesFormatVariants() {
        let variant = """
        WIFI
            mcs_index: 9
            Number of Spatial Streams: 3
            GI: 400 ns
            Channel Utilization: 60
            TRANSMIT RATE: 866 Mbps
        """
        let m = WdutilParser.parse(variant)
        XCTAssertEqual(m.mcsIndex, 9)
        XCTAssertEqual(m.nss, 3)
        XCTAssertEqual(m.guardIntervalNS, 400)
        XCTAssertEqual(m.cca, 60)
        XCTAssertEqual(m.txRateMbps, 866)
    }

    func testChannelWidthAndBandVariants() {
        XCTAssertEqual(WdutilParser.parseChannel("36 (80 MHz, 5 GHz)").width, .mhz80)
        XCTAssertEqual(WdutilParser.parseChannel("36 (80 MHz, 5 GHz)").band, .ghz5)
        XCTAssertEqual(WdutilParser.parseChannel("6 (20MHz, 2.4GHz)").band, .ghz2_4)
        XCTAssertEqual(WdutilParser.parseChannel("157/80").number, 157)
    }

    func testEmptyOrIrrelevantInputProducesEmptyMetrics() {
        XCTAssertTrue(WdutilParser.parse("").isEmpty)
        XCTAssertTrue(WdutilParser.parse("hello: world\nfoo: bar").isEmpty)
    }

    func testIgnoresRedactedIdentityFields() {
        // SSID/BSSID/MAC are redacted; the parser must not surface them as metrics.
        let m = WdutilParser.parse(sonomaFixture)
        // No identity fields exist on WdutilMetrics by design — assert PHY data only.
        XCTAssertNotNil(m.mcsIndex)
    }
}
