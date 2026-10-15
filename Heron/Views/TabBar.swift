import SwiftUI

/// The row of tabs under the toolbar, one per snippet, plus a "+" for a new one.
struct TabBar: View {
    let workspace: Workspace

    var body: some View {
        HStack(spacing: 0) {
            ForEach(workspace.tabs) { tab in
                TabItem(tab: tab, isSelected: tab.id == workspace.selectedID,
                        select: { workspace.select(tab) }, close: { workspace.close(tab) })
            }
            Button { workspace.newTab() } label: {
                Image(systemName: "plus").font(.system(size: 13)).frame(width: 34, height: 34).contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help(String(localized: "New Tab (⌘T)"))
            Spacer(minLength: 0)
        }
        .frame(height: 34)
        .background(Color.heronPanel)
    }
}

private struct TabItem: View {
    let tab: Tab
    let isSelected: Bool
    let select: () -> Void
    let close: () -> Void
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 6) {
            if tab.isRunning {
                ProgressView().controlSize(.mini)
            }
            Text(tab.title)
                .font(.system(size: 12.5))
                .foregroundStyle(isSelected ? .primary : .secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
            Button(action: close) {
                Image(systemName: "xmark").font(.system(size: 9, weight: .semibold))
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .opacity(isHovering || isSelected ? 1 : 0)
            .help(String(localized: "Close Tab (⌘W)"))
        }
        .padding(.horizontal, 12)
        .frame(width: 190, height: 34)
        .background(isSelected ? Color(nsColor: .textBackgroundColor) : Color.clear)
        .overlay(alignment: .trailing) { Divider().frame(height: 34) }
        .contentShape(Rectangle())
        .onTapGesture(perform: select)
        .onHover { isHovering = $0 }
    }
}
