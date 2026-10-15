import Foundation

/// What a run produced: echoed output, the last expression's value or the error, and timing.
/// Decoded from the JSON that runner.php writes.
struct RunResult: Decodable, Sendable {
    enum Kind: String, Decodable, Sendable { case php, composer, laravel }

    struct Failure: Decodable, Sendable, Equatable {
        let `class`: String
        let message: String
        /// Line in the snippet, when the error happened there.
        let line: Int?
        /// "bootstrap" when the project itself failed to start.
        let phase: String?
        let file: String?
    }

    struct Warning: Decodable, Sendable, Hashable {
        let message: String
        let line: Int?
    }

    /// What the snippet produced, in order: a statement's value or a database query.
    enum Item: Decodable, Sendable {
        /// A result card: a dump() call, or the last statement's value.
        case value(line: Int, DumpNode)
        /// A statement ran on this line (a mark in the gutter).
        case mark(line: Int)
        case query(sql: String, milliseconds: Double?, connection: String?)

        private enum CodingKeys: String, CodingKey { case kind, line, value, sql, milliseconds, connection }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            switch try c.decode(String.self, forKey: .kind) {
            case "query":
                self = .query(sql: try c.decode(String.self, forKey: .sql),
                              milliseconds: try c.decodeIfPresent(Double.self, forKey: .milliseconds),
                              connection: try c.decodeIfPresent(String.self, forKey: .connection))
            case "mark":
                self = .mark(line: try c.decode(Int.self, forKey: .line))
            default:
                self = .value(line: try c.decode(Int.self, forKey: .line), try c.decode(DumpNode.self, forKey: .value))
            }
        }
    }

    var kind: Kind
    var php: String
    var items: [Item]
    var framework: String?
    var value: DumpNode?
    /// The line whose value `value` is, when the last statement was an expression.
    var valueLine: Int?
    var error: Failure?
    var warnings: [Warning]
    var milliseconds: Double?
    var memory: Int?
    /// Filled in by the app, not by runner.php.
    var output = ""
    var stderr = ""

    enum CodingKeys: String, CodingKey {
        case kind, php, framework, items, value, valueLine, error, warnings, milliseconds, memory
    }
}

/// One value in the result tree.
final class DumpNode: Decodable, Sendable, Identifiable {
    struct Child: Decodable, Sendable, Identifiable {
        let key: String
        /// "public", "protected", "private" for object properties, "relation" for Eloquent relations.
        let kind: String?
        let value: DumpNode
        var id: String { key }
    }

    let type: String
    let summary: String
    let `class`: String?
    let count: Int?
    let length: Int?
    let oid: Int?
    let children: [Child]?

    var id: ObjectIdentifier { ObjectIdentifier(self) }

    /// One short line for the editor: "42", "\"Ada\"", "User {id: 1, name: …}", "Collection (3)".
    var inlineSummary: String {
        let text: String
        switch type {
        case "string": text = "\"\(summary.replacingOccurrences(of: "\n", with: "⏎"))\""
        case "object":
            let name = `class`.map { $0.split(separator: "\\").last.map(String.init) ?? $0 } ?? summary
            if let count { text = "\(name) (\(count))" }
            else if let children, !children.isEmpty {
                text = name + " {" + children.prefix(3).map { "\($0.key): \($0.value.inlineSummary)" }
                    .joined(separator: ", ") + (children.count > 3 ? ", …}" : "}")
            } else { text = name }
        case "array":
            let items = (children ?? []).prefix(4).map { $0.value.inlineSummary }.joined(separator: ", ")
            text = "[" + items + ((count ?? 0) > 4 ? ", …]" : "]")
        default: text = summary
        }
        return text.count > 90 ? String(text.prefix(89)) + "…" : text
    }
    var isContainer: Bool { children?.isEmpty == false }

    /// A list of rows with keys (a collection of models, an array of arrays): shown as a table too.
    var isTabular: Bool {
        guard let children, children.count >= 1, children.count <= 5000 else { return false }
        return children.allSatisfy { ["array", "object"].contains($0.value.type) && $0.value.isContainer }
    }

    /// Column names across all rows, in first-seen order.
    var tableColumns: [String] {
        var seen: [String] = []
        for row in children ?? [] {
            for cell in row.value.children ?? [] where !seen.contains(cell.key) { seen.append(cell.key) }
        }
        return seen
    }

    func tableRows() -> [[String: String]] {
        (children ?? []).map { row in
            Dictionary((row.value.children ?? []).map { ($0.key, $0.value.cellText) }, uniquingKeysWith: { first, _ in first })
        }
    }

    /// The value the way PHP debuggers print it: one numbered line per row, indented by depth.
    func plainLines(key: String? = nil, kind: String? = nil, inArray: Bool = false, depth: Int = 0) -> [PlainLine] {
        let prefix: String
        if let key {
            let mark = kind == "protected" ? "#" : kind == "private" ? "-" : ""
            prefix = inArray ? "\(key) => " : "\(mark)\(key): "
        } else {
            prefix = ""
        }
        switch type {
        case "object":
            let name = `class` ?? "object"
            guard let children, !children.isEmpty else { return [PlainLine(depth: depth, text: prefix + name + " {#\(oid ?? 0)}")] }
            var lines = [PlainLine(depth: depth, text: prefix + name + " {#\(oid ?? 0)")]
            for child in children {
                lines += child.value.plainLines(key: child.key, kind: child.kind, inArray: false, depth: depth + 1)
            }
            return lines + [PlainLine(depth: depth, text: "}")]
        case "array":
            guard let children, !children.isEmpty else { return [PlainLine(depth: depth, text: prefix + "[]")] }
            var lines = [PlainLine(depth: depth, text: prefix + "array:\(count ?? children.count) [")]
            for child in children {
                lines += child.value.plainLines(key: child.key, kind: nil, inArray: true, depth: depth + 1)
            }
            return lines + [PlainLine(depth: depth, text: "]")]
        case "string":
            return [PlainLine(depth: depth, text: prefix + "\"" + summary + "\"")]
        default:
            return [PlainLine(depth: depth, text: prefix + summary)]
        }
    }

    private var cellText: String {
        switch type {
        case "array": "array (\(count ?? 0))"
        case "object": shortClass ?? summary
        default: summary
        }
    }
}

struct PlainLine: Sendable {
    let depth: Int
    let text: String
}
