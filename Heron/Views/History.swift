import Foundation
import Observation

struct HistoryEntry: Codable, Identifiable, Hashable {
    var id = UUID()
    var code: String
    var project: String?
    var date: Date

    var projectName: String? { project.map { ($0 as NSString).lastPathComponent } }
    /// The first line that isn't a comment or blank, for the list.
    var headline: String {
        code.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty && !$0.hasPrefix("//") && !$0.hasPrefix("#") && !$0.hasPrefix("/*") && !$0.hasPrefix("*") }
            ?? String(localized: "Empty snippet")
    }
}

/// The last 100 snippets that ran, newest first, kept in Application Support.
@MainActor @Observable
final class History {
    private(set) var entries: [HistoryEntry] = []
    private static let limit = 100

    private static var file: URL {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Heron")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appending(path: "history.json")
    }

    init() {
        if let data = try? Data(contentsOf: Self.file),
           let entries = try? JSONDecoder().decode([HistoryEntry].self, from: data) {
            self.entries = entries
        }
    }

    func add(code: String, project: URL?) {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let path = project?.path(percentEncoded: false)
        // Running the same snippet again just moves it to the top.
        entries.removeAll { $0.code == code && $0.project == path }
        entries.insert(HistoryEntry(code: code, project: path, date: .now), at: 0)
        if entries.count > Self.limit { entries.removeLast(entries.count - Self.limit) }
        save()
    }

    func remove(_ entry: HistoryEntry) {
        entries.removeAll { $0.id == entry.id }
        save()
    }

    func clear() {
        entries = []
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(entries) {
            try? data.write(to: Self.file, options: .atomic)
        }
    }
}
