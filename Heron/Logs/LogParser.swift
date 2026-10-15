import Foundation

/// One record from a Laravel (Monolog) log: `[time] env.LEVEL: message {context}` plus any
/// stack trace lines that follow until the next record.
struct LogEntry: Identifiable, Hashable, Sendable {
    let id: Int
    let time: String
    let environment: String
    let level: String
    /// The first line of the message, for the table.
    let summary: String
    /// Everything: message, JSON context and the stack trace.
    let body: String

    static let levels = ["EMERGENCY", "ALERT", "CRITICAL", "ERROR", "WARNING", "NOTICE", "INFO", "DEBUG"]
}

enum LogParser {
    private static let head = try! NSRegularExpression(pattern: #"^\[(\d{4}-\d{2}-\d{2}[^\]]*)\] ([\w-]+)\.([A-Z]+): ?(.*)$"#)

    /// Newest record first.
    static func parse(_ text: String) -> [LogEntry] {
        var entries: [LogEntry] = []
        var current: (time: String, env: String, level: String, lines: [String])?

        func close() {
            guard let record = current else { return }
            let body = record.lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            let first = record.lines.first ?? ""
            entries.append(LogEntry(id: entries.count, time: record.time, environment: record.env, level: record.level,
                                    summary: Self.summary(of: first), body: body))
        }

        text.enumerateLines { line, _ in
            let range = NSRange(line.startIndex..., in: line)
            if let match = head.firstMatch(in: line, range: range) {
                close()
                func group(_ i: Int) -> String { Range(match.range(at: i), in: line).map { String(line[$0]) } ?? "" }
                current = (group(1), group(2), group(3), [group(4)])
            } else if current != nil {
                current?.lines.append(line)
            }
        }
        close()
        return entries.reversed()
    }

    /// The message without its trailing JSON context, cut at a sensible length.
    static func summary(of line: String) -> String {
        var text = line
        if let brace = text.range(of: " {\"", options: .backwards), text.hasSuffix("}") || text.hasSuffix("} ") {
            text = String(text[..<brace.lowerBound])
        } else if text.hasSuffix(" []") {
            text.removeLast(3)
        }
        text = text.trimmingCharacters(in: .whitespaces)
        return text.count > 400 ? String(text.prefix(400)) + "…" : text
    }
}
