import SwiftUI

/// Snippets: saved code, for every project or for one. Open one in the current tab (⏎)
/// or in a new one (⌘⏎); edit it on the right.
struct SnippetsSheet: View {
    let workspace: Workspace
    /// Code to save as a new snippet, when opened from "Save as Snippet".
    var newCode: String?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme
    @State private var scope = Scope.all
    @State private var search = ""
    @State private var selection: Snippet.ID?
    @State private var draft: Snippet?

    enum Scope: Hashable { case all, project }

    private var snippets: [Snippet] {
        workspace.snippets.all(for: workspace.selected.project).filter { snippet in
            (scope == .all || snippet.project == workspace.selected.project?.path(percentEncoded: false))
                && (search.isEmpty || snippet.title.localizedCaseInsensitiveContains(search)
                    || snippet.code.localizedCaseInsensitiveContains(search))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(String(localized: "Snippets")).font(.title3.weight(.semibold))
                Spacer()
                Button(String(localized: "New Snippet")) { startNew(code: workspace.selected.code) }
            }
            .padding(16)
            Divider()
            HSplitView {
                VStack(spacing: 10) {
                    HStack {
                        Picker("", selection: $scope) {
                            Text(String(localized: "All")).tag(Scope.all)
                            Text(workspace.selected.project?.lastPathComponent ?? String(localized: "Project")).tag(Scope.project)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .disabled(workspace.selected.project == nil)
                        TextField(String(localized: "Search"), text: $search).textFieldStyle(.roundedBorder)
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
                    List(snippets, selection: $selection) { snippet in
                        HStack {
                            Text(snippet.title).font(.system(.body, design: .monospaced)).lineLimit(1)
                            Spacer()
                            if let name = snippet.projectName {
                                Label(name, systemImage: snippet.isProjectFile ? "folder" : "folder.badge.gearshape")
                                    .font(.caption).foregroundStyle(.secondary).labelStyle(.titleAndIcon)
                            }
                        }
                        .tag(snippet.id)
                    }
                    .listStyle(.inset)
                }
                .frame(minWidth: 280, idealWidth: 320)
                editor.frame(minWidth: 380)
            }
            Divider()
            HStack {
                if let draft, draft.isProjectFile || draft.project != nil {
                    Text(String(localized: "Stored in the project's .heron/snippets folder")).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(String(localized: "Close")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(String(localized: "Open in New Tab")) { open(inNewTab: true) }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(draft == nil)
                Button(String(localized: "Open")) { open(inNewTab: false) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(draft == nil)
            }
            .padding(16)
        }
        .frame(width: 900, height: 560)
        .onAppear {
            if let newCode { startNew(code: newCode) } else { selection = snippets.first?.id }
        }
        .onChange(of: selection) {
            if let snippet = snippets.first(where: { $0.id == selection }) { draft = snippet }
        }
    }

    @ViewBuilder
    private var editor: some View {
        if let binding = Binding($draft) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    TextField(String(localized: "Title"), text: binding.title).textFieldStyle(.roundedBorder)
                    Picker("", selection: binding.project) {
                        Text(String(localized: "Any project")).tag(String?.none)
                        if let project = workspace.selected.project {
                            Text(project.lastPathComponent).tag(String?.some(project.path(percentEncoded: false)))
                        }
                    }
                    .labelsHidden()
                    .frame(width: 160)
                    .disabled(binding.wrappedValue.isProjectFile)
                }
                TextField(String(localized: "Description"), text: binding.description).textFieldStyle(.roundedBorder)
                TextEditor(text: binding.code)
                    .font(.system(size: 12.5, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(theme.backgroundColor, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(theme.borderColor))
                HStack {
                    Button(String(localized: "Delete"), role: .destructive) {
                        workspace.snippets.remove(binding.wrappedValue)
                        draft = nil
                        selection = nil
                    }
                    .disabled(!exists(binding.wrappedValue))
                    Spacer()
                    Button(String(localized: "Save Snippet")) {
                        var snippet = binding.wrappedValue
                        snippet.title = snippet.title.trimmingCharacters(in: .whitespaces)
                        if snippet.title.isEmpty { snippet.title = String(localized: "Untitled") }
                        // A project snippet is a file in that project.
                        snippet.isProjectFile = snippet.project != nil
                        workspace.snippets.save(snippet)
                        draft = snippet
                        selection = snippet.id
                    }
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(binding.wrappedValue.code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(12)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "bookmark").font(.system(size: 30)).foregroundStyle(.tertiary)
                Text(String(localized: "Choose a snippet, or save the current code as one.")).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func exists(_ snippet: Snippet) -> Bool {
        workspace.snippets.all(for: workspace.selected.project).contains { $0.id == snippet.id }
    }

    private func startNew(code: String) {
        selection = nil
        draft = Snippet(title: "", code: code, project: nil)
    }

    private func open(inNewTab: Bool) {
        guard let draft else { return }
        let project = draft.project.map { URL(filePath: $0) } ?? workspace.selected.project
        if inNewTab {
            workspace.newTab(code: draft.code, project: project)
        } else {
            workspace.selected.code = draft.code
            if draft.project != nil { workspace.setProject(project) }
        }
        dismiss()
    }
}
