import SwiftUI

/// Logs: the project's storage/logs files as a table, newest record first, with level filter,
/// search (⌘F), pages and a live refresh; the chosen record's full text below.
struct LogsSheet: View {
    let workspace: Workspace
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme
    @State private var files: [String] = []
    @State private var file: String?
    @State private var entries: [LogEntry] = []
    @State private var levels: Set<String> = Set(LogEntry.levels)
    @State private var search = ""
    @State private var page = 0
    @State private var selection: LogEntry.ID?
    @State private var refresh = 0
    @State private var failure: String?
    @State private var loading = false
    @FocusState private var searchFocused: Bool

    private let pageSize = 100
    private let intervals: [(Int, String)] = [
        (0, String(localized: "Manual")), (1, String(localized: "1 second")), (5, String(localized: "5 seconds")), (30, String(localized: "30 seconds")),
    ]

    private var source: LogSource? {
        let tab = workspace.selected
        if let connection = workspace.connection(of: tab) {
            guard let credential = connection.credential else { return nil }
            return .remote(connection, credential)
        }
        return tab.project.map(LogSource.local)
    }

    private var filtered: [LogEntry] {
        entries.filter { levels.contains($0.level) && (search.isEmpty || $0.body.localizedCaseInsensitiveContains(search)) }
    }

    private var pageCount: Int { max(1, (filtered.count + pageSize - 1) / pageSize) }
    private var pageEntries: ArraySlice<LogEntry> {
        let all = filtered
        let start = min(page * pageSize, all.count)
        return all[start..<min(start + pageSize, all.count)]
    }
    private var selected: LogEntry? { entries.first { $0.id == selection } }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(String(localized: "Logs")).font(.title3.weight(.semibold))
                Spacer()
                if let source { Text(source.folderDescription).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            }
            .padding(16)
            Divider()
            toolbar
            Divider()
            VSplitView {
                table.frame(minHeight: 180)
                detail.frame(minHeight: 120)
            }
            Divider()
            HStack {
                Text(String(localized: "Page \(page + 1) / \(pageCount)")).foregroundStyle(.secondary)
                if let failure { Text(failure).foregroundStyle(.red).lineLimit(1) }
                Spacer()
                Button(String(localized: "Previous")) { page -= 1 }.disabled(page == 0)
                Button(String(localized: "Next")) { page += 1 }.disabled(page + 1 >= pageCount)
                Button(String(localized: "Close")) { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(16)
        }
        .frame(width: 1100, height: 720)
        .task { await loadFiles() }
        .task(id: refresh) { await load() }
        .task(id: file) { page = 0; await load() }
        .onChange(of: levels) { page = 0 }
        .onChange(of: search) { page = 0 }
        .background {
            Button("") { searchFocused = true }.keyboardShortcut("f").hidden()
            Button("") { Task { await load() } }.keyboardShortcut("r").hidden()
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Picker("", selection: $file) {
                if files.isEmpty { Text(String(localized: "No log files")).tag(String?.none) }
                ForEach(files, id: \.self) { Text($0).tag(String?.some($0)) }
            }
            .labelsHidden().frame(width: 240)
            Menu {
                ForEach(LogEntry.levels, id: \.self) { level in
                    Toggle(level, isOn: Binding(get: { levels.contains(level) },
                                                set: { if $0 { levels.insert(level) } else { levels.remove(level) } }))
                }
                Divider()
                Button(String(localized: "All levels")) { levels = Set(LogEntry.levels) }
                Button(String(localized: "Errors only")) { levels = ["EMERGENCY", "ALERT", "CRITICAL", "ERROR"] }
            } label: {
                Text(String(localized: "Levels (\(levels.count))"))
            }
            .frame(width: 130)
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(String(localized: "Press ⌘F to focus search"), text: $search).textFieldStyle(.plain).focused($searchFocused)
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(theme.backgroundColor, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(theme.borderColor))
            Picker("", selection: $refresh) {
                ForEach(intervals, id: \.0) { Text($0.1).tag($0.0) }
            }
            .labelsHidden().frame(width: 120)
            .help(String(localized: "Reload the file this often"))
            Button { Task { await load() } } label: { Image(systemName: "arrow.clockwise") }
                .help(String(localized: "Reload (⌘R)"))
            if loading { ProgressView().controlSize(.small) }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    private var table: some View {
        Table(Array(pageEntries), selection: $selection) {
            TableColumn(String(localized: "LEVEL")) { entry in
                Text(entry.level).foregroundStyle(Self.color(for: entry.level)).fontWeight(.medium)
            }
            .width(min: 80, ideal: 90, max: 110)
            TableColumn(String(localized: "TIME")) { entry in Text(entry.time).foregroundStyle(.secondary) }
                .width(min: 150, ideal: 170, max: 220)
            TableColumn(String(localized: "DESCRIPTION")) { entry in Text(entry.summary).lineLimit(1) }
        }
        .font(.system(size: 12.5, design: .monospaced))
        .overlay {
            if entries.isEmpty, !loading {
                Text(source == nil ? String(localized: "Open a project or connect to a server to see its logs.")
                                   : String(localized: "No records in this file."))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var detail: some View {
        ScrollView {
            if let selected {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        Text(selected.level).fontWeight(.semibold).foregroundStyle(Self.color(for: selected.level))
                        Text(selected.time).foregroundStyle(.secondary)
                        Text(selected.environment).foregroundStyle(.tertiary)
                    }
                    .font(.system(size: 12, design: .monospaced))
                    Text(selected.body)
                        .font(.system(size: 12.5, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(16)
            } else {
                Text(String(localized: "Choose a record to read it in full.")).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 100)
            }
        }
        .background(theme.backgroundColor)
    }

    private static func color(for level: String) -> Color {
        switch level {
        case "EMERGENCY", "ALERT", "CRITICAL", "ERROR": .red
        case "WARNING": .orange
        case "NOTICE", "INFO": .blue
        default: .secondary
        }
    }

    private func loadFiles() async {
        guard let source else {
            if workspace.connection(of: workspace.selected) != nil {
                failure = String(localized: "No password or key is saved for this server.")
            }
            return
        }
        do {
            files = try await source.files()
            if file == nil || !files.contains(file!) { file = files.first }
            failure = nil
        } catch {
            failure = error.localizedDescription
        }
    }

    /// Reads the chosen file now, and keeps re-reading at the chosen interval until cancelled.
    private func load() async {
        repeat {
            guard let source, let file else { return }
            loading = true
            do {
                let text = try await source.read(file)
                let parsed = LogParser.parse(text)
                if parsed != entries {
                    entries = parsed
                    if selection == nil { selection = parsed.first?.id }
                }
                failure = nil
            } catch {
                failure = error.localizedDescription
            }
            loading = false
            guard refresh > 0 else { return }
            try? await Task.sleep(for: .seconds(refresh))
        } while !Task.isCancelled
    }
}
