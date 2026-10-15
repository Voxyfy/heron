import SwiftUI

/// The result side: one card per thing the run produced, in the order it happened.
/// With "plain output" on, the same values print as numbered lines instead.
struct ResultPanel: View {
    let tab: Tab
    let failure: String?
    @AppStorage("result.showsQueries") private var showsQueries = false
    @AppStorage("result.plain") private var plain = false
    @AppStorage(EditorSettings.fontName) private var fontName = EditorSettings.systemFont
    @AppStorage(EditorSettings.fontSize) private var fontSize = 15.0
    @Environment(\.theme) private var theme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .environment(\.dumpFont, Font(EditorSettings.font(name: fontName, size: fontSize)))
        .background(theme.resultsColor)
        .overlay(alignment: .top) {
            if tab.isRunning { ProgressView().progressViewStyle(.linear).tint(theme.accentColor) }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let failure = failure ?? tab.failure {
            Card(title: String(localized: "Couldn't run"), tint: .red) {
                Text(failure).textSelection(.enabled)
            }
        } else if let result = tab.result {
            if let error = result.error {
                Card(title: error.class, line: error.line, tint: .red) {
                    VStack(alignment: .leading, spacing: 4) {
                        if error.phase == "bootstrap" {
                            Text(String(localized: "The project couldn't start.")).fontWeight(.semibold)
                        }
                        Text(error.message).textSelection(.enabled)
                        if let file = error.file {
                            Text(file).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                    }
                }
            }
            ForEach(Array(result.warnings.enumerated()), id: \.offset) { _, warning in
                Card(title: String(localized: "Warning"), line: warning.line, tint: .orange) {
                    Text(warning.message).textSelection(.enabled)
                }
            }
            if !result.output.isEmpty {
                Card(title: String(localized: "Output")) {
                    Text(result.output.trimmingCharacters(in: .newlines))
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
            if plain {
                PlainOutput(result: result, showsQueries: showsQueries)
            } else {
                ForEach(Array(result.items.enumerated()), id: \.offset) { _, item in
                    switch item {
                    case .value(let line, let node):
                        Card(title: "", line: line, table: node.isTabular ? node : nil) {
                            DumpNodeView(key: nil, kind: nil, node: node, startsOpen: true)
                        }
                    case .mark:
                        EmptyView()
                    case .query(let sql, let ms, _):
                        if showsQueries {
                            Card(title: ms.map { "SQL · " + ($0 < 1 ? "<1 ms" : String(format: "%.1f ms", $0)) } ?? "SQL",
                                 tint: .purple) {
                                Text(sql).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                            }
                        }
                    }
                }
            }
            if !result.stderr.isEmpty {
                Card(title: String(localized: "PHP said"), tint: .secondary) {
                    Text(result.stderr).font(.system(.callout, design: .monospaced)).foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            if result.items.isEmpty, result.output.isEmpty, result.error == nil {
                Text(String(localized: "The snippet ran and produced no value.")).foregroundStyle(.secondary).padding(4)
            }
        } else if !tab.isRunning {
            VStack(spacing: 8) {
                Image(systemName: "play.circle").font(.system(size: 34)).foregroundStyle(.tertiary)
                Text(String(localized: "Press ⌘R to run the snippet.")).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 60)
        }
    }
}

/// Plain output: every value as numbered text lines, queries as "select …" lines.
private struct PlainOutput: View {
    let result: RunResult
    let showsQueries: Bool
    @Environment(\.theme) private var theme
    @Environment(\.dumpFont) private var font

    private var lines: [PlainLine] {
        var all: [PlainLine] = []
        for item in result.items {
            switch item {
            case .value(_, let node): all += node.plainLines()
            case .mark: break
            case .query(let sql, _, _): if showsQueries { all.append(PlainLine(depth: 0, text: sql)) }
            }
        }
        return all
    }

    var body: some View {
        let lines = self.lines
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .trailing, spacing: 0) {
                ForEach(lines.indices, id: \.self) { Text("\($0 + 1)").foregroundStyle(theme.mutedColor) }
            }
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    Text(line.text).foregroundStyle(theme.textColor)
                        .padding(.leading, CGFloat(line.depth) * 18)
                        .textSelection(.enabled)
                }
            }
            Spacer(minLength: 0)
        }
        .font(font)
        .lineSpacing(8)
    }
}

/// One result: a small title, the line it came from, a table button for lists of rows, and the content.
struct Card<Content: View>: View {
    let title: String
    var line: Int?
    var tint: Color? = nil
    var table: DumpNode? = nil
    @ViewBuilder let content: Content
    @Environment(\.theme) private var theme
    @Environment(\.openTable) private var openTable

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !title.isEmpty {
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(tint ?? theme.accentColor)
            }
            content
        }
        .padding(.vertical, 14)
        .padding(.leading, 16)
        .padding(.trailing, 76)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .topTrailing) {
            VStack(alignment: .trailing, spacing: 10) {
                if let line {
                    Text(String(localized: "Line \(line)")).font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(theme.mutedColor)
                }
                if let table {
                    Button { openTable.open(table) } label: {
                        Image(systemName: "tablecells").font(.system(size: 13))
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(theme.textColor)
                    .help(String(localized: "Show as table"))
                }
            }
            .padding(12)
        }
        .background(theme.cardColor, in: RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(theme.borderColor))
        .overlay(alignment: .leading) {
            if let tint {
                UnevenRoundedRectangle(topLeadingRadius: 4, bottomLeadingRadius: 4).fill(tint).frame(width: 3)
            }
        }
    }
}

private struct DumpFontKey: EnvironmentKey {
    static let defaultValue = Font.system(.body, design: .monospaced)
}

extension EnvironmentValues {
    var dumpFont: Font {
        get { self[DumpFontKey.self] }
        set { self[DumpFontKey.self] = newValue }
    }
}

/// One value, printed like a PHP debugger: `Class {#12 ▾`, `key: value` for properties,
/// `0 => value` for array entries, each group closing with `}` or `]`.
struct DumpNodeView: View {
    let key: String?
    let kind: String?
    let node: DumpNode
    var inArray = false
    var startsOpen = false
    var depth = 0
    @State private var isOpen: Bool?
    @Environment(\.theme) private var theme
    @Environment(\.dumpFont) private var font

    /// Groups open down to the third level unless they are long; the rest opens on click.
    private var open: Bool { isOpen ?? (startsOpen || (depth <= 2 && (node.count ?? children.count) <= 60)) }
    private var children: [DumpNode.Child] { node.children ?? [] }
    private var isGroup: Bool { !children.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                keyLabel
                header
                if isGroup {
                    Button { isOpen = !open } label: {
                        Image(systemName: open ? "arrowtriangle.down.fill" : "arrowtriangle.right.fill")
                            .font(.system(size: 7))
                            .foregroundStyle(theme.mutedColor)
                            .frame(width: 18, height: 14)
                            .background(theme.borderColor.opacity(0.5), in: Circle())
                            .padding(.leading, 6)
                    }
                    .buttonStyle(.plain)
                }
            }
            if isGroup, open {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(children.enumerated()), id: \.offset) { _, child in
                        DumpNodeView(key: child.key, kind: child.kind, node: child.value, inArray: node.type == "array",
                                     depth: depth + 1)
                    }
                }
                .padding(.leading, 14)
                .overlay(alignment: .leading) { Rectangle().fill(theme.borderColor.opacity(0.6)).frame(width: 1).padding(.leading, 2) }
                Text(node.type == "array" ? "]" : "}").foregroundStyle(theme.textColor)
            }
        }
        .font(font)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var keyLabel: some View {
        if let key {
            let mark = kind == "protected" ? "#" : kind == "private" ? "-" : kind == "relation" ? "↳ " : ""
            if inArray {
                Text("\(key) => ").foregroundStyle(theme.textColor)
            } else {
                Text("\(mark)\(key): ").foregroundStyle(theme.variableColor)
            }
        }
    }

    @ViewBuilder
    private var header: some View {
        switch node.type {
        case "object":
            HStack(spacing: 0) {
                Text(node.class ?? "object").foregroundStyle(theme.textColor)
                if isGroup || node.oid != nil {
                    Text(verbatim: " {#" + String(node.oid ?? 0)).foregroundStyle(theme.mutedColor)
                }
                if !isGroup { Text("}").foregroundStyle(theme.mutedColor) }
                if let count = node.count { Text(verbatim: " (" + String(count) + ")").foregroundStyle(theme.mutedColor) }
            }
        case "array":
            Text(verbatim: isGroup ? "array:" + String(node.count ?? children.count) + " [" : "[]").foregroundStyle(theme.textColor)
        case "string":
            Text("\"\(node.summary)\"").foregroundStyle(theme.stringColor).textSelection(.enabled).lineLimit(8)
        case "int", "float":
            Text(node.summary).foregroundStyle(theme.numberColor).textSelection(.enabled)
        case "bool", "null":
            Text(node.summary).foregroundStyle(theme.keywordColor).textSelection(.enabled)
        case "error":
            Text(node.summary).foregroundStyle(.red).textSelection(.enabled)
        default:
            Text(node.summary).foregroundStyle(theme.textColor).textSelection(.enabled)
        }
    }
}

extension DumpNode {
    var shortClass: String? {
        `class`.map { $0.split(separator: "\\").last.map(String.init) ?? $0 }
    }

    /// The card title: "User", "Collection (3)", "array (2)", "string", "int"…
    var typeLabel: String {
        switch type {
        case "object": shortClass.map { name in count.map { "\(name) (\($0))" } ?? name } ?? "object"
        case "array": "array (\(count ?? 0))"
        default: type
        }
    }
}
