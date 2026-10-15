import SwiftUI

/// Icon rail on the left, tabs on top, editor and results side by side (or stacked), status bar below.
struct MainWindow: View {
    @Bindable var workspace: Workspace
    @AppStorage(EditorSettings.fontName) private var fontName = EditorSettings.systemFont
    @AppStorage(EditorSettings.fontSize) private var fontSize = 13.0
    @AppStorage(EditorSettings.indentWidth) private var indentWidth = 4
    @AppStorage(EditorSettings.usesTabs) private var usesTabs = false
    @AppStorage(EditorSettings.wrapsLines) private var wrapsLines = true
    @AppStorage(EditorSettings.formatsOnRun) private var formatsOnRun = true
    @AppStorage("layout.stacked") private var stacked = true
    @AppStorage("result.showsQueries") private var showsQueries = true
    @State private var showsHistory = false

    var body: some View {
        HStack(spacing: 0) {
            Rail(workspace: workspace, run: run, history: { showsHistory = true })
            Divider()
            VStack(spacing: 0) {
                TabBar(workspace: workspace)
                Divider()
                if stacked {
                    VSplitView { editor; results }
                } else {
                    HSplitView { editor; results }
                }
                Divider()
                StatusBar(workspace: workspace)
            }
        }
        .navigationTitle("Heron — \(workspace.selected.title)")
        .sheet(isPresented: $showsHistory) { HistorySheet(workspace: workspace) }
        .onReceive(NotificationCenter.default.publisher(for: .heronShowHistory)) { _ in showsHistory = true }
        #if DEBUG
        // `-heron.runOnLaunch YES` runs the snippet once at launch, for screenshots and checks.
        .task {
            if UserDefaults.standard.bool(forKey: "heron.runOnLaunch"), workspace.selected.result == nil {
                run()
            }
        }
        #endif
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { showsQueries.toggle() } label: {
                    Text("SQL")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(showsQueries ? Color.heron : .secondary)
                }
                .help(showsQueries ? String(localized: "Hide database queries") : String(localized: "Show database queries"))
                Button { stacked.toggle() } label: {
                    Label(String(localized: "Layout"), systemImage: stacked ? "rectangle.split.1x2" : "rectangle.split.2x1")
                }
                .help(stacked ? String(localized: "Show the result beside the code")
                              : String(localized: "Show the result below the code"))
            }
        }
    }

    private var editor: some View {
        let tab = workspace.selected
        return CodeEditor(text: Binding(get: { tab.code }, set: { tab.code = $0; workspace.save() }),
                          notes: tab.notes,
                          font: EditorSettings.font(name: fontName, size: fontSize),
                          indentUnit: EditorSettings.indentUnit(tabs: usesTabs, width: indentWidth),
                          wrapsLines: wrapsLines)
            .id(tab.id)
            .background(Color(nsColor: .textBackgroundColor))
            .frame(minWidth: 360, idealWidth: 560, minHeight: 160)
    }

    private var results: some View {
        ResultPanel(tab: workspace.selected, failure: workspace.failure)
            .frame(minWidth: 280, idealWidth: 400, minHeight: 120)
    }

    private func run() {
        workspace.run(tidy: formatsOnRun, indent: EditorSettings.indentUnit(tabs: usesTabs, width: indentWidth))
    }
}

extension Notification.Name {
    static let heronShowHistory = Notification.Name("heron.showHistory")
}

/// The narrow column of actions on the left.
private struct Rail: View {
    let workspace: Workspace
    let run: () -> Void
    let history: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            if workspace.selected.isRunning {
                RailButton(symbol: "stop.circle", help: String(localized: "Stop (⌘.)"), tint: .red) { workspace.stop() }
            } else {
                RailButton(symbol: "play", help: String(localized: "Run (⌘R)"), action: run)
            }
            Menu {
                Button(String(localized: "Choose Project…")) { workspace.chooseProject() }
                Button(String(localized: "No Project (Plain PHP)")) { workspace.setProject(nil) }
                    .disabled(workspace.selected.project == nil)
                if !workspace.recentProjects.isEmpty {
                    Divider()
                    ForEach(workspace.recentProjects, id: \.self) { url in
                        Button(url.lastPathComponent) { workspace.setProject(url) }
                    }
                }
            } label: {
                Image(systemName: "folder")
                    .font(.system(size: 19, weight: .light))
                    .frame(width: 36, height: 36)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(String(localized: "Project (⌘O)"))
            RailButton(symbol: "clock", help: String(localized: "History (⌘Y)"), action: history)
            Spacer()
            SettingsLink {
                Image(systemName: "gearshape").font(.system(size: 19, weight: .light)).frame(width: 36, height: 36)
            }
            .buttonStyle(.borderless)
            .help(String(localized: "Settings"))
        }
        .foregroundStyle(.secondary)
        .padding(.vertical, 6)
        .frame(width: 46)
        .background(Color(nsColor: .textBackgroundColor))
    }
}

private struct RailButton: View {
    let symbol: String
    let help: String
    var tint: Color = .secondary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 19, weight: .light))
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(help)
    }
}

/// Framework, PHP version and the last run's time and memory, then the project's path.
private struct StatusBar: View {
    let workspace: Workspace

    var body: some View {
        let tab = workspace.selected
        HStack(spacing: 0) {
            if let result = tab.result, result.kind == .laravel, let version = result.framework {
                segment("Laravel \(version)")
            }
            segment(workspace.phpVersion.map { "PHP \($0)" } ?? String(localized: "PHP not found"),
                    color: workspace.phpVersion == nil ? .red : .secondary)
            if let result = tab.result, let ms = result.milliseconds {
                let time = ms < 1 ? "<1 ms" : String(format: "%.0f ms", ms)
                let memory = result.memory.map { " / " + ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .memory) } ?? ""
                segment(time + memory)
            }
            Spacer()
            Text(tab.project.map { ($0.path(percentEncoded: false) as NSString).abbreviatingWithTildeInPath }
                 ?? String(localized: "Plain PHP"))
                .lineLimit(1)
                .truncationMode(.head)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 12)
        }
        .font(.system(size: 11, design: .monospaced))
        .frame(height: 26)
        .background(Color.heronPanel)
    }

    private func segment(_ text: String, color: Color = .secondary) -> some View {
        HStack(spacing: 0) {
            Text(text).foregroundStyle(color).padding(.horizontal, 12)
            Divider().frame(height: 14)
        }
    }
}
