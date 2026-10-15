import Foundation

/// Where Heron is sold. Fill these in from the Lemon Squeezy dashboard; until then every key
/// that Lemon Squeezy accepts is taken, whichever product it belongs to.
enum LicenseConfig {
    /// Settings ▸ Stores: Voxyfy, #498451 (the same in test and live mode).
    static let storeID = 498451
    /// The Heron product's ID. 1442112 is the TEST-mode product; "Copy to Live Mode" makes a new
    /// one with its own id, which goes here before the first release. 0 accepts any product.
    static let productID = 0
    /// The checkout link for the yearly plan; the Buy button opens it.
    static let checkoutURL = URL(string: "https://voxyfy.lemonsqueezy.com/buy/heron")!
    /// Days a fresh install runs with everything on.
    static let trialDays = 14
    /// How often a saved key is checked again, and how long a check may fail before Heron asks.
    static let revalidateAfterDays = 7
    static let offlineGraceDays = 14
}
