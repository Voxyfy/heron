import SwiftUI

/// The result side: one card per thing the run produced, in the order it happened.
struct ResultPanel: View {
    let tab: Tab
    let failure: String?
    @AppStorage("result.showsQueries") private var showsQueries = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
        }
        .background(Color.heronPanel)
        .overlay(alignment: .top) {
            if tab.isRunning { ProgressView().progressViewStyle(.linear).tint(.heron) }
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
            ForEach(Array(result.items.enumerated()), id: \.offset) { _, item in
                switch item {
                case .value(let line, let node):
                    Card(title: "", line: line) {
                        DumpNodeView(key: nil, kind: nil, node: node, startsOpen: true)
                    }
                case .query(let sql, let ms, _):
                    if showsQueries {
                        Card(title: ms.map { "SQL · " + ($0 < 1 ? "<1 ms" : String(format: "%.1f ms", $0)) } ?? "SQL",
                             tint: .purple) {
                            Text(sql).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
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
            .padding(.top, 80)
        }
    }
}

/// One result: a small title, the line it came from, and the content.
struct Card<Content: View>: View {
    let title: String
    var line: Int?
    var tint: Color = .heron
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !title.isEmpty {
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(tint)
            }
            content
        }
        .padding(.vertical, 12)
        .padding(.leading, 14)
        .padding(.trailing, 72)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .topTrailing) {
            if let line {
                Text(String(localized: "Line \(line)")).font(.caption).foregroundStyle(.secondary).padding(12)
            }
        }
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.1)))
        .overlay(alignment: .leading) {
            if tint != .heron {
                UnevenRoundedRectangle(topLeadingRadius: 6, bottomLeadingRadius: 6).fill(tint).frame(width: 3)
            }
        }
    }
}

/// One value: a line for scalars, an expandable group for arrays and objects.
struct DumpNodeView: View {
    let key: String?
    let kind: String?
    let node: DumpNode
    var startsOpen = false
    @State private var isOpen: Bool?

    var body: some View {
        if let children = node.children, !children.isEmpty {
            DisclosureGroup(isExpanded: Binding(get: { isOpen ?? startsOpen }, set: { isOpen = $0 })) {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(children.enumerated()), id: \.offset) { _, child in
                        DumpNodeView(key: child.key, kind: child.kind, node: child.value)
                    }
                }
                .padding(.leading, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                line
            }
        } else {
            line.padding(.leading, key == nil ? 0 : 18)
        }
    }

    private var line: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if let key {
                Text(kindPrefix + key).foregroundStyle(.secondary)
                Text("→").foregroundStyle(.tertiary)
            }
            Text(display).foregroundStyle(color).textSelection(.enabled)
                .lineLimit(node.type == "string" ? 8 : 1)
        }
        .font(.system(.body, design: .monospaced))
    }

    private var kindPrefix: String {
        switch kind {
        case "protected": "#"
        case "private": "-"
        case "relation": "↳ "
        default: ""
        }
    }

    private var display: String {
        switch node.type {
        case "string": "\"\(node.summary)\""
        case "object": node.shortClass.map { name in node.count.map { "\(name) (\($0))" } ?? name } ?? node.summary
        default: node.summary
        }
    }

    private var color: Color {
        switch node.type {
        case "string": .orange
        case "int", "float": .purple
        case "bool", "null": .pink
        case "object", "closure": .teal
        default: .primary
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
