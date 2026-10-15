import SwiftUI

/// Remote Connection Manager: servers on the left, under their group headings; the chosen one's
/// form on the right with Test, Connect and Save. Secrets go to Keychain on Save.
struct ConnectionsSheet: View {
    let workspace: Workspace
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme
    @State private var search = ""
    @State private var selection: UUID?
    @State private var draft: RemoteConnection?
    @State private var password = ""
    @State private var key = ""
    @State private var passphrase = ""
    @State private var keyNeedsPassphrase = false
    @State private var status: Status?
    @State private var busy = false
    @State private var hostKey: HostKeyError?
    @State private var groupPrompt: GroupPrompt?
    @FocusState private var searchFocused: Bool

    enum Status: Equatable {
        case ok(String), failed(String), working(String)
    }

    struct GroupPrompt: Identifiable {
        var id: String { old ?? "new" }
        /// The group being renamed; nil adds one.
        var old: String?
        var name = ""
    }

    private var store: ConnectionStore { workspace.connections }

    private var sections: [(group: String, connections: [RemoteConnection])] {
        guard !search.isEmpty else { return store.sections }
        return store.sections.compactMap { section in
            let matching = section.connections.filter {
                $0.title.localizedCaseInsensitiveContains(search) || $0.host.localizedCaseInsensitiveContains(search)
            }
            return matching.isEmpty ? nil : (section.group, matching)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(String(localized: "Remote Connection Manager")).font(.title3.weight(.semibold))
                Spacer()
            }
            .padding(16)
            Rectangle().fill(theme.accentColor).frame(height: 1)
            HSplitView {
                sidebar.frame(minWidth: 270, idealWidth: 280, maxWidth: 320)
                form.frame(minWidth: 640)
            }
            Divider()
            HStack {
                statusLine
                Spacer()
                Button(String(localized: "Close")) { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(16)
        }
        .frame(width: 1060, height: 660)
        .onAppear { selection = store.connections.first?.id }
        .onChange(of: selection) { load(selection) }
        .sheet(item: $groupPrompt) { prompt in
            GroupNameSheet(prompt: prompt) { name in
                if let old = prompt.old { store.renameGroup(old, to: name) } else { store.addGroup(name) }
            }
        }
        .alert(String(localized: "Trust this server?"), isPresented: Binding(get: { hostKey != nil }, set: { if !$0 { hostKey = nil } }),
               presenting: hostKey) { error in
            Button(String(localized: "Trust")) {
                HostKeys.trust(error.presentedKey, host: error.host, port: error.port)
                hostKey = nil
                test(thenConnect: false)
            }
            Button(String(localized: "Cancel"), role: .cancel) { hostKey = nil }
        } message: { error in
            Text(verbatim: (error.errorDescription ?? "") + "\n\n" + HostKeys.fingerprint(error.presentedKey))
        }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Button { startNew() } label: { Label(String(localized: "Connection"), systemImage: "plus") }
                    .buttonStyle(.bordered).tint(theme.accentColor)
                Button { groupPrompt = GroupPrompt() } label: { Label(String(localized: "Group"), systemImage: "plus") }
                    .buttonStyle(.bordered)
            }
            HStack {
                TextField(String(localized: "Search"), text: $search).textFieldStyle(.plain).focused($searchFocused)
                Text("⌘F").font(.caption).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(theme.backgroundColor, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(theme.borderColor))
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4, pinnedViews: []) {
                    ForEach(sections, id: \.group) { section in
                        GroupHeader(name: section.group,
                                    rename: { groupPrompt = GroupPrompt(old: section.group, name: section.group) },
                                    remove: { store.removeGroup(section.group) })
                            .padding(.top, 8)
                        ForEach(section.connections) { connection in
                            ConnectionRow(connection: connection, isSelected: connection.id == selection,
                                          select: { selection = connection.id },
                                          duplicate: { let copy = connection.duplicate(); store.save(copy); selection = copy.id },
                                          remove: {
                                              store.remove(connection)
                                              if selection == connection.id { selection = nil; draft = nil }
                                          })
                        }
                    }
                    if store.connections.isEmpty {
                        Text(String(localized: "No servers yet. Add one with + Connection."))
                            .font(.callout).foregroundStyle(.secondary).padding(.top, 12)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(theme.panelColor)
        .background {
            Button("") { searchFocused = true }.keyboardShortcut("f").hidden()
        }
    }

    // MARK: Form

    @ViewBuilder
    private var form: some View {
        if let binding = Binding($draft) {
            VStack(spacing: 0) {
                HStack {
                    Text(binding.wrappedValue.title.isEmpty ? String(localized: "New connection") : binding.wrappedValue.title)
                        .font(.title2.weight(.medium)).lineLimit(1)
                    Spacer()
                    Button(String(localized: "Test")) { test(thenConnect: false) }
                        .disabled(busy || !binding.wrappedValue.isComplete)
                    Button(String(localized: "Connect")) { test(thenConnect: true) }
                        .buttonStyle(.bordered).tint(theme.accentColor)
                        .disabled(busy || !binding.wrappedValue.isComplete)
                    Button(String(localized: "Save")) { save() }
                        .buttonStyle(.borderedProminent).tint(theme.accentColor)
                        .keyboardShortcut("s", modifiers: .command)
                        .disabled(!binding.wrappedValue.isComplete)
                }
                .padding(.horizontal, 24).padding(.vertical, 16)
                Divider()
                ScrollView {
                    VStack(spacing: 0) {
                        row(String(localized: "Label")) {
                            TextField("", text: binding.name, prompt: Text(String(localized: "Production")))
                            ColorDots(selected: binding.color)
                        }
                        row(String(localized: "Group")) {
                            Picker("", selection: binding.group) {
                                Text(String(localized: "Ungrouped")).tag("")
                                ForEach(store.groups, id: \.self) { Text($0).tag($0) }
                            }
                            .labelsHidden()
                        }
                        row(String(localized: "Host")) {
                            TextField("", text: binding.host, prompt: Text("example.com"))
                                .font(.system(.body, design: .monospaced))
                            TextField("", value: binding.port, format: .number.grouping(.never))
                                .font(.system(.body, design: .monospaced)).frame(width: 76).multilineTextAlignment(.center)
                        }
                        row(String(localized: "Username")) {
                            TextField("", text: binding.username, prompt: Text("forge"))
                        }
                        row(String(localized: "Remote Folder")) {
                            TextField("", text: binding.remotePath, prompt: Text("/home/forge/example.com"))
                                .font(.system(.body, design: .monospaced))
                        }
                        row(String(localized: "Local Path"),
                            detail: String(localized: "Code completion on a server works from a copy of the project on this Mac.")) {
                            TextField("", text: Binding(get: { binding.wrappedValue.localProject ?? "" },
                                                        set: { binding.wrappedValue.localProject = $0.isEmpty ? nil : $0 }),
                                      prompt: Text(String(localized: "Optional")))
                            Button { chooseLocalProject(binding) } label: { Image(systemName: "folder") }
                        }
                        row(String(localized: "PHP Binary"),
                            detail: String(localized: "What to run on the server; leave \"php\" to use its PATH.")) {
                            TextField("", text: binding.phpPath, prompt: Text("php")).font(.system(.body, design: .monospaced))
                        }
                        row(String(localized: "Authentication Method")) {
                            Picker("", selection: binding.auth) {
                                Text(String(localized: "Private Key")).tag(RemoteConnection.Auth.key)
                                Text(String(localized: "Password")).tag(RemoteConnection.Auth.password)
                            }
                            .labelsHidden()
                        }
                        if binding.wrappedValue.auth == .password {
                            row(String(localized: "Password")) {
                                SecureField("", text: $password)
                            }
                        } else {
                            row(String(localized: "Private Key"),
                                detail: String(localized: "An OpenSSH key (ed25519 or RSA). The key is kept in your Keychain.")) {
                                Text(binding.wrappedValue.keyName ?? (key.isEmpty ? String(localized: "None chosen") : String(localized: "Pasted key")))
                                    .foregroundStyle(key.isEmpty ? .secondary : .primary).lineLimit(1)
                                Spacer()
                                Button(String(localized: "Choose…")) { chooseKey(binding) }
                            }
                            if keyNeedsPassphrase || !passphrase.isEmpty {
                                row(String(localized: "Passphrase")) {
                                    SecureField("", text: $passphrase)
                                }
                            }
                        }
                    }
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.large)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 16)
                }
            }
        } else {
            VStack(spacing: 10) {
                Image("lucide.server").renderingMode(.template).resizable().aspectRatio(contentMode: .fit)
                    .frame(width: 34, height: 34).foregroundStyle(.tertiary)
                Text(String(localized: "Choose a server, or add one.")).foregroundStyle(.secondary)
                Text(String(localized: "Snippets run on the server over SSH, inside the project folder you give."))
                    .font(.callout).foregroundStyle(.tertiary).multilineTextAlignment(.center).frame(maxWidth: 360)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func row<Content: View>(_ label: String, detail: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                if let detail {
                    Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(width: 180, alignment: .leading)
            HStack(spacing: 10, content: content).frame(maxWidth: .infinity)
        }
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) { Divider() }
    }

    @ViewBuilder
    private var statusLine: some View {
        switch status {
        case .ok(let text):
            Label(text, systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed(let text):
            Label(text, systemImage: "xmark.circle.fill").foregroundStyle(.red).lineLimit(2).textSelection(.enabled)
        case .working(let text):
            HStack(spacing: 8) { ProgressView().controlSize(.small); Text(text).foregroundStyle(.secondary) }
        case nil:
            EmptyView()
        }
    }

    // MARK: Actions

    private func load(_ id: UUID?) {
        status = nil
        guard let connection = store.connection(id: id) else { return }
        draft = connection
        password = ""
        key = ""
        passphrase = ""
        keyNeedsPassphrase = false
        // Show what's saved without pulling secrets into the fields.
        switch connection.credential {
        case .password(let saved): password = saved
        case .key(let saved, let savedPassphrase): key = saved; passphrase = savedPassphrase
        case nil: break
        }
    }

    private func startNew() {
        selection = nil
        draft = RemoteConnection()
        password = ""; key = ""; passphrase = ""
        keyNeedsPassphrase = false
        status = nil
    }

    private var credential: Credential? {
        guard let draft else { return nil }
        switch draft.auth {
        case .password: return password.isEmpty ? nil : .password(password)
        case .key: return key.isEmpty ? nil : .key(key, passphrase: passphrase)
        }
    }

    @discardableResult
    private func save() -> RemoteConnection? {
        guard var connection = draft else { return nil }
        connection.name = connection.name.trimmingCharacters(in: .whitespaces)
        connection.host = connection.host.trimmingCharacters(in: .whitespaces)
        if connection.phpPath.trimmingCharacters(in: .whitespaces).isEmpty { connection.phpPath = "php" }
        store.save(connection)
        if let credential { connection.save(credential) }
        draft = connection
        selection = connection.id
        status = .ok(String(localized: "Saved"))
        return connection
    }

    private func test(thenConnect: Bool) {
        guard let connection = save() else { return }
        guard let credential else {
            status = .failed(connection.auth == .password ? String(localized: "Enter the password first.")
                                                          : String(localized: "Choose a private key first."))
            return
        }
        busy = true
        status = .working(thenConnect ? String(localized: "Connecting to \(connection.title)…")
                                      : String(localized: "Testing \(connection.title)…"))
        Task {
            defer { busy = false }
            do {
                let version = try await RemoteRunner.test(connection, credential: credential)
                status = .ok(String(localized: "Connected. PHP \(version) on \(connection.host)."))
                if thenConnect {
                    workspace.connect(connection)
                    dismiss()
                }
            } catch let error as HostKeyError {
                status = nil
                hostKey = error
            } catch {
                status = .failed(error.localizedDescription)
            }
        }
    }

    private func chooseKey(_ binding: Binding<RemoteConnection>) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.showsHiddenFiles = true
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".ssh")
        panel.message = String(localized: "Choose your private key (not the .pub file).")
        guard panel.runModal() == .OK, let url = panel.url,
              let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        do {
            keyNeedsPassphrase = try SSHKey.inspect(text)
            key = text
            binding.wrappedValue.keyName = url.lastPathComponent
            status = nil
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    private func chooseLocalProject(_ binding: Binding<RemoteConnection>) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.message = String(localized: "Choose the project's folder on this Mac.")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        binding.wrappedValue.localProject = url.path(percentEncoded: false)
    }
}

/// "Ungrouped" or a group's name, with rename and remove on hover for real groups.
private struct GroupHeader: View {
    let name: String
    let rename: () -> Void
    let remove: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 6) {
            Text(name.isEmpty ? String(localized: "Ungrouped") : name)
                .font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            Spacer()
            if !name.isEmpty, hovering {
                Button(action: rename) { Image(systemName: "pencil") }.help(String(localized: "Rename group"))
                Button(action: remove) { Image(systemName: "trash") }.help(String(localized: "Remove group (its servers stay)"))
            }
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
        .frame(height: 22)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}

/// A server in the list: color bar, name and host; duplicate and delete appear on hover.
private struct ConnectionRow: View {
    let connection: RemoteConnection
    let isSelected: Bool
    let select: () -> Void
    let duplicate: () -> Void
    let remove: () -> Void
    @Environment(\.theme) private var theme
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 1.5).fill(Color(hex: connection.color)).frame(width: 3, height: 34)
            VStack(alignment: .leading, spacing: 3) {
                Text(connection.title).font(.system(size: 13, weight: .medium)).foregroundStyle(theme.textColor).lineLimit(1)
                Text(connection.host.isEmpty ? "—" : connection.host).font(.system(size: 11.5)).foregroundStyle(theme.mutedColor).lineLimit(1)
            }
            Spacer()
            if hovering {
                Button(action: duplicate) { Image(systemName: "doc.on.doc") }.help(String(localized: "Duplicate"))
                Button(action: remove) { Image(systemName: "trash") }.help(String(localized: "Delete"))
            }
        }
        .buttonStyle(.borderless)
        .foregroundStyle(theme.mutedColor)
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(isSelected ? theme.accentColor.opacity(0.14) : hovering ? theme.accentColor.opacity(0.06) : .clear,
                    in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onTapGesture(perform: select)
        .onHover { hovering = $0 }
    }
}

/// The palette of dots next to the label.
private struct ColorDots: View {
    @Binding var selected: String

    var body: some View {
        HStack(spacing: 6) {
            ForEach(RemoteConnection.colors, id: \.self) { hex in
                Circle().fill(Color(hex: hex)).frame(width: 14, height: 14)
                    .overlay(Circle().strokeBorder(.primary.opacity(selected == hex ? 0.9 : 0), lineWidth: 2))
                    .onTapGesture { selected = hex }
            }
        }
    }
}

/// Asks for a group's name.
private struct GroupNameSheet: View {
    let prompt: ConnectionsSheet.GroupPrompt
    let done: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(prompt.old == nil ? String(localized: "New group") : String(localized: "Rename group")).font(.headline)
            TextField(String(localized: "Group name"), text: $name, prompt: Text(String(localized: "Clients, Staging, …")))
                .textFieldStyle(.roundedBorder)
                .onSubmit(submit)
            HStack {
                Spacer()
                Button(String(localized: "Cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(prompt.old == nil ? String(localized: "Add") : String(localized: "Rename"), action: submit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 340)
        .onAppear { name = prompt.name }
    }

    private func submit() {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        done(name)
        dismiss()
    }
}

extension Color {
    /// "#RRGGBB" to a color; anything else is gray.
    init(hex: String) {
        var value: UInt64 = 0x8B8D98
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        if digits.count == 6, let parsed = UInt64(digits, radix: 16) { value = parsed }
        self.init(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
    }
}
