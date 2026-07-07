import XCTest
@testable import AppUpdateSupport

final class AppcastVersionTests: XCTestCase {
    func testParsesTagWithLeadingV() {
        let v = AppcastVersion(tag: "v1.2.3")
        XCTAssertEqual(v, AppcastVersion(major: 1, minor: 2, patch: 3))
    }

    func testParsesTagWithoutLeadingV() {
        XCTAssertEqual(AppcastVersion(tag: "1.0.0"),
                       AppcastVersion(major: 1, minor: 0, patch: 0))
    }

    func testRejectsMalformedTag() {
        XCTAssertNil(AppcastVersion(tag: "v1.2"))
        XCTAssertNil(AppcastVersion(tag: "1.2.3.4"))
        XCTAssertNil(AppcastVersion(tag: "vX.Y.Z"))
        XCTAssertNil(AppcastVersion(tag: ""))
    }

    func testShortVersionString() {
        XCTAssertEqual(AppcastVersion(major: 1, minor: 2, patch: 3).shortVersionString, "1.2.3")
    }

    func testBundleVersionDerivation() {
        XCTAssertEqual(AppcastVersion(major: 1, minor: 1, patch: 0).bundleVersion, 10100)
        XCTAssertEqual(AppcastVersion(major: 1, minor: 2, patch: 3).bundleVersion, 10203)
        XCTAssertEqual(AppcastVersion(major: 0, minor: 0, patch: 1).bundleVersion, 1)
    }

    func testOrderingMatchesBundleVersion() {
        XCTAssertLessThan(AppcastVersion(major: 1, minor: 0, patch: 9),
                          AppcastVersion(major: 1, minor: 1, patch: 0))
        XCTAssertLessThan(AppcastVersion(major: 1, minor: 2, patch: 3),
                          AppcastVersion(major: 2, minor: 0, patch: 0))
    }
}
