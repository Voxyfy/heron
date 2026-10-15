import Foundation

/// Knows the classes a snippet can name without typing a namespace: the project's own classes
/// under app/, Laravel's facades and a few everyday classes. Pressing Tab after `User` or
/// `User::` adds `use App\Models\User;` at the top of the snippet.
struct ClassCompleter {
    struct Candidate: Hashable {
        let name: String
        let fullName: String
    }

    /// Facades and helpers every Laravel app has, so they complete without a project index.
    static let laravel: [Candidate] = (
        ["DB", "Http", "Str", "Arr", "Cache", "Log", "Mail", "Route", "Auth", "Hash", "Storage", "Validator",
         "Schema", "Config", "Event", "Queue", "Bus", "Gate", "Session", "Cookie", "Redirect", "Response", "View",
         "URL", "Artisan", "Notification", "Password", "Crypt", "File", "Lang", "Date", "Process", "Pipeline"]
            .map { Candidate(name: $0, fullName: "Illuminate\\Support\\Facades\\\($0)") }
        + [Candidate(name: "Collection", fullName: "Illuminate\\Support\\Collection"),
           Candidate(name: "Carbon", fullName: "Carbon\\Carbon"),
           Candidate(name: "Model", fullName: "Illuminate\\Database\\Eloquent\\Model"),
           Candidate(name: "Builder", fullName: "Illuminate\\Database\\Eloquent\\Builder"),
           Candidate(name: "Request", fullName: "Illuminate\\Http\\Request")]
    )

    let candidates: [Candidate]

    /// Every class under `project/app`, named after its file, in the PSR-4 namespace App\.
    static func index(project: URL?) -> ClassCompleter {
        var found: [Candidate] = []
        if let project {
            // Resolved on both sides: the enumerator hands back /private/var/… for a /var/… folder.
            let app = project.appending(path: "app").resolvingSymlinksInPath()
            if let walker = FileManager.default.enumerator(at: app, includingPropertiesForKeys: [.isRegularFileKey],
                                                            options: [.skipsHiddenFiles]) {
                for case let url as URL in walker where url.pathExtension == "php" {
                    let relative = url.resolvingSymlinksInPath().deletingPathExtension().path(percentEncoded: false)
                        .dropFirst(app.path(percentEncoded: false).count)
                    let parts = relative.split(separator: "/").map(String.init)
                    guard let name = parts.last, name.first?.isUppercase == true else { continue }
                    found.append(Candidate(name: name, fullName: (["App"] + parts).joined(separator: "\\")))
                }
            }
        }
        found.sort { $0.fullName < $1.fullName }
        return ClassCompleter(candidates: found + laravel)
    }

    /// Classes whose short name starts with `prefix`; an exact short name wins and comes first.
    func matches(for prefix: String) -> [Candidate] {
        guard !prefix.isEmpty else { return [] }
        let exact = candidates.filter { $0.name == prefix }
        let partial = candidates.filter { $0.name != prefix && $0.name.lowercased().hasPrefix(prefix.lowercased()) }
        return exact + partial
    }

    /// The bare class name just before `cursor` (also before a trailing `::`), with its range.
    static func word(before cursor: Int, in text: NSString) -> (name: String, range: NSRange)? {
        var end = min(cursor, text.length)
        if end >= 2, text.substring(with: NSRange(location: end - 2, length: 2)) == "::" { end -= 2 }
        var start = end
        while start > 0 {
            let character = text.character(at: start - 1)
            let scalar = Unicode.Scalar(character).map(Character.init)
            guard let scalar, scalar.isLetter || scalar.isNumber || scalar == "_" else { break }
            start -= 1
        }
        guard start < end else { return nil }
        // A name after "\" or "$" is already qualified or a variable, not a class to import.
        if start > 0, let before = Unicode.Scalar(text.character(at: start - 1)), ["\\", "$"].contains(Character(before)) {
            return nil
        }
        let name = text.substring(with: NSRange(location: start, length: end - start))
        guard name.first?.isUppercase == true else { return nil }
        return (name, NSRange(location: start, length: end - start))
    }

    /// The snippet with `use Full\Name;` added after its last use line (or at the top), unless present.
    static func adding(use fullName: String, to code: String) -> (code: String, insertedAt: Int?) {
        var lines = code.components(separatedBy: "\n")
        let statement = "use \(fullName);"
        if lines.contains(where: { $0.trimmingCharacters(in: .whitespaces) == statement }) { return (code, nil) }
        var insertAt = 0
        if lines.first?.trimmingCharacters(in: .whitespaces) == "<?php" { insertAt = 1 }
        if let lastUse = lines.lastIndex(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("use ") }) {
            insertAt = lastUse + 1
        }
        lines.insert(statement, at: insertAt)
        // A blank line between the use block and the code reads better.
        if insertAt + 1 < lines.count, !lines[insertAt + 1].trimmingCharacters(in: .whitespaces).isEmpty,
           !lines[insertAt + 1].trimmingCharacters(in: .whitespaces).hasPrefix("use ") {
            lines.insert("", at: insertAt + 1)
        }
        let offset = lines.prefix(insertAt).reduce(0) { $0 + $1.utf16.count + 1 }
        return (lines.joined(separator: "\n"), offset)
    }
}
