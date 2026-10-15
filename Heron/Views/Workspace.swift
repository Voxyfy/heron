import AppKit
import Observation

/// The window's state: open tabs, the chosen one, recent projects, history and snippets.
@MainActor @Observable
final class Workspace {
    private(set) var tabs: [Tab]
    var selectedID: UUID {
        didSet { save() }
    }
    private(set) var recentProjects: [URL]
    let history = History()
    let snippets = SnippetStore()
    let connections = ConnectionStore()
    let license = LicenseState()
    /// Why the snippet couldn't even start, when there's no PHP.
    private(set) var failure: String?
    private var versions: [URL: String] = [:]

    static let welcomeKey = "welcome.enabled"

    init() {
        let defaults = UserDefaults.standard
        recentProjects = (defaults.stringArray(forKey: "workspace.recent") ?? []).map { URL(filePath: $0) }

        var tabs: [Tab] = []
        if let data = defaults.data(forKey: "workspace.tabs"),
           let saved = try? JSONDecoder().decode([Tab.Saved].self, from: data) {
            tabs = saved.map(Tab.init(saved:))
        } else if let code = defaults.string(forKey: "workspace.code") {
            // Before tabs, there was one snippet.
            let project = defaults.string(forKey: "workspace.project").map { URL(filePath: $0) }
            tabs = [Tab(code: code, project: project)]
        }
        let wantsWelcome = defaults.object(forKey: Self.welcomeKey) == nil || defaults.bool(forKey: Self.welcomeKey)
        if wantsWelcome, !tabs.contains(where: \.isWelcome) {
            tabs.insert(Tab(isWelcome: true), at: 0)
        }
        if tabs.isEmpty { tabs = [Tab()] }
        self.tabs = tabs
        let selected = defaults.string(forKey: "workspace.selected").flatMap(UUID.init)
        selectedID = tabs.first { $0.id == selected }?.id ?? tabs[0].id
    }

    var selected: Tab {
        tabs.first { $0.id == selectedID } ?? tabs[0]
    }

    func connection(of tab: Tab) -> RemoteConnection? {
        connections.connection(id: tab.connectionID)
    }

    func title(of tab: Tab) -> String {
        tab.title(connection: connection(of: tab))
    }

    // MARK: PHP

    /// The PHP chosen in Settings, or the first one found on this Mac.
    var php: URL? { PHPBinary.find() }

    var phpVersion: String? {
        guard let php else { return nil }
        if let known = versions[php] { return known }
        let version = PHPRunner.version(of: php)
        if let version { versions[php] = version }
        return version
    }

    func forgetVersions() { versions = [:] }

    // MARK: Tabs

    /// ⌘T and "+": a Get started page, where the project (or plain PHP) is chosen first.
    func newWelcomeTab() {
        let tab = Tab(isWelcome: true)
        tabs.append(tab)
        selectedID = tab.id
        save()
    }

    /// A code tab with this content. When the current tab is a Get started page it becomes that tab,
    /// so choosing a project there doesn't leave the page behind.
    @discardableResult
    func newTab(code: String = "", project: URL? = nil, keepProject: Bool = true) -> Tab {
        let tab = Tab(code: code, project: project ?? (keepProject && !selected.isWelcome ? selected.project : nil))
        if let project { remember(project) }
        if selected.isWelcome, let index = tabs.firstIndex(where: { $0.id == selectedID }) {
            tabs[index] = tab
        } else {
            tabs.append(tab)
        }
        selectedID = tab.id
        save()
        return tab
    }

    /// Closes a tab; the last code tab is emptied instead, so there's always one.
    func close(_ tab: Tab) {
        tab.stop()
        guard let index = tabs.firstIndex(where: { $0.id == tab.id }) else { return }
        if tabs.count == 1 {
            if tab.isWelcome { tabs = [Tab()]; selectedID = tabs[0].id } else { tab.code = "" }
            save()
            return
        }
        tabs.remove(at: index)
        if selectedID == tab.id {
            selectedID = tabs[min(index, tabs.count - 1)].id
        }
        save()
    }

    func select(_ tab: Tab) { selectedID = tab.id }

    func save() {
        let defaults = UserDefaults.standard
        if let data = try? JSONEncoder().encode(tabs.map(\.saved)) {
            defaults.set(data, forKey: "workspace.tabs")
        }
        defaults.set(selectedID.uuidString, forKey: "workspace.selected")
    }

    // MARK: Projects

    func chooseProject(forNewTab: Bool = false) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.message = String(localized: "Choose a PHP or Laravel project. Snippets run inside it.")
        panel.prompt = String(localized: "Choose")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if forNewTab || selected.isWelcome {
            newTab(project: url)
        } else {
            setProject(url)
        }
    }

    func setProject(_ url: URL?) {
        if selected.isWelcome {
            newTab(project: url, keepProject: false)
            return
        }
        selected.project = url
        if let url { remember(url) }
        save()
    }

    // MARK: Servers

    /// Puts the current tab on a server, or opens a tab for it from the Get started page.
    func connect(_ connection: RemoteConnection) {
        connections.noteConnected(connection.id)
        if selected.isWelcome {
            let tab = newTab(project: connection.localProjectURL, keepProject: false)
            tab.connectionID = connection.id
        } else {
            selected.connectionID = connection.id
            if let local = connection.localProjectURL { selected.project = local }
        }
        save()
    }

    /// Back to this Mac's PHP.
    func disconnect() {
        guard !selected.isWelcome else { return }
        selected.connectionID = nil
        save()
    }

    /// Trusts the server key the last run stopped at, then runs again.
    func trustHostKey(tidy: Bool, indent: String) {
        guard let error = selected.hostKeyError else { return }
        HostKeys.trust(error.presentedKey, host: error.host, port: error.port)
        selected.hostKeyError = nil
        run(tidy: tidy, indent: indent)
    }

    private func remember(_ url: URL) {
        recentProjects = ([url] + recentProjects.filter { $0 != url }).prefix(8).map { $0 }
        UserDefaults.standard.set(recentProjects.map { $0.path(percentEncoded: false) }, forKey: "workspace.recent")
    }

    // MARK: Running

    /// Set when a run was refused because the trial ended; the window shows the license sheet.
    var wantsLicense = false

    func run(tidy: Bool, indent: String) {
        guard !selected.isWelcome else { return }
        guard license.canRun else {
            wantsLicense = true
            return
        }
        let tab = selected
        let connection = connection(of: tab)
        // A server run needs no PHP here; only tidying does, and it's skipped without one.
        if connection == nil, php == nil {
            failure = RunnerError.noPHP.localizedDescription
            return
        }
        failure = nil
        tab.run(php: php, connection: connection, tidy: tidy, indent: indent) { [weak self] _ in
            self?.history.add(code: tab.code, project: tab.project)
            self?.save()
        }
    }

    func stop() { selected.stop() }
}
