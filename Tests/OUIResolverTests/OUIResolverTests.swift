import XCTest
@testable import OUIResolver

final class OUIResolverTests: XCTestCase {

    func testBundledDatabaseLoads() {
        let r = OUIResolver.shared
        XCTAssertGreaterThan(r.count, 20, "bundled oui.csv should load many entries")
    }

    func testResolvesKnownVendorAcrossMACFormats() {
        let r = OUIResolver.shared
        XCTAssertEqual(r.vendor(for: "00:14:51:aa:bb:cc"), "Apple")
        XCTAssertEqual(r.vendor(for: "001451AABBCC"), "Apple")
        XCTAssertEqual(r.vendor(for: "0018-0A-11-22-33"), "Cisco Meraki")
    }

    func testUnknownVendorReturnsNil() {
        // 0x10 first octet: unicast (I/G clear) + globally unique (U/L clear), not in table.
        let r = OUIResolver(table: ["AABBCC": "Test"])
        XCTAssertNil(r.vendor(for: "10:22:33:44:55:66"))
    }

    func testRandomizedAndMulticastMACs() {
        let r = OUIResolver.shared
        // 0x02 in first octet → locally administered (private/randomized).
        XCTAssertEqual(r.vendor(for: "02:11:22:33:44:55"), "Locally administered (randomized)")
        // 0x01 bit → multicast/group address.
        XCTAssertEqual(r.vendor(for: "01:00:5e:00:00:01"), "Multicast/Group")
    }

    func testNilAndShortInputs() {
        let r = OUIResolver.shared
        XCTAssertNil(r.vendor(for: nil))
        XCTAssertNil(r.vendor(for: "ab"))
        XCTAssertNil(r.vendor(for: "<redacted>"))
    }

    func testCSVParsingSkipsCommentsAndBadRows() {
        let csv = """
        # comment
        001451,Apple
        bad line without comma
        ZZZZZZ,Invalid Hex
        50C7BF,TP-Link
        """
        let table = OUIResolver.parseCSV(csv)
        XCTAssertEqual(table.count, 2)
        XCTAssertEqual(table["001451"], "Apple")
        XCTAssertEqual(table["50C7BF"], "TP-Link")
    }

    func testMergeOverlaysEntries() {
        let r = OUIResolver(table: ["001451": "Apple"])
        r.merge(["ABCDEF": "NewVendor"])
        XCTAssertEqual(r.vendor(for: "AB:CD:EF:00:00:00"), "NewVendor")
        XCTAssertEqual(r.count, 2)
    }
}
