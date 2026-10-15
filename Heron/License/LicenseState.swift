import AppKit
import Foundation
import Observation

/// Whether Heron may run snippets: a trial that started on first launch, or a key that was
/// activated here. The key and the trial's start date live in Keychain; the last answer from the
/// license server is cached so Heron works offline for a while.
@MainActor @Observable
final class LicenseState {
    enum Status: Equatable {
        case trial(daysLeft: Int)
        case trialExpired
        case licensed(LicenseClient.Info)
        /// A key was saved, but the last check said no (expired, disabled, released elsewhere).
        case lapsed(LicenseClient.Info)
    }

    private(set) var status: Status = .trialExpired
    private(set) var key: String?
    private(set) var checking = false
    /// When the saved key was last confirmed by the server.
    private(set) var lastValidated: Date?

    private static let keyAccount = "license:key"
    private static let instanceAccount = "license:instance"
    private static let trialAccount = "trial:start"
    private static let infoKey = "license.info"
    private static let validatedKey = "license.validated"

    var canRun: Bool {
        switch status {
        case .trial, .licensed: true
        case .trialExpired, .lapsed: false
        }
    }

    var info: LicenseClient.Info? {
        switch status {
        case .licensed(let info), .lapsed(let info): info
        default: nil
        }
    }

    init() {
        load()
    }

    /// Reads what's saved and decides without the network; `refresh()` then asks the server when due.
    private func load() {
        key = Keychain.password(account: Self.keyAccount)
        lastValidated = UserDefaults.standard.object(forKey: Self.validatedKey) as? Date
        if let key, !key.isEmpty {
            let saved = UserDefaults.standard.data(forKey: Self.infoKey).flatMap { try? JSONDecoder().decode(LicenseClient.Info.self, from: $0) }
            let info = saved ?? LicenseClient.Info(status: "active")
            if Self.isGood(info), !offlineTooLong { status = .licensed(info) } else { status = .lapsed(info) }
        } else {
            let start = trialStart()
            let days = Calendar.current.dateComponents([.day], from: start, to: .now).day ?? 0
            let left = LicenseConfig.trialDays - days
            status = left > 0 ? .trial(daysLeft: left) : .trialExpired
        }
    }

    private static func isGood(_ info: LicenseClient.Info) -> Bool {
        guard info.status == "active" else { return false }
        if let expires = info.expiresAt, expires < .now { return false }
        return true
    }

    /// True when the server hasn't confirmed the key for longer than the grace period.
    private var offlineTooLong: Bool {
        guard let lastValidated else { return false }
        let days = Calendar.current.dateComponents([.day], from: lastValidated, to: .now).day ?? 0
        return days > LicenseConfig.revalidateAfterDays + LicenseConfig.offlineGraceDays
    }

    /// The first launch date, kept in Keychain so reinstalling doesn't restart the trial.
    private func trialStart() -> Date {
        if let saved = Keychain.password(account: Self.trialAccount), let seconds = TimeInterval(saved) {
            return Date(timeIntervalSince1970: seconds)
        }
        let now = Date()
        Keychain.setPassword(String(now.timeIntervalSince1970), account: Self.trialAccount)
        return now
    }

    // MARK: Server

    /// Checks the saved key again when it's been a while. Quiet: a network failure changes nothing.
    func refresh(force: Bool = false) async {
        guard let key, !key.isEmpty, !checking else { return }
        if !force, let lastValidated,
           (Calendar.current.dateComponents([.day], from: lastValidated, to: .now).day ?? 0) < LicenseConfig.revalidateAfterDays {
            return
        }
        checking = true
        defer { checking = false }
        do {
            var info = try await LicenseClient.validate(key, instanceID: Keychain.password(account: Self.instanceAccount))
            info.instanceID = Keychain.password(account: Self.instanceAccount)
            remember(info)
        } catch LicenseClient.Problem.offline {
            // Keep the cached answer; `offlineTooLong` ends the grace period eventually.
        } catch {
            // The server answered and the key is bad: show that, keep the key for the user to see.
            var info = self.info ?? LicenseClient.Info(status: "disabled")
            info.status = "disabled"
            remember(info)
        }
    }

    func activate(_ rawKey: String) async throws {
        let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        checking = true
        defer { checking = false }
        let info = try await LicenseClient.activate(key, instanceName: Self.instanceName)
        guard Self.isGood(info) else {
            throw LicenseClient.Problem.refused(info.status == "expired"
                                                ? String(localized: "This license has expired. Renew it to keep using Heron.")
                                                : String(localized: "This license isn't active."))
        }
        Keychain.setPassword(key, account: Self.keyAccount)
        if let instance = info.instanceID { Keychain.setPassword(instance, account: Self.instanceAccount) }
        self.key = key
        remember(info)
    }

    /// Frees this Mac's seat so the key can be used elsewhere.
    func deactivate() async throws {
        guard let key else { return }
        checking = true
        defer { checking = false }
        if let instance = Keychain.password(account: Self.instanceAccount) {
            try await LicenseClient.deactivate(key, instanceID: instance)
        }
        forget()
    }

    /// Drops the key without telling the server (when the server already refused it).
    func forget() {
        Keychain.deletePassword(account: Self.keyAccount)
        Keychain.deletePassword(account: Self.instanceAccount)
        UserDefaults.standard.removeObject(forKey: Self.infoKey)
        UserDefaults.standard.removeObject(forKey: Self.validatedKey)
        key = nil
        lastValidated = nil
        load()
    }

    private func remember(_ info: LicenseClient.Info) {
        if let data = try? JSONEncoder().encode(info) { UserDefaults.standard.set(data, forKey: Self.infoKey) }
        lastValidated = .now
        UserDefaults.standard.set(lastValidated, forKey: Self.validatedKey)
        status = Self.isGood(info) ? .licensed(info) : .lapsed(info)
    }

    /// "Batuhan's MacBook Pro", so the customer can tell seats apart on the Lemon Squeezy page.
    private static var instanceName: String {
        Host.current().localizedName ?? "Mac"
    }
}
