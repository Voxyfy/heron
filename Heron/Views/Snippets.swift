import Foundation
import Observation

/// A saved piece of code. App snippets live in Application Support; project snippets are
/// plain .php files in the project's .heron/snippets folder, so a team can share them in git.
struct Snippet: Codable, Identifiable, Hashable {
    var id = UUID()
    var title: String
    var description = ""
    var code: String
    /// The project this snippet belongs to (its folder path), or nil for "any project".
    var project: String?
    /// True when read from a project's .heron/snippets folder.
    var isProjectFile = false

    var projectName: String? { project.map { ($0 as NSString).lastPathComponent } }

    enum CodingKeys: String, CodingKey { case id, title, description, code, project }
}

@MainActor @Observable
final class SnippetStore {
    private(set) var appSnippets: [Snippet] = []

    private static var file: URL {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Heron")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appending(path: "snippets.json")
    }

    init() {
        if let data = try? Data(contentsOf: Self.file),
           let snippets = try? JSONDecoder().decode([Snippet].self, from: data) {
            appSnippets = snippets
        }
    }

    /// App snippets plus the files in `project`'s .heron/snippets folder.
    func all(for project: URL?) -> [Snippet] {
        appSnippets + projectSnippets(in: project)
    }

    func projectSnippets(in project: URL?) -> [Snippet] {
        guard let folder = Self.folder(in: project),
              let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false)) else {
            return []
        }
        return names.filter { $0.hasSuffix(".php") }.sorted().compactMap { name in
            let url = folder.appending(path: name)
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            var lines = text.components(separatedBy: "\n")
            if lines.first?.trimmingCharacters(in: .whitespaces) == "<?php" { lines.removeFirst() }
            // "// about: Sends the welcome mail" on the first line is the description.
            var description = ""
            if let first = lines.first?.trimmingCharacters(in: .whitespaces), first.hasPrefix("// about:") {
                description = first.dropFirst("// about:".count).trimmingCharacters(in: .whitespaces)
                lines.removeFirst()
            }
            return Snippet(id: UUID(uuidString: Self.stableID(for: url)) ?? UUID(),
                           title: String(name.dropLast(4)), description: description,
                           code: lines.joined(separator: "\n").trimmingCharacters(in: .newlines),
                           project: project?.path(percentEncoded: false), isProjectFile: true)
        }
    }

    static func folder(in project: URL?) -> URL? {
        project?.appending(path: ".heron/snippets")
    }

    func save(_ snippet: Snippet) {
        if snippet.isProjectFile {
            saveProjectFile(snippet)
            return
        }
        if let index = appSnippets.firstIndex(where: { $0.id == snippet.id }) {
            appSnippets[index] = snippet
        } else {
            appSnippets.insert(snippet, at: 0)
        }
        persist()
    }

    func remove(_ snippet: Snippet) {
        if snippet.isProjectFile, let project = snippet.project.map({ URL(filePath: $0) }),
           let folder = Self.folder(in: project) {
            try? FileManager.default.removeItem(at: folder.appending(path: snippet.title + ".php"))
            return
        }
        appSnippets.removeAll { $0.id == snippet.id }
        persist()
    }

    private func saveProjectFile(_ snippet: Snippet) {
        guard let project = snippet.project.map({ URL(filePath: $0) }), let folder = Self.folder(in: project) else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var text = "<?php\n"
        if !snippet.description.isEmpty { text += "// about: \(snippet.description)\n" }
        text += snippet.code + "\n"
        let safeTitle = snippet.title.replacingOccurrences(of: "/", with: "-")
        try? text.write(to: folder.appending(path: safeTitle + ".php"), atomically: true, encoding: .utf8)
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(appSnippets) {
            try? data.write(to: Self.file, options: .atomic)
        }
    }

    /// The same file gets the same id across launches, so list selection survives a reload.
    private static func stableID(for url: URL) -> String {
        var hash: UInt64 = 1469598103934665603
        for byte in url.path(percentEncoded: false).utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1099511628211
        }
        let hex = String(format: "%016llx", hash) + String(format: "%016llx", hash &* 31)
        let h = Array(hex)
        return "\(String(h[0..<8]))-\(String(h[8..<12]))-4\(String(h[13..<16]))-a\(String(h[17..<20]))-\(String(h[20..<32]))"
    }
}
