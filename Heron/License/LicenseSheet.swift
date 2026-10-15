import SwiftUI

/// Trial status and the key field: shown on launch once the trial ends, and from Heron ▸ License.
struct LicenseSheet: View {
    let license: LicenseState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme
    @State private var key = ""
    @State private var failure: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.title2.weight(.semibold))
                    Text(subtitle).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            if case .licensed = license.status {
                LicenseDetails(license: license)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text(String(localized: "License key")).font(.callout.weight(.medium))
                    TextField("", text: $key, prompt: Text("XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX"))
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .onSubmit(activate)
                    if let failure {
                        Text(failure).font(.callout).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                    }
                    Text(String(localized: "The key is in your purchase email. One key works on two Macs."))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack {
                if case .licensed = license.status {} else {
                    Button(String(localized: "Buy Heron — $10 / year")) { NSWorkspace.shared.open(LicenseConfig.checkoutURL) }
                        .buttonStyle(.bordered).tint(theme.accentColor)
                }
                Spacer()
                if license.checking { ProgressView().controlSize(.small).padding(.trailing, 6) }
                if license.canRun {
                    Button(String(localized: "Close")) { dismiss() }.keyboardShortcut(.cancelAction)
                } else {
                    Button(String(localized: "Quit Heron")) { NSApp.terminate(nil) }.keyboardShortcut(.cancelAction)
                }
                if case .licensed = license.status {} else {
                    Button(String(localized: "Activate")) { activate() }
                        .buttonStyle(.borderedProminent).tint(theme.accentColor)
                        .keyboardShortcut(.defaultAction)
                        .disabled(key.trimmingCharacters(in: .whitespaces).count < 8 || license.checking)
                }
            }
        }
        .padding(24)
        .frame(width: 520)
    }

    private var title: String {
        switch license.status {
        case .trial(let days): String(localized: "Trial: \(days) days left")
        case .trialExpired: String(localized: "Your trial has ended")
        case .licensed: String(localized: "Heron is licensed")
        case .lapsed(let info):
            info.status == "expired" ? String(localized: "Your license has expired") : String(localized: "This license isn't active")
        }
    }

    private var subtitle: String {
        switch license.status {
        case .trial: String(localized: "Everything is on during the trial. Enter a key any time.")
        case .trialExpired: String(localized: "Thanks for trying Heron. A license keeps it running: $10 a year, two Macs.")
        case .licensed: String(localized: "Thank you for supporting Heron.")
        case .lapsed(let info):
            info.status == "expired" ? String(localized: "Renew on Lemon Squeezy, then enter the key again.")
                                     : String(localized: "The license server refused the saved key. Enter a key, or contact support.")
        }
    }

    private func activate() {
        failure = nil
        Task {
            do {
                try await license.activate(key)
                key = ""
            } catch {
                failure = error.localizedDescription
            }
        }
    }
}

/// Email, expiry and the Release button, shared by the sheet and Settings ▸ License.
struct LicenseDetails: View {
    let license: LicenseState
    @State private var failure: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let email = license.info?.email { row(String(localized: "Licensed to"), email) }
            if let expires = license.info?.expiresAt {
                row(String(localized: "Renews on"), expires.formatted(date: .long, time: .omitted))
            }
            if let key = license.key { row(String(localized: "Key"), String(key.prefix(8)) + "…" + String(key.suffix(4))) }
            if let checked = license.lastValidated {
                row(String(localized: "Last checked"), checked.formatted(date: .abbreviated, time: .shortened))
            }
            HStack(spacing: 12) {
                Button(String(localized: "Check Now")) { Task { await license.refresh(force: true) } }
                Button(String(localized: "Release This Mac")) {
                    Task {
                        do { try await license.deactivate() } catch { failure = error.localizedDescription }
                    }
                }
                .help(String(localized: "Frees the seat so the key can be used on another Mac."))
            }
            .disabled(license.checking)
            .padding(.top, 4)
            if let failure { Text(failure).font(.callout).foregroundStyle(.red) }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(spacing: 10) {
            Text(label).foregroundStyle(.secondary).frame(width: 110, alignment: .leading)
            Text(value).textSelection(.enabled)
        }
        .font(.callout)
    }
}
