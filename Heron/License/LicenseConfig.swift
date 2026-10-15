import Foundation

/// Where Heron is sold. Fill these in from the Lemon Squeezy dashboard; until then every key
/// that Lemon Squeezy accepts is taken, whichever product it belongs to.
enum LicenseConfig {
    /// Settings ▸ General ▸ Store ID.
    static let storeID = 0
    /// The Heron product's ID (Products ▸ Heron ▸ the number in the URL).
    static let productID = 0
    /// The checkout link for the yearly plan; the Buy button opens it.
    static let checkoutURL = URL(string: "https://voxyfy.lemonsqueezy.com/buy/heron")!
    /// Days a fresh install runs with everything on.
    static let trialDays = 14
    /// How often a saved key is checked again, and how long a check may fail before Heron asks.
    static let revalidateAfterDays = 7
    static let offlineGraceDays = 14
}
