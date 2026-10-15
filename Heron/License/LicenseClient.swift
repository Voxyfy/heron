import Foundation

/// Polar's customer-portal license endpoints: activate ties a key to this Mac and returns an
/// activation id, validate checks key + activation, deactivate frees the seat. All three are
/// meant for public clients, so they need no token.
enum LicenseClient {
    struct Info: Codable, Sendable, Equatable {
        /// "active" (Polar: granted), "inactive" (this Mac's seat was released), "expired" or "disabled".
        var status: String
        var email: String?
        var expiresAt: Date?
        /// Polar's activation id for this Mac.
        var instanceID: String?
        var limitActivations: Int?
        var benefitID: String?
    }

    enum Problem: LocalizedError, Equatable {
        case refused(String), notConfigured, offline, badResponse

        var errorDescription: String? {
            switch self {
            case .refused(let message): message
            case .notConfigured: String(localized: "This build isn't connected to a shop yet.")
            case .offline: String(localized: "Heron couldn't reach the license server. Check your connection and try again.")
            case .badResponse: String(localized: "The license server gave an unexpected answer.")
            }
        }
    }

    /// Ties a key to this Mac; the returned activation id is what later checks and releases use.
    static func activate(_ key: String, instanceName: String) async throws -> Info {
        let (status, json) = try await post("activate", ["key": key, "organization_id": try organization(), "label": instanceName])
        guard status == 200 else { throw Problem.refused(message(status: status, json: json)) }
        guard let licenseKey = json["license_key"] as? [String: Any] else { throw Problem.badResponse }
        var info = try info(from: licenseKey)
        info.instanceID = json["id"] as? String
        return info
    }

    /// Asks whether a key and this Mac's activation are still good.
    static func validate(_ key: String, instanceID: String?) async throws -> Info {
        var body: [String: Any] = ["key": key, "organization_id": try organization()]
        if let instanceID { body["activation_id"] = instanceID }
        let (status, json) = try await post("validate", body)
        if status == 200 {
            var info = try info(from: json)
            info.instanceID = (json["activation"] as? [String: Any])?["id"] as? String ?? instanceID
            return info
        }
        let detail = (json["detail"] as? String ?? "").lowercased()
        // Polar answers a bare "Not found" whether the key or only this Mac's activation is gone.
        // Ask once more without the activation: a key that still validates was released elsewhere.
        if status == 404, instanceID != nil {
            let (bare, bareJSON) = try await post("validate", ["key": key, "organization_id": try organization()])
            if bare == 200, let _ = try? info(from: bareJSON) { return Info(status: "inactive") }
        }
        if status == 404, detail.contains("expired") { return Info(status: "expired") }
        if status == 404, detail.contains("revoked") || detail.contains("disabled") { return Info(status: "disabled") }
        throw Problem.refused(message(status: status, json: json))
    }

    static func deactivate(_ key: String, instanceID: String) async throws {
        let (status, json) = try await post("deactivate", ["key": key, "organization_id": try organization(), "activation_id": instanceID])
        // 404 means the activation is already gone, which is what we wanted.
        guard status == 204 || status == 200 || status == 404 else {
            throw Problem.refused(message(status: status, json: json))
        }
    }

    // MARK: Wire

    private static func organization() throws -> String {
        guard !LicenseConfig.polarOrganizationID.isEmpty else { throw Problem.notConfigured }
        return LicenseConfig.polarOrganizationID
    }

    private static func post(_ path: String, _ body: [String: Any]) async throws -> (Int, [String: Any]) {
        var request = URLRequest(url: LicenseConfig.apiBase.appending(path: path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 20
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw Problem.offline
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        if status >= 500 { throw Problem.badResponse }
        // Polar rate-limits these endpoints; a 429 is a "try later", never a verdict on the key.
        if status == 429 { throw Problem.offline }
        return (status, json)
    }

    /// Polar's error lines, in the user's words.
    private static func message(status: Int, json: [String: Any]) -> String {
        let detail = (json["detail"] as? String ?? "").lowercased()
        if detail.contains("limit") || (status == 403 && detail.contains("activation")) {
            return String(localized: "This key is already in use on its allowed number of Macs. Release one in Settings ▸ License on that Mac, or buy another seat.")
        }
        if detail.contains("expired") { return String(localized: "This license has expired. Renew it to keep using Heron.") }
        if detail.contains("revoked") || detail.contains("disabled") { return String(localized: "This license has been disabled.") }
        if status == 404 { return String(localized: "That key isn't recognised. Check for typos; the key is in your purchase email.") }
        if status == 422 { return String(localized: "That doesn't look like a license key.") }
        return (json["detail"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? String(localized: "The license server refused the key.")
    }

    private static func info(from licenseKey: [String: Any]) throws -> Info {
        guard let status = licenseKey["status"] as? String else { throw Problem.badResponse }
        let normalized: String
        switch status {
        case "granted": normalized = "active"
        case "revoked", "disabled": normalized = "disabled"
        default: normalized = status
        }
        return Info(status: normalized,
                    email: (licenseKey["customer"] as? [String: Any])?["email"] as? String,
                    expiresAt: (licenseKey["expires_at"] as? String).flatMap(Self.date(from:)),
                    instanceID: nil,
                    limitActivations: licenseKey["limit_activations"] as? Int,
                    benefitID: licenseKey["benefit_id"] as? String)
    }
}

extension LicenseClient {
    /// Polar writes "2027-10-15T12:00:00.000000Z"; the plain ISO parser rejects the fraction.
    static func date(from text: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }
}
