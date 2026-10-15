import Foundation

/// Where Heron is sold: Polar (polar.sh), merchant of record. The license endpoints the app
/// uses take only the key and the organization id, so no token ships in the app.
enum LicenseConfig {
    /// Polar ▸ Settings ▸ General: the organization's id (a UUID). Empty until the shop exists.
    static let polarOrganizationID = "85eab49a-6d86-4467-a8a2-da966bc64a30"
    /// Polar's sandbox (sandbox.polar.sh) has its own organizations and keys; true while testing.
    static let polarSandbox = false
    static var apiBase: URL {
        URL(string: polarSandbox ? "https://sandbox-api.polar.sh/v1/customer-portal/license-keys/"
                                 : "https://api.polar.sh/v1/customer-portal/license-keys/")!
    }
    /// The checkout link for the yearly plan; the Buy button opens it.
    static let checkoutURL = URL(string: "https://buy.polar.sh/polar_cl_JXRFKGs8lVmfH1LAxXkVSPjVNWJsn1BfcoCT73CWx9o")!
    /// Days a fresh install runs with everything on.
    static let trialDays = 14
    /// How often a saved key is checked again, and how long a check may fail before Heron asks.
    static let revalidateAfterDays = 7
    static let offlineGraceDays = 14
}
