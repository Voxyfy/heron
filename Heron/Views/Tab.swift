import Foundation
import Observation

/// One tab: a snippet, the project it runs in, and its last run.
@MainActor @Observable
final class Tab: Identifiable {
    let id: UUID
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

    static let welcome = """
        // Welcome to Heron. Press ⌘R to run this snippet.
        // Choose a Laravel project from the folder icon to use its models and database.

        $numbers = collect([1, 2, 3, 4]);
        $numbers->map(fn ($n) => $n * $n)->sum()
        """

    init(id: UUID = UUID(), code: String = Tab.welcome, project: URL? = nil) {
        self.id = id
        self.code = code
        self.project = project
    }

    var title: String {
        project?.lastPathComponent ?? String(localized: "PHP")
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
                let tidied = await PHPRunner.format(snippet, indent: indent, php: php)
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

    /// Errors and warnings at their line, a gutter mark on every line that produced a value,
    /// and the last value spelled out next to its line.
    private static func notes(for result: RunResult) -> [LineNote] {
        var notes = result.warnings.compactMap { warning in
            warning.line.map { LineNote(line: $0, message: warning.message, level: .warning) }
        }
        if let error = result.error, let line = error.line {
            notes.append(LineNote(line: line, message: error.message, level: .error))
        }
        for case .value(let line, _) in result.items {
            notes.append(LineNote(line: line, message: "", level: .mark))
        }
        if result.error == nil, let line = result.valueLine, let value = result.value {
            notes.append(LineNote(line: line, message: value.inlineSummary, level: .value))
        }
        return notes
    }

    // MARK: Persistence

    struct Saved: Codable {
        var id: UUID
        var code: String
        var project: String?
    }

    var saved: Saved {
        Saved(id: id, code: code, project: project?.path(percentEncoded: false))
    }

    convenience init(saved: Saved) {
        let project = saved.project.map { URL(filePath: $0) }
            .flatMap { FileManager.default.fileExists(atPath: $0.path(percentEncoded: false)) ? $0 : nil }
        self.init(id: saved.id, code: saved.code, project: project)
    }
}
