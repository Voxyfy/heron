import SwiftUI

/// ⌘P: find anything by typing: commands, recent folders, snippets. "/" limits to folders,
/// "#" to snippets.
struct CommandPalette: View {
    let workspace: Workspace
    let perform: (Action) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme
    @State private var query = ""
    @State private var selected = 0
    @FocusState private var focused: Bool

    enum Action {
        case run, stop, newTab, chooseProject, plainPHP, history, snippets, settings, toggleLayout, toggleQueries
        case openFolder(URL), openSnippet(Snippet)
        case connections, connect(RemoteConnection)
    }

    private struct Entry: Identifiable {
        let id = UUID()
        let title: String
        let detail: String
        let symbol: String
        let kind: String
        let action: Action
    }

    private var entries: [Entry] {
        var all: [Entry] = []
        let commands: [(String, String, String, Action)] = [
            (String(localized: "Run"), String(localized: "Runs the snippet (⌘R)"), "play", .run),
            (String(localized: "New Tab"), String(localized: "Opens an empty tab (⌘T)"), "plus.square", .newTab),
            (String(localized: "Open Project Folder…"), String(localized: "Runs snippets inside a project (⌘O)"), "folder", .chooseProject),
            (String(localized: "Use Plain PHP"), String(localized: "Runs without a project"), "terminal", .plainPHP),
            (String(localized: "Open History"), String(localized: "Snippets that ran before (⌘Y)"), "clock", .history),
            (String(localized: "Open Snippets"), String(localized: "Saved code (⌘B)"), "bookmark", .snippets),
            (String(localized: "Open Settings"), String(localized: "PHP, editor, themes (⌘,)"), "gearshape", .settings),
            (String(localized: "Remote Connections…"), String(localized: "Servers to run snippets on (⌘⇧K)"), "server.rack", .connections),
            (String(localized: "Toggle Layout"), String(localized: "Result below or beside the code"), "rectangle.split.2x1", .toggleLayout),
            (String(localized: "Toggle SQL Queries"), String(localized: "Show or hide database queries"), "cylinder", .toggleQueries),
        ]
        let folders = workspace.recentProjects.map {
            Entry(title: $0.lastPathComponent, detail: ($0.path(percentEncoded: false) as NSString).abbreviatingWithTildeInPath,
                  symbol: "folder", kind: String(localized: "Recent"), action: .openFolder($0))
        }
        let servers = workspace.connections.connections.map {
            Entry(title: $0.title, detail: $0.host, symbol: "server.rack", kind: String(localized: "Server"), action: .connect($0))
        }
        let snippets = workspace.snippets.all(for: workspace.selected.project).map {
            Entry(title: $0.title, detail: $0.projectName ?? $0.description, symbol: "bookmark",
                  kind: String(localized: "Snippet"), action: .openSnippet($0))
        }
        var text = query.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("/") {
            text.removeFirst(); all = folders
        } else if text.hasPrefix("#") {
            text.removeFirst(); all = snippets
        } else {
            all = folders + servers + snippets + commands.map {
                Entry(title: $0.0, detail: $0.1, symbol: $0.2, kind: String(localized: "Command"), action: $0.3)
            }
        }
        guard !text.isEmpty else { return all }
        return all.filter { $0.title.localizedCaseInsensitiveContains(text) || $0.detail.localizedCaseInsensitiveContains(text) }
    }

    var body: some View {
        let list = entries
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(String(localized: "Open anything"), text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16))
                    .focused($focused)
                    .onSubmit { choose(list) }
            }
            .padding(14)
            .background(theme.borderColor)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(Array(list.enumerated()), id: \.element.id) { index, entry in
                            HStack(spacing: 10) {
                                Image(systemName: entry.symbol).frame(width: 22).foregroundStyle(theme.accentColor)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(entry.title).lineLimit(1)
                                    if !entry.detail.isEmpty { Text(entry.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                                }
                                Spacer()
                                Text(entry.kind).font(.caption).foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(theme.cardColor, in: RoundedRectangle(cornerRadius: 4))
                            .overlay(RoundedRectangle(cornerRadius: 4)
                                .strokeBorder(index == selected ? theme.accentColor : theme.borderColor,
                                              lineWidth: index == selected ? 1.5 : 1))
                            .contentShape(Rectangle())
                            .onTapGesture { selected = index; choose(list) }
                            .id(index)
                        }
                        if list.isEmpty {
                            Text(String(localized: "Nothing matches.")).foregroundStyle(.secondary).padding(20)
                        }
                    }
                    .padding(8)
                }
                .frame(height: 320)
                .onChange(of: selected) { proxy.scrollTo(selected) }
            }
            Divider()
            HStack(spacing: 14) {
                Text(String(localized: "Hit ENTER to open up an entry and ESC to clear the search or close the window."))
                Spacer()
            }
            .font(.caption).foregroundStyle(theme.mutedColor)
            .padding(10)
            .background(theme.borderColor)
        }
        .frame(width: 620)
        .onAppear { focused = true }
        .onChange(of: query) { selected = 0 }
        .onKeyPress(.downArrow) { selected = min(selected + 1, max(list.count - 1, 0)); return .handled }
        .onKeyPress(.upArrow) { selected = max(selected - 1, 0); return .handled }
        .onKeyPress(.escape) { dismiss(); return .handled }
    }

    private func choose(_ list: [Entry]) {
        guard list.indices.contains(selected) else { return }
        let action = list[selected].action
        dismiss()
        perform(action)
    }
}
