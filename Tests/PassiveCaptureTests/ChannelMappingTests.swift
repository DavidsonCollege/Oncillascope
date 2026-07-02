import XCTest
import WiFiModel
@testable import PassiveCapture

final class ChannelMappingTests: XCTestCase {
    func testTwoPointFour() {
        XCTAssertEqual(ChannelMapping.channelNumber(forFrequencyMHz: 2412), 1)
        XCTAssertEqual(ChannelMapping.channelNumber(forFrequencyMHz: 2437), 6)
        XCTAssertEqual(ChannelMapping.channelNumber(forFrequencyMHz: 2484), 14)
        XCTAssertEqual(ChannelMapping.band(forFrequencyMHz: 2412), .ghz2_4)
    }
    func testFiveAndSix() {
        XCTAssertEqual(ChannelMapping.channelNumber(forFrequencyMHz: 5180), 36)
        XCTAssertEqual(ChannelMapping.band(forFrequencyMHz: 5180), .ghz5)
        XCTAssertEqual(ChannelMapping.channelNumber(forFrequencyMHz: 5955), 1)
        XCTAssertEqual(ChannelMapping.band(forFrequencyMHz: 5955), .ghz6)
    }
    func testOutOfRange() {
        XCTAssertNil(ChannelMapping.channelNumber(forFrequencyMHz: 100))
        XCTAssertNil(ChannelMapping.band(forFrequencyMHz: 100))
    }
    func testBoundaries() {
        XCTAssertEqual(ChannelMapping.channelNumber(forFrequencyMHz: 2472), 13)
        XCTAssertEqual(ChannelMapping.channelNumber(forFrequencyMHz: 2480), nil)   // gap between ch13 and ch14
        XCTAssertEqual(ChannelMapping.band(forFrequencyMHz: 2480), nil)
        XCTAssertEqual(ChannelMapping.channelNumber(forFrequencyMHz: 5885), 177)
        XCTAssertEqual(ChannelMapping.channelNumber(forFrequencyMHz: 5890), nil)
        XCTAssertEqual(ChannelMapping.band(forFrequencyMHz: 5890), nil)
    }
    func testValidityAgrees() {
        // channelNumber and band must agree on which frequencies are valid.
        for freq in stride(from: 2400, through: 7200, by: 1) {
            XCTAssertEqual(ChannelMapping.channelNumber(forFrequencyMHz: freq) != nil,
                           ChannelMapping.band(forFrequencyMHz: freq) != nil,
                           "disagreement at \(freq) MHz")
        }
    }
}
