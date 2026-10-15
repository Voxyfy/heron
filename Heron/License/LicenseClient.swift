import Foundation

/// Lemon Squeezy's license endpoints. They take the key itself, so no API token ships in the app.
enum LicenseClient {
    struct Info: Codable, Sendable, Equatable {
        /// "active", "inactive", "expired" or "disabled".
        var status: String
        var email: String?
        var expiresAt: Date?
        var instanceID: String?
        var productID: Int?
        var storeID: Int?
        var productName: String?
    }

    enum Problem: LocalizedError, Equatable {
        case refused(String), wrongProduct, offline, badResponse

        var errorDescription: String? {
            switch self {
            case .refused(let message): message
            case .wrongProduct: String(localized: "This key belongs to another product.")
            case .offline: String(localized: "Heron couldn't reach the license server. Check your connection and try again.")
            case .badResponse: String(localized: "The license server gave an unexpected answer.")
            }
        }
    }

    private static let base = URL(string: "https://api.lemonsqueezy.com/v1/licenses/")!

    /// Ties a key to this Mac; the returned instance id is what later checks and releases use.
    static func activate(_ key: String, instanceName: String) async throws -> Info {
        let json = try await post("activate", ["license_key": key, "instance_name": instanceName])
        guard json["activated"] as? Bool == true else { throw Problem.refused(message(in: json)) }
        return try info(from: json)
    }

    /// Asks whether a key and its instance are still good; the answer says why when not.
    static func validate(_ key: String, instanceID: String?) async throws -> Info {
        var form = ["license_key": key]
        if let instanceID { form["instance_id"] = instanceID }
        let json = try await post("validate", form)
        if json["license_key"] == nil {
            // "instance_id not found.": the seat was released on another Mac. The key itself may be
            // fine, so report it as inactive here rather than as a broken answer.
            if (json["error"] as? String)?.lowercased().contains("instance") == true { return Info(status: "inactive") }
            throw Problem.refused(message(in: json))
        }
        var info = try info(from: json)
        if json["valid"] as? Bool != true, info.status == "active" { info.status = "inactive" }
        return info
    }

    static func deactivate(_ key: String, instanceID: String) async throws {
        let json = try await post("deactivate", ["license_key": key, "instance_id": instanceID])
        guard json["deactivated"] as? Bool == true else { throw Problem.refused(message(in: json)) }
    }

    // MARK: Wire

    private static func post(_ path: String, _ form: [String: String]) async throws -> [String: Any] {
        var request = URLRequest(url: base.appending(path: path))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 20
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=")
        request.httpBody = form.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }
            .joined(separator: "&").data(using: .utf8)
        let data: Data
        do {
            (data, _) = try await URLSession.shared.data(for: request)
        } catch {
            throw Problem.offline
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw Problem.badResponse }
        return json
    }

    private static func message(in json: [String: Any]) -> String {
        (json["error"] as? String).map(Self.friendly) ?? String(localized: "The license server refused the key.")
    }

    /// Lemon Squeezy's English error lines, in the user's words.
    private static func friendly(_ error: String) -> String {
        let lower = error.lowercased()
        if lower.contains("activation limit") { return String(localized: "This key is already in use on its allowed number of Macs. Release one in Settings ▸ License on that Mac, or buy another seat.") }
        if lower.contains("not found") || lower.contains("invalid") { return String(localized: "That key isn't recognised. Check for typos; the key is in your purchase email.") }
        if lower.contains("expired") { return String(localized: "This license has expired. Renew it to keep using Heron.") }
        if lower.contains("disabled") { return String(localized: "This license has been disabled.") }
        return error
    }

    private static func info(from json: [String: Any]) throws -> Info {
        guard let key = json["license_key"] as? [String: Any], let status = key["status"] as? String else {
            throw Problem.badResponse
        }
        let meta = json["meta"] as? [String: Any] ?? [:]
        let productID = meta["product_id"] as? Int
        let storeID = meta["store_id"] as? Int
        if LicenseConfig.productID != 0, let productID, productID != LicenseConfig.productID { throw Problem.wrongProduct }
        if LicenseConfig.storeID != 0, let storeID, storeID != LicenseConfig.storeID { throw Problem.wrongProduct }
        let expires = (key["expires_at"] as? String).flatMap(Self.date(from:))
        return Info(status: status, email: meta["customer_email"] as? String, expiresAt: expires,
                    instanceID: (json["instance"] as? [String: Any])?["id"] as? String,
                    productID: productID, storeID: storeID, productName: meta["product_name"] as? String)
    }
}

extension LicenseClient {
    /// Lemon Squeezy writes "2027-10-15T12:00:00.000000Z"; the plain ISO parser rejects the fraction.
    static func date(from text: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }
}
