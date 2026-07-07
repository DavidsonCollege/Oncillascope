import XCTest
@testable import Telemetry

final class HelpdeskRecipientTests: XCTestCase {
    private func defaults(_ value: String?) -> UserDefaults {
        let d = UserDefaults(suiteName: "HelpdeskRecipientTests")!
        d.removePersistentDomain(forName: "HelpdeskRecipientTests")
        if let value { d.set(value, forKey: HelpdeskRecipient.defaultsKey) }
        return d
    }
    func testFallsBackToBakedDefault() {
        XCTAssertEqual(HelpdeskRecipient.resolve(defaults(nil)), "ti@davidson.edu")
    }
    func testManagedPreferenceWins() {
        XCTAssertEqual(HelpdeskRecipient.resolve(defaults("it-team@davidson.edu")),
                       "it-team@davidson.edu")
    }
    func testBlankManagedPreferenceFallsBack() {
        XCTAssertEqual(HelpdeskRecipient.resolve(defaults("   ")), "ti@davidson.edu")
    }
    func testValidation() {
        XCTAssertTrue(HelpdeskRecipient.isValid("a@b.co"))
        XCTAssertTrue(HelpdeskRecipient.isValid("ti@davidson.edu"))
        XCTAssertFalse(HelpdeskRecipient.isValid("nope"))
        XCTAssertFalse(HelpdeskRecipient.isValid("a@b"))
        XCTAssertFalse(HelpdeskRecipient.isValid(""))
        XCTAssertFalse(HelpdeskRecipient.isValid("a b@c.com"))
    }
}
