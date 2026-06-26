import XCTest
@testable import IEParser
import WiFiModel

final class IEParserTests: XCTestCase {

    // MARK: - Fixture builders

    /// Build a standard element: [id][len][payload...].
    func el(_ id: UInt8, _ payload: [UInt8]) -> [UInt8] {
        [id, UInt8(payload.count)] + payload
    }
    /// Build an extension element: [255][len][extID][payload...].
    func ext(_ extID: UInt8, _ payload: [UInt8]) -> [UInt8] {
        [255, UInt8(payload.count + 1), extID] + payload
    }

    func ssidIE(_ s: String) -> [UInt8] { el(0, Array(s.utf8)) }
    func dsIE(_ ch: UInt8) -> [UInt8] { el(3, [ch]) }
    func countryIE() -> [UInt8] { el(7, Array("US ".utf8) + [1, 11, 30]) }
    func bssLoadIE() -> [UInt8] { el(11, [0x0A, 0x00, 128, 0x64, 0x00]) } // 10 sta, ~50%, 100

    /// HT cap: 40 MHz + SGI20, 2 spatial streams, MCS 0–7.
    func htIE() -> [UInt8] {
        var p = [UInt8](repeating: 0, count: 26)
        p[0] = 0x22            // bit1 (40 MHz) + bit5 (SGI20)
        p[3] = 0xFF            // MCS 0–7 stream 1
        p[4] = 0xFF            // MCS 8–15 stream 2
        return el(45, p)
    }

    /// VHT cap: 160 MHz + SGI80, 2 streams, MCS 0–9.
    func vhtIE() -> [UInt8] {
        var p = [UInt8](repeating: 0, count: 12)
        p[0] = 0x24            // widthSet=1 (160) + bit5 (SGI80)
        p[4] = 0xFA            // streams 0,1 = code 2 (MCS0-9); 2,3 = 3 (none)
        p[5] = 0xFF            // streams 4–7 = none
        return el(191, p)
    }

    /// HE cap: 160 MHz, 2 streams, MCS 0–11.
    func heIE() -> [UInt8] {
        var p = [UInt8](repeating: 0, count: 21)
        p[6] = 0x08            // PHY cap byte0: bit3 → 160 MHz in 5/6
        p[17] = 0xFA           // RX MCS map low: streams 0,1 = code2 (MCS0-11)
        p[18] = 0xFF           // streams 4–7 none
        return ext(35, p)      // ext() supplies the extID; payload is the HE body
    }

    // MARK: - TLV walk

    func testParsesFlatElementList() {
        let blob = ssidIE("HomeWiFi") + dsIE(36) + bssLoadIE()
        let els = IEParser.parseElements(blob)
        XCTAssertEqual(els.count, 3)
        XCTAssertEqual(els[0].elementID, 0)
        XCTAssertEqual(els[0].name, "SSID")
        XCTAssertEqual(els[1].elementID, 3)
        XCTAssertEqual(els[2].elementID, 11)
    }

    func testTruncatedTrailingElementIsDropped() {
        // Valid SSID then a header claiming 10 bytes with only 2 present.
        let blob = ssidIE("X") + [45, 10, 0x01, 0x02]
        let els = IEParser.parseElements(blob)
        XCTAssertEqual(els.count, 1)         // truncated HT element dropped, no crash
        XCTAssertEqual(els[0].name, "SSID")
    }

    func testEmptyInputIsSafe() {
        XCTAssertTrue(IEParser.parseElements([]).isEmpty)
        XCTAssertEqual(IEParser.parse([]).generation, .unknown)
    }

    // MARK: - Individual decoders

    func testSSIDDecode() {
        let p = IEParser.parse(ssidIE("HomeWiFi"))
        XCTAssertEqual(p.ssid, "HomeWiFi")
    }

    func testDSParameterChannel() {
        XCTAssertEqual(IEParser.parse(dsIE(149)).primaryChannel, 149)
    }

    func testCountryDecode() {
        let p = IEParser.parse(countryIE())
        XCTAssertEqual(p.countryCode, "US")
    }

    func testBSSLoadDecode() {
        let load = IEParser.parse(bssLoadIE()).bssLoad
        XCTAssertEqual(load?.stationCount, 10)
        XCTAssertEqual(load?.channelUtilization ?? 0, 50.2, accuracy: 0.1)
        XCTAssertEqual(load?.availableAdmissionCapacity, 100)
    }

    func testHTCapabilities() {
        let p = IEParser.parse(htIE())
        XCTAssertEqual(p.generation, .n)
        XCTAssertEqual(p.capabilities?.spatialStreams, 2)
        XCTAssertEqual(p.capabilities?.maxMCS, 7)
        XCTAssertEqual(p.capabilities?.maxWidth, .mhz40)
        XCTAssertEqual(p.capabilities?.shortGuardInterval, true)
    }

    func testVHTCapabilities() {
        let p = IEParser.parse(vhtIE())
        XCTAssertEqual(p.generation, .ac)
        XCTAssertEqual(p.capabilities?.spatialStreams, 2)
        XCTAssertEqual(p.capabilities?.maxMCS, 9)
        XCTAssertEqual(p.capabilities?.maxWidth, .mhz160)
        // VHT160 MCS9 2SS SGI ≈ 1733.3 Mb/s
        XCTAssertEqual(p.maxTheoreticalRate ?? 0, 1733.3, accuracy: 1.0)
    }

    func testHECapabilities() {
        let p = IEParser.parse(heIE())
        XCTAssertEqual(p.generation, .ax)
        XCTAssertEqual(p.capabilities?.spatialStreams, 2)
        XCTAssertEqual(p.capabilities?.maxMCS, 11)
        XCTAssertEqual(p.capabilities?.supports160MHz, true)
        // HE160 MCS11 2SS 0.8µs GI ≈ 2402 Mb/s
        XCTAssertEqual(p.maxTheoreticalRate ?? 0, 2402, accuracy: 5.0)
    }

    // MARK: - Generation precedence

    func testNewestGenerationWins() {
        // A modern AP advertises HT + VHT + HE together; HE (ax) must win.
        let blob = ssidIE("Net") + dsIE(36) + countryIE() + bssLoadIE()
            + htIE() + vhtIE() + heIE()
        let p = IEParser.parse(blob)
        XCTAssertEqual(p.generation, .ax)
        XCTAssertEqual(p.ssid, "Net")
        XCTAssertEqual(p.primaryChannel, 36)
        XCTAssertNotNil(p.bssLoad)
        XCTAssertEqual(p.capabilities?.maxMCS, 11)
    }

    func testInspectorSummariesPopulated() {
        let els = IEParser.parseElements(bssLoadIE())
        XCTAssertTrue(els[0].summary.contains { $0.contains("Stations: 10") })
        XCTAssertFalse(els[0].hexDump.isEmpty)
    }
}
