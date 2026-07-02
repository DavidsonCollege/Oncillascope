import XCTest
@testable import PassiveCapture

final class RadiotapParserTests: XCTestCase {
    func testParsesKnownHeader() {
        let info = RadiotapParser.parse(Fixtures.radiotapHeader)
        XCTAssertEqual(info?.headerLength, 16)
        XCTAssertEqual(info?.frequencyMHz, 2412)
        XCTAssertEqual(info?.signalDBm, -50)
        XCTAssertEqual(info?.noiseDBm, -95)
        XCTAssertEqual(info?.rateMbps, 6.0)
        XCTAssertEqual(info?.badFCS, false)
    }
    func testBadFCSFlag() {
        var bytes = Fixtures.radiotapHeader
        bytes[8] = 0x40   // Flags field: bad-FCS bit
        XCTAssertEqual(RadiotapParser.parse(bytes)?.badFCS, true)
    }
    func testTooShortReturnsNil() {
        XCTAssertNil(RadiotapParser.parse([0x00, 0x00, 0x04]))
        XCTAssertNil(RadiotapParser.parse([]))
    }
    func testTruncatedFieldsAreNilNotCrash() {
        // Claims it_len=16 but only 10 bytes present.
        let bytes: [UInt8] = [0x00,0x00, 0x10,0x00, 0x6E,0x00,0x00,0x00, 0x00,0x0C]
        let info = RadiotapParser.parse(bytes)
        XCTAssertEqual(info?.headerLength, 16)
        XCTAssertNil(info?.signalDBm)   // ran off the end; degraded, no trap
    }
}
