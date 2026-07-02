import XCTest
import IEParser
@testable import PassiveCapture

final class FrameIngestorTests: XCTestCase {
    func testVisibleBeaconResolvesSSIDAndChannel() {
        let f = FrameIngestor.ingest(Fixtures.frame(Fixtures.beaconVisible))
        XCTAssertEqual(f?.channel, 1)
        XCTAssertEqual(f?.radiotap.signalDBm, -50)
        XCTAssertEqual(f?.header.subtype, Dot11Subtype.beacon)
        XCTAssertEqual(f?.ies?.ssid, "Test")
    }
    func testHiddenBeaconHasEmptyOrNilSSID() {
        let f = FrameIngestor.ingest(Fixtures.frame(Fixtures.beaconHidden))
        XCTAssertEqual(f?.header.subtype, Dot11Subtype.beacon)
        XCTAssertTrue((f?.ies?.ssid ?? "").isEmpty)
    }
    func testRadiotapFailureYieldsNil() {
        XCTAssertNil(FrameIngestor.ingest([0x00]))  // too short for radiotap
    }
    func testShortDot11AfterHeaderYieldsNil() {
        // Valid radiotap header but no 802.11 frame after it.
        XCTAssertNil(FrameIngestor.ingest(Fixtures.radiotapHeader))
    }
}
