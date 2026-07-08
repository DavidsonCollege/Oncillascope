import XCTest
@testable import Telemetry
import WiFiModel

final class TelemetryTests: XCTestCase {

    // MARK: - RingBuffer

    func testRingBufferKeepsLastNInOrder() {
        var ring = RingBuffer<Int>(capacity: 3)
        for i in 1...5 { ring.append(i) }
        XCTAssertEqual(ring.elements, [3, 4, 5])
        XCTAssertTrue(ring.isFull)
        XCTAssertEqual(ring.count, 3)
    }

    func testRingBufferUnderCapacity() {
        var ring = RingBuffer<Int>(capacity: 10)
        ring.append(1); ring.append(2)
        XCTAssertEqual(ring.elements, [1, 2])
        XCTAssertFalse(ring.isFull)
    }

    // MARK: - TelemetryStore markers

    func testRoamMarkerOnBSSIDChange() {
        let store = TelemetryStore(capacity: 100)
        let t0 = Date(timeIntervalSince1970: 1_000)
        store.record(TelemetrySample(timestamp: t0, rssi: -50, noise: -90, txRate: 866,
                                     bssid: "AA:AA:AA:AA:AA:AA", channel: 36))
        store.record(TelemetrySample(timestamp: t0 + 1, rssi: -55, noise: -90, txRate: 866,
                                     bssid: "BB:BB:BB:BB:BB:BB", channel: 36))
        XCTAssertEqual(store.markers.count, 1)
        XCTAssertEqual(store.markers.first?.kind, .roam)
    }

    func testChannelChangeMarker() {
        let store = TelemetryStore(capacity: 100)
        let t0 = Date(timeIntervalSince1970: 2_000)
        store.record(TelemetrySample(timestamp: t0, rssi: -50, noise: -90, txRate: 100,
                                     bssid: "AA", channel: 6))
        store.record(TelemetrySample(timestamp: t0 + 1, rssi: -50, noise: -90, txRate: 100,
                                     bssid: "AA", channel: 11))
        XCTAssertEqual(store.markers.first?.kind, .channelChange)
    }

    func testWindowFilter() {
        let store = TelemetryStore(capacity: 100)
        let now = Date(timeIntervalSince1970: 10_000)
        store.record(TelemetrySample(timestamp: now - 120, rssi: -50, noise: -90, txRate: 1))
        store.record(TelemetrySample(timestamp: now - 30, rssi: -50, noise: -90, txRate: 1))
        let recent = store.samples(inLast: 60, now: now)
        XCTAssertEqual(recent.count, 1)
    }

    func testSNRDerivation() {
        let s = TelemetrySample(timestamp: Date(), rssi: -50, noise: -92, txRate: 100)
        XCTAssertEqual(s.snr, 42)
    }

    // MARK: - Export

    func testNetworksCSVHasHeaderAndRow() {
        let net = BSSObservation(ssid: "Home, Net", bssid: "AA:BB:CC:DD:EE:FF",
                                 vendor: "Apple", rssi: -50, noise: -90,
                                 channel: ChannelInfo(number: 36, width: .mhz80, band: .ghz5),
                                 security: .wpa3Personal, phyGeneration: .ax, beaconInterval: 100)
        let csv = Exporter.networksCSV([net])
        let lines = csv.split(separator: "\n")
        XCTAssertEqual(lines.count, 2)
        XCTAssertTrue(lines[0].contains("bssid"))
        // SSID has a comma → must be quoted.
        XCTAssertTrue(csv.contains("\"Home, Net\""))
        XCTAssertTrue(csv.contains("AA:BB:CC:DD:EE:FF"))
    }

    func testSamplesCSVRoundTripsFields() {
        let s = TelemetrySample(timestamp: Date(timeIntervalSince1970: 0), rssi: -48,
                                noise: -91, txRate: 1201, mcsIndex: 11, cca: 20,
                                bssid: "AA", channel: 36)
        let csv = Exporter.samplesCSV([s])
        XCTAssertTrue(csv.contains("-48"))
        XCTAssertTrue(csv.contains("1201"))
        XCTAssertTrue(csv.contains("11"))
    }

    func testJSONExportEncodesSnapshot() throws {
        let snap = WiFiSnapshot(timestamp: Date(timeIntervalSince1970: 0),
                                current: ConnectionInfo(ssid: "Net", rssi: -50, noise: -90),
                                networks: [])
        let data = try Exporter.json(snap)
        let str = String(data: data, encoding: .utf8)!
        XCTAssertTrue(str.contains("\"ssid\""))
        XCTAssertTrue(str.contains("Net"))
        // Round-trip decode with the matching ISO8601 date strategy.
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(WiFiSnapshot.self, from: data)
        XCTAssertEqual(decoded.current?.ssid, "Net")
    }

    func testCSVEscaping() {
        XCTAssertEqual(Exporter.escape("plain"), "plain")
        XCTAssertEqual(Exporter.escape("a,b"), "\"a,b\"")
        XCTAssertEqual(Exporter.escape("say \"hi\""), "\"say \"\"hi\"\"\"")
    }

    // MARK: - CSV formula-injection defense

    func testEscapeNeutralizesFormulaPrefixes() {
        // Anyone can broadcast an SSID starting with a formula trigger; Excel/Sheets
        // would execute it when the exported CSV is opened. Defuse with a leading '.
        XCTAssertEqual(Exporter.escape("=1+1"), "'=1+1")
        XCTAssertEqual(Exporter.escape("@SUM(A1)"), "'@SUM(A1)")
        XCTAssertEqual(Exporter.escape("+cmd|calc"), "'+cmd|calc")
        XCTAssertEqual(Exporter.escape("-2+3"), "'-2+3")
        XCTAssertEqual(Exporter.escape("\ttabbed"), "'\ttabbed")
        // Defusing composes with RFC-4180 quoting when the field also needs quotes.
        XCTAssertEqual(Exporter.escape("=HYPERLINK(\"http://evil\")"),
                       "\"'=HYPERLINK(\"\"http://evil\"\")\"")
    }

    func testEscapeLeavesPlainNumbersAlone() {
        // Numeric columns (RSSI, noise) legitimately start with '-'; they must stay
        // numeric so the helpdesk can chart/sort them.
        XCTAssertEqual(Exporter.escape("-70"), "-70")
        XCTAssertEqual(Exporter.escape("-3.5"), "-3.5")
        XCTAssertEqual(Exporter.escape("+5"), "+5")
    }

    func testNetworksCSVDefusesHostileSSID() {
        let net = BSSObservation(ssid: "=1+1", bssid: "AA:BB:CC:DD:EE:FF",
                                 vendor: "Apple", rssi: -50, noise: -90,
                                 channel: ChannelInfo(number: 36, width: .mhz80, band: .ghz5),
                                 security: .wpa3Personal, phyGeneration: .ax, beaconInterval: 100)
        let csv = Exporter.networksCSV([net])
        // The data row must not begin with a live formula.
        XCTAssertTrue(csv.contains("\n'=1+1,"))
        XCTAssertFalse(csv.contains("\n=1+1,"))
    }
}
