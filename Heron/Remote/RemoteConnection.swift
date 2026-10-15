import Foundation
import Observation

/// A server a snippet can run on: where it is, who signs in, and which folder holds the project.
/// Passwords, passphrases and keys live in Keychain, not here.
struct RemoteConnection: Codable, Identifiable, Hashable {
    enum Auth: String, Codable, CaseIterable { case key, password }

    var id = UUID()
    var name = ""
    /// The group heading it sits under in the manager; empty is "Ungrouped".
    var group = ""
    /// A hex color for the dot next to the name, to tell production from staging at a glance.
    var color = RemoteConnection.colors[0]
    var host = ""
    var port = 22
    var username = ""
    var auth = Auth.key
    /// File name of the chosen key, shown in the form; the key itself is in Keychain.
    var keyName: String?
    /// The project folder on the server, e.g. /home/forge/example.com/current.
    var remotePath = ""
    /// A copy of the project on this Mac, so completion can index its classes.
    var localProject: String?
    /// The php to run there; "php" uses whatever is on the server's PATH.
    var phpPath = "php"

    static let colors = ["#DB578E", "#E5484D", "#F5A524", "#30A46C", "#3E8EF7", "#8E4EC6", "#8B8D98"]

    var title: String { name.isEmpty ? host : name }
    var isComplete: Bool { !host.trimmingCharacters(in: .whitespaces).isEmpty && !username.isEmpty }
    var localProjectURL: URL? {
        guard let localProject, !localProject.isEmpty else { return nil }
        let url = URL(filePath: localProject)
        return FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) ? url : nil
    }

    var passwordAccount: String { "connection:\(id.uuidString):password" }
    var keyAccount: String { "connection:\(id.uuidString):key" }
    var passphraseAccount: String { "connection:\(id.uuidString):passphrase" }

    /// What's saved in Keychain for this connection, or nil when something is missing.
    var credential: Credential? {
        switch auth {
        case .password:
            return Keychain.password(account: passwordAccount).map(Credential.password)
        case .key:
            guard let key = Keychain.password(account: keyAccount) else { return nil }
            return .key(key, passphrase: Keychain.password(account: passphraseAccount) ?? "")
        }
    }

    func save(_ credential: Credential) {
        switch credential {
        case .password(let password):
            Keychain.setPassword(password, account: passwordAccount)
        case .key(let key, let passphrase):
            Keychain.setPassword(key, account: keyAccount)
            Keychain.setPassword(passphrase, account: passphraseAccount)
        }
    }

    func forgetSecrets() {
        for account in [passwordAccount, keyAccount, passphraseAccount] { Keychain.deletePassword(account: account) }
    }

    /// A copy with its own id and secrets, named "… copy".
    func duplicate() -> RemoteConnection {
        var copy = self
        copy.id = UUID()
        copy.name = String(localized: "\(title) copy")
        if let credential { copy.save(credential) }
        return copy
    }
}

/// The saved connections and group names, in Application Support/Heron/connections.json.
/// Groups are kept by name so an empty group survives until it's removed.
@MainActor @Observable
final class ConnectionStore {
    private(set) var connections: [RemoteConnection] = []
    private(set) var groups: [String] = []
    /// Ids in the order they were last connected to, newest first.
    private(set) var recent: [UUID] = []

    private struct File: Codable {
        var groups: [String] = []
        var connections: [RemoteConnection] = []
        var recent: [UUID] = []
    }

    private static var file: URL {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Heron")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appending(path: "connections.json")
    }

    init() {
        if let data = try? Data(contentsOf: Self.file), let saved = try? JSONDecoder().decode(File.self, from: data) {
            connections = saved.connections
            groups = saved.groups
            recent = saved.recent.filter { id in saved.connections.contains { $0.id == id } }
        }
    }

    func connection(id: UUID?) -> RemoteConnection? {
        connections.first { $0.id == id }
    }

    /// The last few connected to, for the rail popover.
    var recentConnections: [RemoteConnection] {
        let ordered = recent.compactMap(connection(id:))
        return ordered.isEmpty ? Array(connections.prefix(5)) : Array(ordered.prefix(5))
    }

    /// Group headings in order, each with its members; "" is Ungrouped and comes first.
    var sections: [(group: String, connections: [RemoteConnection])] {
        let names = [""] + groups + connections.map(\.group).filter { !$0.isEmpty && !groups.contains($0) }
        var seen = Set<String>()
        return names.filter { seen.insert($0).inserted }.compactMap { name in
            let members = connections.filter { $0.group == name }
            if members.isEmpty, name.isEmpty || !groups.contains(name) { return nil }
            return (name, members)
        }
    }

    func save(_ connection: RemoteConnection) {
        if let index = connections.firstIndex(where: { $0.id == connection.id }) {
            connections[index] = connection
        } else {
            connections.append(connection)
        }
        if !connection.group.isEmpty, !groups.contains(connection.group) { groups.append(connection.group) }
        persist()
    }

    func remove(_ connection: RemoteConnection) {
        connection.forgetSecrets()
        connections.removeAll { $0.id == connection.id }
        recent.removeAll { $0 == connection.id }
        persist()
    }

    func addGroup(_ name: String) {
        let name = name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !groups.contains(name) else { return }
        groups.append(name)
        persist()
    }

    func renameGroup(_ old: String, to new: String) {
        let new = new.trimmingCharacters(in: .whitespaces)
        guard !new.isEmpty, new != old else { return }
        groups = groups.map { $0 == old ? new : $0 }
        for index in connections.indices where connections[index].group == old { connections[index].group = new }
        persist()
    }

    /// Removes the heading; its connections become ungrouped.
    func removeGroup(_ name: String) {
        groups.removeAll { $0 == name }
        for index in connections.indices where connections[index].group == name { connections[index].group = "" }
        persist()
    }

    func noteConnected(_ id: UUID) {
        recent = [id] + recent.filter { $0 != id }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(File(groups: groups, connections: connections, recent: recent)) {
            try? data.write(to: Self.file, options: .atomic)
        }
    }
}
