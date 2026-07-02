import XCTest
@testable import PassiveCapture

final class AccumulatorTests: XCTestCase {
    private func ingest(_ dot11: [UInt8]) -> CapturedFrame {
        FrameIngestor.ingest(Fixtures.frame(dot11))!
    }

    func testHiddenSSIDFilledFromLaterFrame() {
        let acc = PassiveBSSAccumulator()
        acc.ingest(ingest(Fixtures.beaconHidden))          // blank name first
        XCTAssertTrue((acc.bsses["00:11:22:33:44:55"]?.ssid ?? "").isEmpty)
        acc.ingest(ingest(Fixtures.beaconVisible))         // name arrives
        XCTAssertEqual(acc.bsses["00:11:22:33:44:55"]?.ssid, "Test")
        XCTAssertEqual(acc.bsses["00:11:22:33:44:55"]?.hiddenResolved, true)
        XCTAssertEqual(acc.bsses["00:11:22:33:44:55"]?.channel, 1)
    }

    func testAirtimeMath() {
        // 1000 bytes at 6 Mbps = 8000 bits / 6 = 1333.33 µs.
        XCTAssertEqual(frameAirtimeMicroseconds(bytes: 1000, rateMbps: 6), 8000.0/6.0, accuracy: 0.01)
    }

    func testAirtimeUtilizationPerChannel() {
        let acc = AirtimeAccumulator()
        let f = ingest(Fixtures.beaconVisible)             // channel 1, 6 Mbps
        acc.ingest(f); acc.ingest(f)
        let expected = 2 * frameAirtimeMicroseconds(bytes: f.rawLength, rateMbps: 6)
        XCTAssertEqual(acc.busyMicroseconds(channel: 1), expected, accuracy: 0.01)
        // Over a 1-second window: fraction = busyMicros / 1_000_000.
        XCTAssertEqual(acc.utilization(channel: 1, elapsedSeconds: 1.0),
                       expected / 1_000_000, accuracy: 1e-9)
    }

    func testStationTrackerCollectsProbingClient() {
        let acc = StationTracker()
        acc.ingest(ingest(Fixtures.probeRequest))
        XCTAssertEqual(acc.stations["66:77:88:99:AA:BB"]?.probing, true)
        // A beacon's broadcast addr1 must NOT be listed as a station.
        acc.ingest(ingest(Fixtures.beaconVisible))
        XCTAssertNil(acc.stations["FF:FF:FF:FF:FF:FF"])
    }

    func testRetryRate() {
        let acc = RetryAccumulator()
        acc.ingest(ingest(Fixtures.beaconVisible))         // not a retry
        acc.ingest(ingest(Fixtures.beaconVisibleRetry))    // retry
        let s = acc.stat(bssid: "00:11:22:33:44:55")
        XCTAssertEqual(s?.total, 2)
        XCTAssertEqual(s?.retries, 1)
        XCTAssertEqual(s?.rate, 0.5)
    }
}
