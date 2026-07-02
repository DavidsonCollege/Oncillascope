import XCTest
@testable import PassiveCapture

final class Dot11FrameParserTests: XCTestCase {
    func testBeaconHeader() {
        let h = Dot11FrameParser.parse(Fixtures.beaconVisible)
        XCTAssertEqual(h?.type, .management)
        XCTAssertEqual(h?.subtype, Dot11Subtype.beacon)
        XCTAssertEqual(h?.isRetry, false)
        XCTAssertEqual(h?.addr2, "00:11:22:33:44:55")
        XCTAssertEqual(h?.addr3, "00:11:22:33:44:55")
        // Beacon fixed params are 12 bytes after the 24-byte MAC header.
        XCTAssertEqual(h?.taggedBodyRange, 36..<Fixtures.beaconVisible.count)
    }
    func testRetryBit() {
        XCTAssertEqual(Dot11FrameParser.parse(Fixtures.beaconVisibleRetry)?.isRetry, true)
    }
    func testProbeRequestBodyStartsAfterHeader() {
        let h = Dot11FrameParser.parse(Fixtures.probeRequest)
        XCTAssertEqual(h?.subtype, Dot11Subtype.probeReq)
        XCTAssertEqual(h?.addr2, "66:77:88:99:AA:BB")
        XCTAssertEqual(h?.taggedBodyRange, 24..<Fixtures.probeRequest.count)  // no fixed params
    }
    func testTruncatedReturnsNil() {
        XCTAssertNil(Dot11FrameParser.parse([0x80, 0x00]))
        XCTAssertNil(Dot11FrameParser.parse([]))
    }
}
