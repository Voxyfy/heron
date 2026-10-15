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

extension LicenseTests {
    /// A real key from a test-mode purchase, passed as TEST_RUNNER_HERON_LICENSE_KEY (HERON_LICENSE_KEY inside): activates,
    /// validates and releases the seat again, so the key is left as it was.
    func testRealKeyRoundTrip() async throws {
        guard let key = ProcessInfo.processInfo.environment["HERON_LICENSE_KEY"], !key.isEmpty else {
            throw XCTSkip("No HERON_LICENSE_KEY")
        }
        let activated = try await LicenseClient.activate(key, instanceName: "HeronTests")
        XCTAssertEqual(activated.status, "active")
        XCTAssertEqual(activated.storeID, LicenseConfig.storeID)
        XCTAssertNotNil(activated.instanceID)
        // Subscription keys carry no expires_at; a lapsed subscription changes the status instead.
        let validated = try await LicenseClient.validate(key, instanceID: activated.instanceID)
        XCTAssertEqual(validated.status, "active")
        try await LicenseClient.deactivate(key, instanceID: activated.instanceID!)
        let after = try await LicenseClient.validate(key, instanceID: activated.instanceID)
        XCTAssertEqual(after.status, "inactive", "a released instance must not validate")
    }
}
