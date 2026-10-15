import SwiftUI

/// Icon rail on the left, tabs on top, editor and results stacked (or side by side), status bar below.
struct MainWindow: View {
    @Bindable var workspace: Workspace
    @AppStorage(EditorSettings.fontName) private var fontName = EditorSettings.systemFont
    @AppStorage(EditorSettings.fontSize) private var fontSize = 15.0
    @AppStorage(EditorSettings.indentWidth) private var indentWidth = 4
    @AppStorage(EditorSettings.usesTabs) private var usesTabs = false
    @AppStorage(EditorSettings.wrapsLines) private var wrapsLines = true
    @AppStorage(EditorSettings.formatsOnRun) private var formatsOnRun = true
    @AppStorage(Theme.key) private var themeID = Theme.defaultID
    @AppStorage("layout.stacked") private var stacked = true
    @AppStorage("layout.resultsHidden") private var resultsHidden = false
    @AppStorage("result.showsQueries") private var showsQueries = false
    @AppStorage("result.plain") private var plainOutput = false
    @State private var sheet: Sheet?
    @State private var table: DumpNode?

    enum Sheet: Identifiable {
        case history, snippets, saveSnippet(String), palette, connections, logs, license
        var id: String {
            switch self {
            case .logs: "logs"
            case .license: "license"
            case .history: "history"
            case .snippets: "snippets"
            case .saveSnippet: "save"
            case .palette: "palette"
            case .connections: "connections"
            }
        }
    }

    private var theme: Theme { Theme.named(themeID) }

    var body: some View {
        HStack(spacing: 0) {
            Rail(workspace: workspace, run: run, history: { sheet = .history }, snippets: { sheet = .snippets },
                 connections: { sheet = .connections }, logs: { sheet = .logs })
            VStack(spacing: 0) {
                TabBar(workspace: workspace)
                Rectangle().fill(theme.borderColor).frame(height: 1)
                if workspace.selected.isWelcome {
                    WelcomeView(workspace: workspace)
                } else if resultsHidden || !workspace.selected.hasRun {
                    // Nothing has run yet: the editor alone, like a fresh scratchpad.
                    editor
                } else if stacked {
                    VSplitView { editor; results }
                } else {
                    HSplitView { editor; results }
                }
                Rectangle().fill(theme.borderColor).frame(height: 1)
                StatusBar(workspace: workspace, resultsHidden: $resultsHidden)
            }
        }
        .environment(\.theme, theme)
        .environment(workspace.license)
        .background(theme.panelColor)
        .navigationTitle("Heron — \(workspace.title(of: workspace.selected))")
        .sheet(item: $sheet) { which in
            Group {
                switch which {
                case .history: HistorySheet(workspace: workspace)
                case .snippets: SnippetsSheet(workspace: workspace)
                case .saveSnippet(let code): SnippetsSheet(workspace: workspace, newCode: code)
                case .palette: CommandPalette(workspace: workspace, perform: perform)
                case .connections: ConnectionsSheet(workspace: workspace)
                case .logs: LogsSheet(workspace: workspace)
                case .license: LicenseSheet(license: workspace.license)
                }
            }
            .environment(\.theme, theme)
            .background(theme.backgroundColor)
            .preferredColorScheme(theme.isDark ? .dark : .light)
        }
        .sheet(item: $table) { node in
            TablePreview(node: node).environment(\.theme, theme).background(theme.backgroundColor)
                .preferredColorScheme(theme.isDark ? .dark : .light)
        }
        .environment(\.openTable, OpenTable { node in table = node })
        .onReceive(NotificationCenter.default.publisher(for: .heronShowHistory)) { _ in sheet = .history }
        .onReceive(NotificationCenter.default.publisher(for: .heronShowSnippets)) { _ in sheet = .snippets }
        .onReceive(NotificationCenter.default.publisher(for: .heronSaveSnippet)) { _ in
            if !workspace.selected.isWelcome { sheet = .saveSnippet(workspace.selected.code) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .heronShowPalette)) { _ in sheet = .palette }
        .onReceive(NotificationCenter.default.publisher(for: .heronShowConnections)) { _ in sheet = .connections }
        .onReceive(NotificationCenter.default.publisher(for: .heronShowLogs)) { _ in sheet = .logs }
        .onReceive(NotificationCenter.default.publisher(for: .heronShowLicense)) { _ in sheet = .license }
        .onChange(of: workspace.wantsLicense) {
            if workspace.wantsLicense { sheet = .license; workspace.wantsLicense = false }
        }
        .task {
            // Ask once at launch when the trial is over; otherwise just re-check a saved key quietly.
            if !workspace.license.canRun { sheet = .license }
            await workspace.license.refresh()
        }
        .alert(String(localized: "Trust this server?"),
               isPresented: Binding(get: { workspace.selected.hostKeyError != nil },
                                    set: { if !$0 { workspace.selected.hostKeyError = nil } }),
               presenting: workspace.selected.hostKeyError) { _ in
            Button(String(localized: "Trust")) {
                workspace.trustHostKey(tidy: formatsOnRun, indent: EditorSettings.indentUnit(tabs: usesTabs, width: indentWidth))
            }
            Button(String(localized: "Cancel"), role: .cancel) { workspace.selected.hostKeyError = nil }
        } message: { error in
            Text(verbatim: (error.errorDescription ?? "") + "\n\n" + HostKeys.fingerprint(error.presentedKey))
        }
        #if DEBUG
        // `-heron.runOnLaunch YES` runs the snippet once at launch, for screenshots and checks.
        .task {
            if UserDefaults.standard.bool(forKey: "heron.runOnLaunch"), workspace.selected.result == nil {
                run()
            }
            // `-heron.showConnections YES` opens the connection manager, for screenshots.
            if UserDefaults.standard.bool(forKey: "heron.showConnections") { sheet = .connections }
            if UserDefaults.standard.bool(forKey: "heron.showLogs") { sheet = .logs }
            if UserDefaults.standard.bool(forKey: "heron.showLicense") { sheet = .license }
            // `-heron.licenseKey XXXX` activates that key at launch, to check the flow end to end.
            if let key = UserDefaults.standard.string(forKey: "heron.licenseKey"), !key.isEmpty {
                try? await workspace.license.activate(key)
                sheet = .license
            }
        }
        #endif
        .toolbar(removing: .title)
        .toolbarBackground(theme.panelColor, for: .windowToolbar)
        .toolbarBackgroundVisibility(.visible, for: .windowToolbar)
        .toolbarColorScheme(theme.isDark ? .dark : .light, for: .windowToolbar)
        .toolbar { toolbarItems }
    }

    /// Title in the middle, then SQL, results style and layout on the right. On macOS 26 the
    /// toolbar draws a glass pill behind items; the reference has none, so it is switched off.
    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        if #available(macOS 26.0, *) {
            ToolbarItem(placement: .principal) { titleView }.sharedBackgroundVisibility(.hidden)
            ToolbarItemGroup(placement: .primaryAction) { actionButtons }.sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .principal) { titleView }
            ToolbarItemGroup(placement: .primaryAction) { actionButtons }
        }
    }

    private var titleView: some View {
        Text("Heron - \(workspace.title(of: workspace.selected))")
            .font(.system(size: 13))
            .foregroundStyle(theme.textColor)
    }

    @ViewBuilder
    private var actionButtons: some View {
        Button { showsQueries.toggle() } label: {
            Text("SQL")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(showsQueries ? theme.accentColor : theme.textColor)
        }
        .help(showsQueries ? String(localized: "Hide database queries") : String(localized: "Show database queries"))
        Button { plainOutput.toggle() } label: {
            Image(systemName: "square.3.layers.3d")
                .font(.system(size: 14))
                .foregroundStyle(theme.accentColor)
        }
        .help(plainOutput ? String(localized: "Show results as cards") : String(localized: "Show results as plain output"))
        Button { stacked.toggle() } label: {
            Image(systemName: "chevron.left.forwardslash.chevron.right")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(theme.textColor)
                .frame(width: 22, height: 20)
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(theme.textColor.opacity(0.8)))
        }
        .help(stacked ? String(localized: "Show the result beside the code")
                      : String(localized: "Show the result below the code"))
    }

    private var editor: some View {
        let tab = workspace.selected
        return CodeEditor(text: Binding(get: { tab.code }, set: { tab.code = $0; workspace.save() }),
                          notes: tab.notes,
                          font: EditorSettings.font(name: fontName, size: fontSize),
                          indentUnit: EditorSettings.indentUnit(tabs: usesTabs, width: indentWidth),
                          wrapsLines: wrapsLines,
                          theme: theme,
                          project: tab.project)
            .id(tab.id)
            .background(theme.backgroundColor)
            .frame(minWidth: 360, idealWidth: 560, minHeight: 160)
    }

    private var results: some View {
        ResultPanel(tab: workspace.selected, failure: workspace.failure)
            .frame(minWidth: 280, idealWidth: 400, minHeight: 120)
    }

    private func run() {
        workspace.run(tidy: formatsOnRun, indent: EditorSettings.indentUnit(tabs: usesTabs, width: indentWidth))
    }

    private func perform(_ action: CommandPalette.Action) {
        switch action {
        case .run: run()
        case .stop: workspace.stop()
        case .newTab: workspace.newWelcomeTab()
        case .chooseProject: workspace.chooseProject()
        case .plainPHP: workspace.setProject(nil)
        case .history: sheet = .history
        case .snippets: sheet = .snippets
        case .settings: NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        case .connections: sheet = .connections
        case .connect(let connection): workspace.connect(connection)
        case .logs: sheet = .logs
        case .license: sheet = .license
        case .toggleLayout: stacked.toggle()
        case .toggleQueries: showsQueries.toggle()
        case .openFolder(let url): workspace.newTab(project: url, keepProject: false)
        case .openSnippet(let snippet):
            workspace.newTab(code: snippet.code, project: snippet.project.map { URL(filePath: $0) } ?? workspace.selected.project,
                             keepProject: true)
        }
    }
}

extension Notification.Name {
    static let heronShowHistory = Notification.Name("heron.showHistory")
    static let heronShowSnippets = Notification.Name("heron.showSnippets")
    static let heronSaveSnippet = Notification.Name("heron.saveSnippet")
    static let heronShowPalette = Notification.Name("heron.showPalette")
    static let heronShowConnections = Notification.Name("heron.showConnections")
    static let heronShowLogs = Notification.Name("heron.showLogs")
    static let heronShowLicense = Notification.Name("heron.showLicense")
}

/// Lets a result card open the table preview for its value.
struct OpenTable: Sendable {
    let open: @MainActor @Sendable (DumpNode) -> Void
}

private struct OpenTableKey: EnvironmentKey {
    static let defaultValue = OpenTable { _ in }
}

extension EnvironmentValues {
    var openTable: OpenTable {
        get { self[OpenTableKey.self] }
        set { self[OpenTableKey.self] = newValue }
    }
}

/// The narrow column of actions on the left: Lucide icons, all the same size, on an even grid.
private struct Rail: View {
    let workspace: Workspace
    let run: () -> Void
    let history: () -> Void
    let snippets: () -> Void
    let connections: () -> Void
    let logs: () -> Void
    @Environment(\.theme) private var theme
    @State private var showsProjects = false
    @State private var showsServers = false

    var body: some View {
        VStack(spacing: 2) {
            if workspace.selected.isRunning {
                RailButton(icon: "tabler.circle-stop", help: String(localized: "Stop (⌘.)"), tint: .red) { workspace.stop() }
            } else {
                RailButton(icon: "tabler.play", help: String(localized: "Run (⌘R)"), action: run)
                    .disabled(workspace.selected.isWelcome)
            }
            RailButton(icon: "tabler.folder-open", help: String(localized: "Project (⌘O)")) { showsProjects.toggle() }
                .popover(isPresented: $showsProjects, arrowEdge: .trailing) { projectList }
            RailButton(icon: "tabler.server", help: String(localized: "Servers (⌘⇧K)"),
                       tint: workspace.selected.isRemote ? theme.accentColor : nil) { showsServers.toggle() }
                .popover(isPresented: $showsServers, arrowEdge: .trailing) { serverList }
            RailButton(icon: "tabler.clock", help: String(localized: "History (⌘Y)"), action: history)
            RailButton(icon: "tabler.bookmark", help: String(localized: "Snippets (⌘B)"), action: snippets)
            RailButton(icon: "tabler.file-text", help: String(localized: "Logs (⌘L)"), action: logs)
                .disabled(workspace.selected.project == nil && !workspace.selected.isRemote)
            Spacer()
            SettingsLink {
                RailIcon(name: "tabler.settings", tint: theme.textColor.opacity(0.85))
            }
            .buttonStyle(.plain)
            .help(String(localized: "Settings"))
        }
        .padding(.top, 8)
        .padding(.bottom, 6)
        .frame(width: 52)
        .background(theme.panelColor)
        .overlay(alignment: .trailing) { Rectangle().fill(theme.borderColor).frame(width: 1) }
    }

    private var projectList: some View {
        VStack(alignment: .leading, spacing: 2) {
            projectRow(String(localized: "Choose Project…"), symbol: "folder.badge.plus") { workspace.chooseProject() }
            projectRow(String(localized: "No Project (Plain PHP)"), symbol: "terminal") { workspace.setProject(nil) }
                .disabled(workspace.selected.project == nil)
            if !workspace.recentProjects.isEmpty {
                Divider().padding(.vertical, 4)
                ForEach(workspace.recentProjects, id: \.self) { url in
                    projectRow(url.lastPathComponent, symbol: "folder") { workspace.setProject(url) }
                }
            }
        }
        .padding(8)
        .frame(minWidth: 240)
    }

    /// Recent connections, like the reference: name on the left, host on the right.
    private var serverList: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(String(localized: "Recent connections")).font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary).padding(.horizontal, 8).padding(.vertical, 4)
            if workspace.connections.recentConnections.isEmpty {
                Text(String(localized: "No servers yet.")).foregroundStyle(.secondary).padding(.horizontal, 8).padding(.vertical, 5)
            }
            ForEach(workspace.connections.recentConnections) { connection in
                Button {
                    showsServers = false
                    workspace.connect(connection)
                } label: {
                    HStack(spacing: 12) {
                        Circle().fill(Color(hex: connection.color)).frame(width: 7, height: 7)
                        Text(connection.title).lineLimit(1)
                        Spacer()
                        Text(connection.host).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.vertical, 5).padding(.horizontal, 8)
            }
            Divider().padding(.vertical, 4)
            if workspace.selected.isRemote {
                projectRow(String(localized: "Run on this Mac"), symbol: "laptopcomputer") { workspace.disconnect() }
            }
            projectRow(String(localized: "Manage Connections…"), symbol: "slider.horizontal.3") { connections() }
        }
        .padding(8)
        .frame(minWidth: 260)
    }

    private func projectRow(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button {
            showsProjects = false
            showsServers = false
            action()
        } label: {
            Label(title, systemImage: symbol).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
    }
}

/// A Lucide icon from Icons.xcassets, drawn in one color.
private struct RailIcon: View {
    let name: String
    let tint: Color

    var body: some View {
        Image(name)
            .renderingMode(.template)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 26, height: 26)
            .foregroundStyle(tint)
            .frame(width: 52, height: 46)
            .contentShape(Rectangle())
    }
}

private struct RailButton: View {
    let icon: String
    let help: String
    var tint: Color? = nil
    let action: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        Button(action: action) {
            RailIcon(name: icon, tint: tint ?? theme.textColor.opacity(0.85))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

/// Framework, PHP version and the last run's time and memory; on the right, the project's
/// path and a chevron that hides or shows the results.
private struct StatusBar: View {
    let workspace: Workspace
    @Binding var resultsHidden: Bool
    @Environment(\.theme) private var theme

    var body: some View {
        let tab = workspace.selected
        HStack(spacing: 0) {
            if let result = tab.result, result.kind == .laravel, let version = result.framework {
                HStack(spacing: 6) {
                    Text("Laravel \(version)").foregroundStyle(theme.textColor)
                    Image(systemName: "info.circle.fill").font(.system(size: 9)).foregroundStyle(theme.accentColor)
                }
                .padding(.horizontal, 12)
                Rectangle().fill(theme.borderColor).frame(width: 1, height: 14)
            }
            if let connection = workspace.connection(of: tab) {
                segment(tab.result.map { "PHP \($0.php)" } ?? "SSH", color: theme.mutedColor)
                HStack(spacing: 8) {
                    Circle().fill(Color(hex: connection.color)).frame(width: 7, height: 7)
                    Text(String(localized: "Connected to")).foregroundStyle(theme.mutedColor)
                    Text(connection.title).fontWeight(.bold).foregroundStyle(theme.textColor)
                }
                .padding(.horizontal, 12)
                Rectangle().fill(theme.borderColor).frame(width: 1, height: 14)
            } else {
                segment(workspace.phpVersion.map { "PHP \($0)" } ?? String(localized: "PHP not found"),
                        color: workspace.phpVersion == nil ? .red : theme.mutedColor)
            }
            if let result = tab.result, let ms = result.milliseconds {
                let time = ms < 1 ? "<1 ms" : String(format: "%.0f ms", ms)
                let memory = result.memory.map { " / " + ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .memory) } ?? ""
                segment(time + memory)
            }
            if case .trial(let days) = workspace.license.status {
                Button { NotificationCenter.default.post(name: .heronShowLicense, object: nil) } label: {
                    segment(String(localized: "Trial · \(days) days"), color: theme.accentColor)
                }
                .buttonStyle(.plain)
            }
            Spacer()
            Text(workspace.connection(of: tab).map { "\($0.username)@\($0.host):\($0.remotePath)" }
                 ?? tab.project.map { ($0.path(percentEncoded: false) as NSString).abbreviatingWithTildeInPath }
                 ?? (tab.isWelcome ? "" : String(localized: "Plain PHP")))
                .lineLimit(1)
                .truncationMode(.head)
                .foregroundStyle(theme.mutedColor)
                .padding(.horizontal, 12)
            if !tab.isWelcome {
                Rectangle().fill(theme.borderColor).frame(width: 1, height: 14)
                Image(systemName: tab.result?.error == nil ? "checkmark.circle" : "xmark.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(tab.result?.error == nil ? theme.mutedColor : .red)
                    .frame(width: 34, height: 24)
                Rectangle().fill(theme.borderColor).frame(width: 1, height: 14)
                Button { resultsHidden.toggle() } label: {
                    Image(systemName: resultsHidden ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 30, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .foregroundStyle(theme.mutedColor)
                .help(resultsHidden ? String(localized: "Show results") : String(localized: "Hide results"))
            }
        }
        .font(.system(size: 11, design: .monospaced))
        .frame(height: 26)
        .background(theme.panelColor)
    }

    private func segment(_ text: String, color: Color? = nil) -> some View {
        HStack(spacing: 0) {
            Text(text).foregroundStyle(color ?? theme.textColor).padding(.horizontal, 12)
            Rectangle().fill(theme.borderColor).frame(width: 1, height: 14)
        }
    }
}
