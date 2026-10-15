import AppKit
import SwiftUI

/// A list of rows (a collection of models, an array of arrays) as a searchable grid, with CSV export.
struct TablePreview: View {
    let node: DumpNode
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    private var columns: [String] { Array(node.tableColumns.prefix(40)) }
    private var rows: [[String: String]] {
        let all = node.tableRows()
        guard !search.isEmpty else { return all }
        return all.filter { row in row.values.contains { $0.localizedCaseInsensitiveContains(search) } }
    }

    var body: some View {
        let rows = self.rows
        VStack(spacing: 0) {
            HStack {
                Text(String(localized: "Table Preview")).font(.title3.weight(.semibold))
                Spacer()
                TextField(String(localized: "Search…"), text: $search).textFieldStyle(.roundedBorder).frame(width: 220)
                Text(String(localized: "\(rows.count) entries")).foregroundStyle(.secondary)
                Button(String(localized: "Export CSV")) { export(rows) }
            }
            .padding(14)
            Divider()
            Table(Array(rows.enumerated()).map { Row(index: $0.offset, cells: $0.element) }) {
                TableColumnForEach(columns, id: \.self) { column in
                    TableColumn(column) { row in
                        Text(row.cells[column] ?? "").lineLimit(1).textSelection(.enabled)
                    }
                }
            }
            Divider()
            HStack {
                Spacer()
                Button(String(localized: "Close")) { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(12)
        }
        .frame(width: 900, height: 560)
    }

    private struct Row: Identifiable {
        let index: Int
        let cells: [String: String]
        var id: Int { index }
    }

    private func export(_ rows: [[String: String]]) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "export.csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        func cell(_ text: String) -> String { "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        var csv = columns.map(cell).joined(separator: ",") + "\n"
        for row in rows { csv += columns.map { cell(row[$0] ?? "") }.joined(separator: ",") + "\n" }
        try? csv.write(to: url, atomically: true, encoding: .utf8)
    }
}
