import Foundation
import Observation

/// One tab: a snippet, the project it runs in, and its last run. The welcome tab has no code.
@MainActor @Observable
final class Tab: Identifiable {
    let id: UUID
    let isWelcome: Bool
    var code: String
    /// The project folder the snippet runs in; nil runs plain PHP.
    var project: URL?

    private(set) var isRunning = false
    private(set) var result: RunResult?
    private(set) var failure: String?
    private(set) var notes: [LineNote] = []
    private var running: Task<Void, Never>?
    /// Bumped by every run and stop, so only the newest run may change the state.
    private var generation = 0

    init(id: UUID = UUID(), code: String = "", project: URL? = nil, isWelcome: Bool = false) {
        self.id = id
        self.code = code
        self.project = project
        self.isWelcome = isWelcome
    }

    /// True once this tab produced something to show on the result side.
    var hasRun: Bool { isRunning || result != nil || failure != nil }

    var title: String {
        if isWelcome { return String(localized: "Get started") }
        return project?.lastPathComponent ?? String(localized: "PHP")
    }

    // MARK: Running

    func run(php: URL, tidy: Bool, indent: String, finished: @escaping @MainActor (RunResult) -> Void) {
        running?.cancel()
        generation += 1
        let current = generation
        isRunning = true
        failure = nil
        notes = []
        running = Task {
            var snippet = code
            if tidy {
                let quotes = UserDefaults.standard.string(forKey: EditorSettings.quoteStyle) ?? "double"
                let tidied = await PHPRunner.format(snippet, indent: indent, quotes: quotes, php: php)
                // Only if nothing was typed meanwhile; never overwrite the user's edits.
                if code == snippet, tidied != snippet {
                    code = tidied
                    snippet = tidied
                }
            }
            do {
                let result = try await PHPRunner.run(snippet, in: project, php: php)
                guard current == generation else { return }
                self.result = result
                // Line numbers only fit the editor if the code is still what ran.
                notes = code == snippet ? Self.notes(for: result) : []
                finished(result)
            } catch {
                guard current == generation else { return }
                if !(error is CancellationError) {
                    result = nil
                    failure = error.localizedDescription
                }
            }
            isRunning = false
        }
    }

    func stop() {
        generation += 1
        running?.cancel()
        running = nil
        isRunning = false
    }

    /// Errors and warnings at their line; a gutter mark on every line that ran a statement.
    private static func notes(for result: RunResult) -> [LineNote] {
        var notes = result.warnings.compactMap { warning in
            warning.line.map { LineNote(line: $0, message: warning.message, level: .warning) }
        }
        if let error = result.error, let line = error.line {
            notes.append(LineNote(line: line, message: error.message, level: .error))
        }
        for item in result.items {
            switch item {
            case .mark(let line), .value(let line, _):
                notes.append(LineNote(line: line, message: "", level: .mark))
            case .query:
                break
            }
        }
        return notes
    }

    // MARK: Persistence

    struct Saved: Codable {
        var id: UUID
        var code: String
        var project: String?
        var isWelcome: Bool? = nil
    }

    var saved: Saved {
        Saved(id: id, code: code, project: project?.path(percentEncoded: false), isWelcome: isWelcome ? true : nil)
    }

    convenience init(saved: Saved) {
        let project = saved.project.map { URL(filePath: $0) }
            .flatMap { FileManager.default.fileExists(atPath: $0.path(percentEncoded: false)) ? $0 : nil }
        self.init(id: saved.id, code: saved.code, project: project, isWelcome: saved.isWelcome ?? false)
    }
}
