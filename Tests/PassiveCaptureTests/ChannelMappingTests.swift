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
    func testBoundaries() {
        XCTAssertEqual(channelNumber(forFrequencyMHz: 2472), 13)
        XCTAssertEqual(channelNumber(forFrequencyMHz: 2480), nil)   // gap between ch13 and ch14
        XCTAssertEqual(band(forFrequencyMHz: 2480), nil)
        XCTAssertEqual(channelNumber(forFrequencyMHz: 5885), 177)
        XCTAssertEqual(channelNumber(forFrequencyMHz: 5890), nil)
        XCTAssertEqual(band(forFrequencyMHz: 5890), nil)
    }
    func testValidityAgrees() {
        // channelNumber and band must agree on which frequencies are valid.
        for freq in stride(from: 2400, through: 7200, by: 1) {
            XCTAssertEqual(channelNumber(forFrequencyMHz: freq) != nil,
                           band(forFrequencyMHz: freq) != nil,
                           "disagreement at \(freq) MHz")
        }
    }
}
