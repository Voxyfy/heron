import SwiftUI

/// The "Get started" tab: a big greeting, three ways to begin as cards, and recent folders.
struct WelcomeView: View {
    let workspace: Workspace
    @Environment(\.theme) private var theme
    @State private var hovering: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 36) {
                HStack(alignment: .center, spacing: 20) {
                    Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 84, height: 84)
                        .shadow(color: .black.opacity(theme.isDark ? 0.5 : 0.2), radius: 16, y: 8)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(String(localized: "Hi there!")).font(.system(size: 34, weight: .bold))
                        Text(String(localized: "Pick a project, write a few lines of PHP, press ⌘R."))
                            .font(.system(size: 15)).foregroundStyle(theme.mutedColor)
                    }
                }
                HStack(spacing: 16) {
                    StartCard(icon: "lucide.square-terminal", title: String(localized: "Plain PHP"),
                              detail: String(localized: "A scratchpad with no project, just the PHP on your Mac."),
                              shortcut: nil) { workspace.newTab(project: nil, keepProject: false) }
                    StartCard(icon: "lucide.folder-open", title: String(localized: "Open a project"),
                              detail: String(localized: "Laravel and plain PHP projects. Models, config and the database come along."),
                              shortcut: "⌘O") { workspace.chooseProject(forNewTab: true) }
                    StartCard(icon: "lucide.bookmark", title: String(localized: "Snippets"),
                              detail: String(localized: "Code you saved earlier, for any project or this one."),
                              shortcut: "⌘B") { NotificationCenter.default.post(name: .heronShowSnippets, object: nil) }
                }
                if !workspace.recentProjects.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(String(localized: "Recent folders")).font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(theme.mutedColor).textCase(.uppercase)
                        VStack(spacing: 0) {
                            ForEach(Array(workspace.recentProjects.enumerated()), id: \.element) { index, url in
                                RecentRow(url: url, isLast: index == workspace.recentProjects.count - 1) {
                                    workspace.newTab(project: url, keepProject: false)
                                }
                            }
                        }
                        .background(theme.cardColor, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(theme.borderColor))
                    }
                }
                HStack(spacing: 18) {
                    hint("⌘P", String(localized: "Open anything"))
                    hint("⌘Y", String(localized: "History"))
                    hint("⌘T", String(localized: "New tab"))
                    hint("⌘,", String(localized: "Settings"))
                }
                .foregroundStyle(theme.mutedColor)
            }
            .frame(maxWidth: 820, alignment: .leading)
            .padding(.horizontal, 48)
            .padding(.vertical, 44)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(theme.backgroundColor)
    }

    private func hint(_ keys: String, _ text: String) -> some View {
        HStack(spacing: 6) {
            Text(keys).font(.system(size: 11, weight: .semibold, design: .rounded))
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(theme.cardColor, in: RoundedRectangle(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(theme.borderColor))
            Text(text).font(.system(size: 12))
        }
    }
}

/// One way to begin: an icon, a title, a sentence, the whole card clickable.
private struct StartCard: View {
    let icon: String
    let title: String
    let detail: String
    let shortcut: String?
    let action: () -> Void
    @Environment(\.theme) private var theme
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(icon).renderingMode(.template).resizable().aspectRatio(contentMode: .fit)
                        .frame(width: 24, height: 24).foregroundStyle(theme.accentColor)
                    Spacer()
                    if let shortcut {
                        Text(shortcut).font(.system(size: 11, weight: .medium, design: .rounded)).foregroundStyle(theme.mutedColor)
                    }
                }
                Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(theme.textColor)
                Text(detail).font(.system(size: 12.5)).foregroundStyle(theme.mutedColor)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(18)
            .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
            .background(theme.cardColor, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(hovering ? theme.accentColor : theme.borderColor,
                                                                        lineWidth: hovering ? 1.5 : 1))
            .scaleEffect(hovering ? 1.015 : 1)
            .animation(.easeOut(duration: 0.15), value: hovering)
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

private struct RecentRow: View {
    let url: URL
    let isLast: Bool
    let action: () -> Void
    @Environment(\.theme) private var theme
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image("lucide.folder-open").renderingMode(.template).resizable().aspectRatio(contentMode: .fit)
                    .frame(width: 16, height: 16).foregroundStyle(theme.mutedColor)
                Text(url.lastPathComponent).foregroundStyle(theme.textColor)
                Spacer()
                Text((url.path(percentEncoded: false) as NSString).abbreviatingWithTildeInPath)
                    .font(.system(size: 11.5)).foregroundStyle(theme.mutedColor).lineLimit(1)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(hovering ? theme.accentColor.opacity(0.12) : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .overlay(alignment: .bottom) {
            if !isLast { Rectangle().fill(theme.borderColor).frame(height: 1).padding(.leading, 44) }
        }
    }
}
