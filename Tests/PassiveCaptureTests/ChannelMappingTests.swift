import XCTest
import WiFiModel
@testable import PassiveCapture

final class ChannelMappingTests: XCTestCase {
    func testTwoPointFour() {
        XCTAssertEqual(channelNumber(forFrequencyMHz: 2412), 1)
        XCTAssertEqual(channelNumber(forFrequencyMHz: 2437), 6)
        XCTAssertEqual(channelNumber(forFrequencyMHz: 2484), 14)
        XCTAssertEqual(band(forFrequencyMHz: 2412), .ghz2_4)
    }
    func testFiveAndSix() {
        XCTAssertEqual(channelNumber(forFrequencyMHz: 5180), 36)
        XCTAssertEqual(band(forFrequencyMHz: 5180), .ghz5)
        XCTAssertEqual(channelNumber(forFrequencyMHz: 5955), 1)
        XCTAssertEqual(band(forFrequencyMHz: 5955), .ghz6)
    }
    func testOutOfRange() {
        XCTAssertNil(channelNumber(forFrequencyMHz: 100))
        XCTAssertNil(band(forFrequencyMHz: 100))
    }
}
