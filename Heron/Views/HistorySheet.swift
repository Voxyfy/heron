import SwiftUI

/// History: every snippet that ran, with a preview; open one in the current tab or a new one.
struct HistorySheet: View {
    let workspace: Workspace
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var projectFilter: String?
    @State private var selection: HistoryEntry.ID?

    private var entries: [HistoryEntry] {
        workspace.history.entries.filter { entry in
            (projectFilter == nil || entry.project == projectFilter)
                && (search.isEmpty || entry.code.localizedCaseInsensitiveContains(search))
        }
    }

    private var projects: [String] {
        Array(Set(workspace.history.entries.compactMap(\.project))).sorted {
            ($0 as NSString).lastPathComponent.localizedCaseInsensitiveCompare(($1 as NSString).lastPathComponent) == .orderedAscending
        }
    }

    private var selectedEntry: HistoryEntry? {
        entries.first { $0.id == selection } ?? entries.first
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(String(localized: "History")).font(.title3.weight(.semibold))
                Spacer()
                Picker("", selection: $projectFilter) {
                    Text(String(localized: "All Projects")).tag(String?.none)
                    ForEach(projects, id: \.self) { Text(($0 as NSString).lastPathComponent).tag(String?.some($0)) }
                }
                .labelsHidden()
                .frame(width: 180)
                TextField(String(localized: "Search"), text: $search)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)
            }
            .padding(16)
            Divider()
            HSplitView {
                List(entries, selection: $selection) { entry in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(entry.headline).font(.system(.body, design: .monospaced)).lineLimit(1)
                        HStack(spacing: 6) {
                            if let name = entry.projectName {
                                Label(name, systemImage: "folder").labelStyle(.titleAndIcon)
                            }
                            Text(entry.date, format: .dateTime.day().month().hour().minute())
                        }
                        .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                    .tag(entry.id)
                }
                .listStyle(.inset)
                .frame(minWidth: 260, idealWidth: 300)
                preview
                    .frame(minWidth: 320)
            }
            Divider()
            HStack {
                Button(String(localized: "Clear History"), role: .destructive) { workspace.history.clear() }
                    .disabled(workspace.history.entries.isEmpty)
                Spacer()
                Button(String(localized: "Close")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(String(localized: "Open in New Tab")) { open(inNewTab: true) }
                    .disabled(selectedEntry == nil)
                Button(String(localized: "Open")) { open(inNewTab: false) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(selectedEntry == nil)
            }
            .padding(16)
        }
        .frame(width: 820, height: 520)
    }

    @ViewBuilder
    private var preview: some View {
        if let entry = selectedEntry {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    if let name = entry.projectName {
                        Label(name, systemImage: "folder")
                    } else {
                        Label(String(localized: "Plain PHP"), systemImage: "terminal")
                    }
                    Spacer()
                    Text(entry.date, format: .dateTime.day().month().year().hour().minute())
                }
                .font(.callout).foregroundStyle(.secondary)
                .padding(12)
                Divider()
                ScrollView {
                    Text(entry.code)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
            }
        } else {
            Text(String(localized: "Nothing has run yet.")).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func open(inNewTab: Bool) {
        guard let entry = selectedEntry else { return }
        let project = entry.project.map { URL(filePath: $0) }
        if inNewTab {
            workspace.newTab(code: entry.code, project: project)
        } else {
            workspace.selected.code = entry.code
            workspace.setProject(project)
        }
        dismiss()
    }
}
