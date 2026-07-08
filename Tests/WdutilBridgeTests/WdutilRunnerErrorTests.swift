import XCTest
@testable import WdutilBridge

final class WdutilRunnerErrorTests: XCTestCase {

    /// The helper daemon returns a human-readable failure reason; it must survive to
    /// the UI instead of being flattened into a generic "not authorized".
    func testFailedErrorCarriesMessage() {
        let err = WdutilRunner.WdutilError.failed("wdutil exited with status 2: boom")
        XCTAssertEqual(err.errorDescription, "wdutil exited with status 2: boom")
    }

    func testFailedErrorsCompareByMessage() {
        XCTAssertEqual(WdutilRunner.WdutilError.failed("a"), .failed("a"))
        XCTAssertNotEqual(WdutilRunner.WdutilError.failed("a"), .failed("b"))
    }
}
