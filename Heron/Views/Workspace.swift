import AppKit
import Observation

/// The window's state: open tabs, the chosen one, recent projects and the run history.
@MainActor @Observable
final class Workspace {
    private(set) var tabs: [Tab]
    var selectedID: UUID {
        didSet { save() }
    }
    private(set) var recentProjects: [URL]
    let history = History()
    let php: URL?
    let phpVersion: String?
    /// Why the snippet couldn't even start, when there's no PHP.
    private(set) var failure: String?

    init() {
        let defaults = UserDefaults.standard
        php = PHPBinary.find()
        phpVersion = php.flatMap(PHPRunner.version(of:))
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
        if tabs.isEmpty { tabs = [Tab()] }
        self.tabs = tabs
        let selected = defaults.string(forKey: "workspace.selected").flatMap(UUID.init)
        selectedID = tabs.first { $0.id == selected }?.id ?? tabs[0].id
    }

    var selected: Tab {
        tabs.first { $0.id == selectedID } ?? tabs[0]
    }

    // MARK: Tabs

    @discardableResult
    func newTab(code: String = "", project: URL? = nil) -> Tab {
        let tab = Tab(code: code, project: project ?? selected.project)
        tabs.append(tab)
        selectedID = tab.id
        return tab
    }

    /// Closes a tab; the last tab is emptied instead, so there's always one.
    func close(_ tab: Tab) {
        tab.stop()
        guard tabs.count > 1, let index = tabs.firstIndex(where: { $0.id == tab.id }) else {
            tabs[0].code = ""
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

    func chooseProject() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.message = String(localized: "Choose a PHP or Laravel project. Snippets run inside it.")
        panel.prompt = String(localized: "Choose")
        if panel.runModal() == .OK, let url = panel.url { setProject(url) }
    }

    func setProject(_ url: URL?) {
        selected.project = url
        if let url { remember(url) }
        save()
    }

    private func remember(_ url: URL) {
        recentProjects = ([url] + recentProjects.filter { $0 != url }).prefix(8).map { $0 }
        UserDefaults.standard.set(recentProjects.map { $0.path(percentEncoded: false) }, forKey: "workspace.recent")
    }

    // MARK: Running

    func run(tidy: Bool, indent: String) {
        guard let php else {
            failure = RunnerError.noPHP.localizedDescription
            return
        }
        failure = nil
        let tab = selected
        tab.run(php: php, tidy: tidy, indent: indent) { [weak self] _ in
            self?.history.add(code: tab.code, project: tab.project)
            self?.save()
        }
    }

    func stop() { selected.stop() }
}
