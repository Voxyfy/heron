import SwiftUI

/// The row of tabs under the toolbar, one per snippet, plus a "+" for a new one.
struct TabBar: View {
    let workspace: Workspace
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 0) {
            ForEach(workspace.tabs) { tab in
                TabItem(tab: tab, isSelected: tab.id == workspace.selectedID,
                        select: { workspace.select(tab) }, close: { workspace.close(tab) })
            }
            Button { workspace.newWelcomeTab() } label: {
                Image(systemName: "plus").font(.system(size: 12)).frame(width: 36, height: 36).contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .foregroundStyle(theme.mutedColor)
            .help(String(localized: "New Tab (⌘T)"))
            Spacer(minLength: 0)
        }
        .frame(height: 36)
        .background(theme.panelColor)
    }
}

private struct TabItem: View {
    let tab: Tab
    let isSelected: Bool
    let select: () -> Void
    let close: () -> Void
    @Environment(\.theme) private var theme
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 6) {
            if tab.isRunning {
                ProgressView().controlSize(.mini)
            }
            Text(tab.title)
                .font(.system(size: 12))
                .foregroundStyle(isSelected ? theme.textColor : theme.mutedColor)
                .lineLimit(1)
            Spacer(minLength: 0)
            Button(action: close) {
                Image(systemName: "xmark").font(.system(size: 9, weight: .semibold))
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .foregroundStyle(theme.mutedColor)
            .opacity(isHovering || isSelected ? 1 : 0)
            .help(String(localized: "Close Tab (⌘W)"))
        }
        .padding(.horizontal, 12)
        .frame(width: 180, height: 36)
        .background(isSelected ? theme.backgroundColor : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture(perform: select)
        .onHover { isHovering = $0 }
    }
}
