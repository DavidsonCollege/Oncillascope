import XCTest
@testable import WiFiModel

final class ScanAggregatorTests: XCTestCase {

    private func bss(_ id: String, rssi: Int = -60) -> BSSObservation {
        BSSObservation(ssid: "Net-\(id)", bssid: id, vendor: nil, rssi: rssi, noise: -95,
                       channel: ChannelInfo(number: 36, width: .mhz80, band: .ghz5),
                       security: .wpa2Personal, phyGeneration: .ax, beaconInterval: 100)
    }

    func testIngestInsertsAndUpdates() {
        var agg = ScanAggregator(ttl: 90)
        let t0 = Date(timeIntervalSince1970: 1_000)
        agg.ingest([bss("AA", rssi: -70)], at: t0)
        agg.ingest([bss("AA", rssi: -55)], at: t0 + 20)
        let obs = agg.observations(at: t0 + 20)
        XCTAssertEqual(obs.count, 1)
        // Latest scan's data wins.
        XCTAssertEqual(obs.first?.rssi, -55)
    }

    func testMissedScanIsRetainedWithinTTL() {
        // A BSS heard once must survive scans that miss it, for up to ttl seconds —
        // this is the fix for weak networks flickering in and out of the table.
        var agg = ScanAggregator(ttl: 90)
        let t0 = Date(timeIntervalSince1970: 2_000)
        agg.ingest([bss("AA"), bss("BB")], at: t0)
        agg.ingest([bss("AA")], at: t0 + 20)          // BB missed this pass
        XCTAssertEqual(agg.observations(at: t0 + 20).count, 2)
    }

    func testEntryExpiresAfterTTL() {
        var agg = ScanAggregator(ttl: 90)
        let t0 = Date(timeIntervalSince1970: 3_000)
        agg.ingest([bss("AA"), bss("BB")], at: t0)
        agg.ingest([bss("AA")], at: t0 + 100)          // BB last seen 100s ago > ttl
        XCTAssertEqual(agg.observations(at: t0 + 100).map(\.bssid), ["AA"])
    }

    func testObservationsPruneWithoutIngest() {
        // Aging must also apply when scanning stops (e.g. Wi-Fi turned off).
        var agg = ScanAggregator(ttl: 90)
        let t0 = Date(timeIntervalSince1970: 4_000)
        agg.ingest([bss("AA")], at: t0)
        XCTAssertEqual(agg.observations(at: t0 + 89).count, 1)
        XCTAssertEqual(agg.observations(at: t0 + 91).count, 0)
    }

    func testLastSeenAndStaleness() {
        var agg = ScanAggregator(ttl: 90)
        let t0 = Date(timeIntervalSince1970: 5_000)
        agg.ingest([bss("AA"), bss("BB")], at: t0)
        agg.ingest([bss("AA")], at: t0 + 30)
        XCTAssertEqual(agg.lastSeen(id: "AA"), t0 + 30)
        XCTAssertEqual(agg.lastSeen(id: "BB"), t0)
        // Fresh window 25s: AA seen 0s ago is fresh, BB seen 30s ago is stale.
        XCTAssertFalse(agg.isStale(id: "AA", at: t0 + 30))
        XCTAssertTrue(agg.isStale(id: "BB", at: t0 + 30))
    }

    func testReset() {
        var agg = ScanAggregator(ttl: 90)
        let t0 = Date(timeIntervalSince1970: 6_000)
        agg.ingest([bss("AA")], at: t0)
        agg.reset()
        XCTAssertTrue(agg.observations(at: t0).isEmpty)
        XCTAssertNil(agg.lastSeen(id: "AA"))
    }
}
