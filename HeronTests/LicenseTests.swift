import XCTest
@testable import Heron

/// The license client against the real Lemon Squeezy endpoint with a key that can't exist:
/// checks the wire format and that refusals come back as a readable message. Skipped offline.
final class LicenseTests: XCTestCase {
    func testUnknownKeyIsRefusedPlainly() async throws {
        do {
            _ = try await LicenseClient.activate("00000000-0000-0000-0000-000000000000", instanceName: "HeronTests")
            XCTFail("A made-up key must not activate")
        } catch LicenseClient.Problem.offline {
            throw XCTSkip("No network")
        } catch LicenseClient.Problem.refused(let message) {
            XCTAssertFalse(message.isEmpty)
            XCTAssertFalse(message.lowercased().contains("license_key"), "Server wording leaked: \(message)")
        }
    }

    func testDatesWithAndWithoutFractions() {
        XCTAssertNotNil(LicenseClient.date(from: "2027-10-15T12:00:00.000000Z"))
        XCTAssertNotNil(LicenseClient.date(from: "2027-10-15T12:00:00Z"))
        XCTAssertNil(LicenseClient.date(from: "yesterday"))
    }
}
