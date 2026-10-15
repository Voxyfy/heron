import Foundation

/// One entry in the completion list.
struct CompletionItem: Hashable {
    enum Kind: String { case `class`, method, `static`, property, column, relation, scope, function, variable, word }

    struct Parameter: Hashable {
        let name: String
        let optional: Bool
    }

    let label: String
    /// What goes into the text when chosen; a method with parameters ends in "(".
    let insert: String
    let kind: Kind
    let detail: String
    /// A class to import with a `use` line when chosen.
    let use: String?
    /// The class this member hands back, so a chain like `User::first()->` can go on.
    let returns: String?
    /// A callable's parameters, in order; the required ones become placeholders when chosen.
    var params: [Parameter] = []

    /// What goes into the text: `where($column, $operator, $value)` for a callable with required
    /// parameters, with the ranges of those placeholders relative to the start.
    func expansion() -> (text: String, placeholders: [NSRange]) {
        let required = params.filter { !$0.optional }
        guard insert.hasSuffix("(") else { return (insert, []) }
        if required.isEmpty {
            // Only optional parameters: "name()" with the caret between the parentheses.
            return (insert + ")", [NSRange(location: insert.utf16.count, length: 0)])
        }
        var text = insert
        var ranges: [NSRange] = []
        for (index, parameter) in required.enumerated() {
            if index > 0 { text += ", " }
            let placeholder = "$" + parameter.name
            ranges.append(NSRange(location: text.utf16.count, length: placeholder.utf16.count))
            text += placeholder
        }
        text += ")"
        return (text, ranges)
    }
}

/// Everything Heron can suggest while typing: class names from the project index, members of a
/// class resolved through `->` and `::` chains (asked from PHP by reflection, cached), PHP and
/// framework functions, and the snippet's own variables.
@MainActor
final class CompletionEngine {
    private(set) var project: URL?
    private var classes: ClassCompleter
    private var members: [String: [CompletionItem]] = [:]
    private var functionList: [CompletionItem]?
    private var loading = Set<String>()
    /// Called when data that was missing has arrived, so the list can be shown after all.
    var onDataArrived: (() -> Void)?

    init(project: URL?) {
        self.project = project
        classes = ClassCompleter.index(project: project)
    }

    func setProject(_ project: URL?) {
        guard project != self.project else { return }
        self.project = project
        classes = ClassCompleter.index(project: project)
        members = [:]
        functionList = nil
        loading = []
    }

    /// The list for the caret position, and the range of text it would replace.
    func suggestions(in text: NSString, cursor: Int) -> (range: NSRange, items: [CompletionItem])? {
        let (prefix, prefixRange) = Self.identifier(before: cursor, in: text)
        let beforePrefix = prefixRange.location
        // `->` or `::` right before the word being typed: members of whatever stands before the arrow.
        if beforePrefix >= 2 {
            let op = text.substring(with: NSRange(location: beforePrefix - 2, length: 2))
            if op == "->" || op == "::" {
                guard let receiver = Self.receiver(endingAt: beforePrefix - 2, in: text),
                      let type = resolve(receiver, in: text, before: beforePrefix - 2, depth: 0) else { return nil }
                guard let all = members(of: type) else { return nil }   // being fetched
                let wantsStatic = op == "::"
                let items = all.filter { item in
                    switch item.kind {
                    case .static, .scope: true
                    case .method: !wantsStatic
                    case .property, .column, .relation: !wantsStatic
                    default: false
                    }
                }
                // What people reach for first: a model's columns and relations, then its own methods.
                let priority: [CompletionItem.Kind: Int] = wantsStatic
                    ? [.scope: 0, .static: 1]
                    : [.column: 0, .relation: 1, .property: 2, .scope: 3, .method: 4, .static: 5]
                let ordered = items.enumerated().sorted {
                    (priority[$0.element.kind] ?? 9, $0.offset) < (priority[$1.element.kind] ?? 9, $1.offset)
                }.map(\.element)
                let known = Set(ordered.map(\.label))
                let words = Self.words(in: text, excluding: prefixRange).filter { !known.contains($0) }
                    .map { CompletionItem(label: $0, insert: $0, kind: .word, detail: "", use: nil, returns: nil) }
                return (prefixRange, Self.ranked(ordered + words, prefix: prefix))
            }
        }
        guard prefix.count >= 1 else { return nil }
        if prefix.hasPrefix("$") {
            let names = Self.variables(in: text, excluding: prefixRange)
            let items = names.map { CompletionItem(label: $0, insert: $0, kind: .variable, detail: "", use: nil, returns: nil) }
            return (prefixRange, Self.ranked(items, prefix: prefix))
        }
        if prefix.first!.isUppercase {
            let items = classes.matches(for: prefix).map {
                CompletionItem(label: $0.name, insert: $0.name, kind: .class, detail: $0.fullName, use: $0.fullName, returns: $0.fullName)
            }
            return items.isEmpty ? nil : (prefixRange, items)
        }
        guard prefix.count >= 2 else { return nil }
        let functions = functions() ?? []
        let names = Self.variables(in: text, excluding: prefixRange).filter { $0.dropFirst().lowercased().hasPrefix(prefix.lowercased()) }
        let variableItems = names.map { CompletionItem(label: $0, insert: $0, kind: .variable, detail: "", use: nil, returns: nil) }
        let known = Set(functions.map(\.label))
        let words = Self.words(in: text, excluding: prefixRange).filter { !known.contains($0) }
            .map { CompletionItem(label: $0, insert: $0, kind: .word, detail: "", use: nil, returns: nil) }
        let items = Self.ranked(functions + words, prefix: prefix)
        return items.isEmpty && variableItems.isEmpty ? nil : (prefixRange, Array((variableItems + items).prefix(200)))
    }

    // MARK: Data from PHP

    private func members(of className: String) -> [CompletionItem]? {
        if let known = members[className] { return known }
        fetch(key: "members:" + className, arguments: ["members", className]) { [weak self] items in
            self?.members[className] = items
        }
        return nil
    }

    private func functions() -> [CompletionItem]? {
        if let functionList { return functionList }
        fetch(key: "functions", arguments: ["functions"]) { [weak self] items in
            self?.functionList = items
        }
        return nil
    }

    private func fetch(key: String, arguments: [String], store: @escaping @MainActor ([CompletionItem]) -> Void) {
        guard !loading.contains(key), let php = PHPBinary.find(),
              let script = Bundle.main.url(forResource: "complete", withExtension: "php") else { return }
        loading.insert(key)
        let root = project?.path(percentEncoded: false) ?? ""
        Task.detached { [weak self] in
            let items = Self.run(php: php, script: script, arguments: [root] + arguments)
            await MainActor.run {
                guard let self else { return }
                self.loading.remove(key)
                store(items)
                self.onDataArrived?()
            }
        }
    }

    private nonisolated static func run(php: URL, script: URL, arguments: [String]) -> [CompletionItem] {
        let process = Process()
        process.executableURL = php
        process.arguments = [script.path(percentEncoded: false)] + arguments
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return [] }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return rows.compactMap { row in
            guard let label = row["label"] as? String else { return nil }
            let kind = CompletionItem.Kind(rawValue: row["kind"] as? String ?? "method") ?? .method
            let params = (row["params"] as? [[String: Any]] ?? []).compactMap { parameter -> CompletionItem.Parameter? in
                guard let name = parameter["name"] as? String else { return nil }
                return CompletionItem.Parameter(name: name, optional: parameter["optional"] as? Bool ?? false)
            }
            return CompletionItem(label: label, insert: row["insert"] as? String ?? label, kind: kind,
                                  detail: row["detail"] as? String ?? "", use: nil, returns: row["returns"] as? String,
                                  params: params)
        }
    }

    // MARK: Reading the snippet

    /// The identifier (or `$variable`) being typed just before the caret.
    static func identifier(before cursor: Int, in text: NSString) -> (String, NSRange) {
        var start = min(cursor, text.length)
        while start > 0 {
            let c = text.character(at: start - 1)
            let isWord = (c >= 48 && c <= 57) || (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 95 || c > 127
            if isWord { start -= 1 } else if c == 36 { start -= 1; break } else { break }
        }
        return (text.substring(with: NSRange(location: start, length: cursor - start)), NSRange(location: start, length: cursor - start))
    }

    /// The expression that ends right before an arrow: `$user`, `User`, `new User(...)`,
    /// `collect(...)`, or a chain of those joined by `->` and `::`.
    static func receiver(endingAt end: Int, in text: NSString) -> String? {
        var i = end
        var depth = 0
        while i > 0 {
            let c = text.character(at: i - 1)
            if c == 41 { depth += 1 }                              // )
            else if c == 40 { if depth == 0 { break }; depth -= 1 } // (
            else if depth == 0 {
                let isWord = (c >= 48 && c <= 57) || (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 95 || c == 36 || c == 92
                let isArrow = c == 62 || c == 58 || c == 45  // > : -
                if !isWord && !isArrow {
                    // "new User" keeps its "new"; a space elsewhere ends the expression.
                    if c == 32 || c == 10 || c == 9 {
                        let before = text.substring(with: NSRange(location: 0, length: i - 1))
                        if before.hasSuffix("new") { i -= 4; continue }
                    }
                    break
                }
            }
            i -= 1
        }
        let expression = text.substring(with: NSRange(location: i, length: end - i)).trimmingCharacters(in: .whitespacesAndNewlines)
        return expression.isEmpty ? nil : expression
    }

    /// The class an expression is: follows `$var = …` assignments and `->method()` chains.
    func resolve(_ expression: String, in text: NSString, before limit: Int, depth: Int) -> String? {
        guard depth < 6 else { return nil }
        var expression = expression.trimmingCharacters(in: .whitespaces)
        if expression.hasPrefix("new ") {
            expression = String(expression.dropFirst(4))
        }
        // Split "head->a()->b()" into head + segments, respecting parentheses.
        var segments: [(op: String, name: String)] = []
        var head = expression
        var parenDepth = 0
        var cut: String.Index? = nil
        var i = expression.startIndex
        var lastOp: String.Index? = nil
        while i < expression.endIndex {
            let c = expression[i]
            if c == "(" { parenDepth += 1 } else if c == ")" { parenDepth -= 1 }
            if parenDepth == 0 {
                let rest = expression[i...]
                if rest.hasPrefix("->") || rest.hasPrefix("::") {
                    if cut == nil { cut = i }
                    if let lastOp { segments.append(Self.segment(expression[lastOp..<i])) }
                    lastOp = i
                    i = expression.index(i, offsetBy: 2)
                    continue
                }
            }
            i = expression.index(after: i)
        }
        if let lastOp { segments.append(Self.segment(expression[lastOp...])) }
        if let cut { head = String(expression[..<cut]) }
        guard var type = resolveHead(head, in: text, before: limit, depth: depth) else { return nil }
        // The model a query started from: `User::where()->first()` gives a User, `->get()` Users.
        var model: String? = type.hasSuffix("Builder") || type.hasSuffix("Collection") ? nil : type
        for segment in segments {
            guard let items = members(of: type), let item = items.first(where: { $0.label == segment.name }),
                  let next = item.returns else { return nil }
            if next == "@model" {
                guard let model else { return nil }
                type = model
            } else {
                type = next
                if !next.hasSuffix("Builder") && !next.hasSuffix("Collection") && !next.hasSuffix("Relation") { model = next }
            }
        }
        return type
    }

    private static func segment(_ part: Substring) -> (op: String, name: String) {
        let op = String(part.prefix(2))
        let rest = part.dropFirst(2)
        let name = String(rest.prefix { $0.isLetter || $0.isNumber || $0 == "_" })
        return (op, name)
    }

    private func resolveHead(_ head: String, in text: NSString, before limit: Int, depth: Int) -> String? {
        let head = head.trimmingCharacters(in: .whitespaces)
        if head.hasPrefix("$") {
            return variableType(head, in: text, before: limit, depth: depth)
        }
        if head.hasPrefix("\\") { return String(head.dropFirst()) }
        if let first = head.first, first.isUppercase {
            let name = String(head.prefix { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "\\" })
            return className(name, in: text)
        }
        // A function call: what it returns, if the function list knows.
        let name = String(head.prefix { $0.isLetter || $0.isNumber || $0 == "_" })
        return functions()?.first { $0.label == name }?.returns
    }

    /// The full name for a short class name: from the snippet's `use` lines, else the project index.
    private func className(_ name: String, in text: NSString) -> String? {
        if name.contains("\\") { return name }
        if let imported = ClassCompleter.imports(in: text as String)[name] { return imported }
        return classes.matches(for: name).first { $0.name == name }?.fullName
    }

    /// The type of `$var`: its last assignment above, a typed parameter, or a foreach over a model list.
    private func variableType(_ variable: String, in text: NSString, before limit: Int, depth: Int) -> String? {
        let code = text.substring(to: min(limit, text.length))
        let escaped = NSRegularExpression.escapedPattern(for: variable)
        if let assignment = try? NSRegularExpression(pattern: "(?m)^\\s*\(escaped)\\s*=\\s*([^;]+);") {
            let matches = assignment.matches(in: code, range: NSRange(location: 0, length: code.utf16.count))
            if let last = matches.last, let range = Range(last.range(at: 1), in: code) {
                return resolve(String(code[range]), in: text, before: last.range.location, depth: depth + 1)
            }
        }
        if let parameter = try? NSRegularExpression(pattern: "([A-Z][A-Za-z0-9_\\\\]*)\\s+\(escaped)\\b"),
           let match = parameter.firstMatch(in: code, range: NSRange(location: 0, length: code.utf16.count)),
           let range = Range(match.range(at: 1), in: code) {
            return className(String(code[range]), in: text)
        }
        if let loop = try? NSRegularExpression(pattern: "foreach\\s*\\(([^)]+?)\\s+as\\s+(?:\\$\\w+\\s*=>\\s*)?\(escaped)\\s*\\)"),
           let match = loop.firstMatch(in: code, range: NSRange(location: 0, length: code.utf16.count)),
           let range = Range(match.range(at: 1), in: code) {
            // Looping over a query result: the items are the model.
            let source = String(code[range])
            if let collection = resolve(source, in: text, before: match.range.location, depth: depth + 1),
               collection.hasSuffix("Collection") {
                return Self.modelBehind(source, in: text, engine: self, before: match.range.location, depth: depth + 1)
            }
        }
        return nil
    }

    /// For `User::where(...)->get()`, the model is the head of the chain.
    private static func modelBehind(_ expression: String, in text: NSString, engine: CompletionEngine, before: Int, depth: Int) -> String? {
        let head = String(expression.prefix { $0 != "-" && $0 != ":" }).trimmingCharacters(in: .whitespaces)
        guard let first = head.first, first.isUppercase else { return nil }
        return engine.resolveHead(head, in: text, before: before, depth: depth)
    }

    /// Identifiers of three letters or more in the snippet, except the one being typed: the plain
    /// word completion every editor has, for names the index doesn't know.
    static func words(in text: NSString, excluding: NSRange) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: "[A-Za-z_][A-Za-z0-9_]{2,}") else { return [] }
        var seen: [String] = []
        for match in regex.matches(in: text as String, range: NSRange(location: 0, length: text.length))
        where match.range != excluding && NSIntersectionRange(match.range, excluding).length == 0 {
            let word = text.substring(with: match.range)
            if !seen.contains(word) { seen.append(word) }
        }
        return seen
    }

    /// Every `$name` in the snippet except the one being typed, most recent first.
    static func variables(in text: NSString, excluding: NSRange) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: "\\$[A-Za-z_][A-Za-z0-9_]*") else { return [] }
        var seen: [String] = []
        for match in regex.matches(in: text as String, range: NSRange(location: 0, length: text.length)).reversed()
        where match.range != excluding {
            let name = text.substring(with: match.range)
            if !seen.contains(name) && name != "$this" { seen.append(name) }
        }
        return seen
    }

    /// Prefix matches first (shortest first), then contains; at most 200, the panel scrolls.
    static func ranked(_ items: [CompletionItem], prefix: String) -> [CompletionItem] {
        guard !prefix.isEmpty else { return Array(items.prefix(200)) }
        let lower = prefix.lowercased()
        // Shortest names first among the ones that start with the prefix: "where" before "whereKey".
        let starts = items.filter { $0.label.lowercased().hasPrefix(lower) }
            .sorted { ($0.label.count, $0.label.lowercased()) < ($1.label.count, $1.label.lowercased()) }
        let contains = items.filter { !$0.label.lowercased().hasPrefix(lower) && $0.label.lowercased().contains(lower) }
        return Array((starts + contains).prefix(200))
    }
}

extension ClassCompleter {
    /// `use App\Models\User;` and `use Foo\Bar as Baz;` lines of the snippet: short name → full name.
    static func imports(in code: String) -> [String: String] {
        var map: [String: String] = [:]
        guard let regex = try? NSRegularExpression(pattern: "(?m)^\\s*use\\s+([A-Za-z0-9_\\\\]+)(?:\\s+as\\s+([A-Za-z0-9_]+))?\\s*;") else { return map }
        for match in regex.matches(in: code, range: NSRange(location: 0, length: code.utf16.count)) {
            guard let fullRange = Range(match.range(at: 1), in: code) else { continue }
            let full = String(code[fullRange])
            let alias = Range(match.range(at: 2), in: code).map { String(code[$0]) }
            map[alias ?? String(full.split(separator: "\\").last ?? Substring(full))] = full
        }
        return map
    }
}
