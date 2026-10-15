import Sparkle
import SwiftUI

@main
struct HeronApp: App {
    @State private var workspace = Workspace()
    /// Sparkle: checks the appcast daily and offers updates; the menu item asks right away.
    /// Not started until the build carries its public key (SUPublicEDKey), or Sparkle shows an
    /// error alert on every launch.
    private let updater = SPUStandardUpdaterController(startingUpdater: HeronApp.hasUpdateKey,
                                                        updaterDelegate: nil, userDriverDelegate: nil)

    static var hasUpdateKey: Bool {
        !((Bundle.main.infoDictionary?["SUPublicEDKey"] as? String) ?? "").isEmpty
    }

    init() {
        Theme.current.apply()
    }

    var body: some Scene {
        Window("Heron", id: "main") {
            MainWindow(workspace: workspace)
                .frame(minWidth: 860, minHeight: 500)
                .tint(Theme.current.accentColor)
        }
        .windowToolbarStyle(.unifiedCompact)
        .defaultSize(width: 1280, height: 760)
        .commands {
            CommandGroup(after: .appInfo) {
                Button(String(localized: "Check for Updates…")) { updater.updater.checkForUpdates() }
                    .disabled(!Self.hasUpdateKey || !updater.updater.canCheckForUpdates)
                Button(String(localized: "License…")) {
                    NotificationCenter.default.post(name: .heronShowLicense, object: nil)
                }
            }
            CommandGroup(replacing: .newItem) {
                Button(String(localized: "New Tab")) { workspace.newWelcomeTab() }
                    .keyboardShortcut("t")
                Button(String(localized: "Choose Project…")) { workspace.chooseProject() }
                    .keyboardShortcut("o")
            }
            CommandGroup(replacing: .saveItem) {
                Button(String(localized: "Close Tab")) {
                    if workspace.tabs.count > 1 {
                        workspace.close(workspace.selected)
                    } else {
                        NSApp.keyWindow?.performClose(nil)
                    }
                }
                .keyboardShortcut("w")
                Button(String(localized: "Save as Snippet…")) {
                    NotificationCenter.default.post(name: .heronSaveSnippet, object: nil)
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
            }
            CommandMenu(String(localized: "Code")) {
                RunCommands(workspace: workspace)
                Divider()
                Button(String(localized: "Open Anything…")) {
                    NotificationCenter.default.post(name: .heronShowPalette, object: nil)
                }
                .keyboardShortcut("p")
                Button(String(localized: "History…")) {
                    NotificationCenter.default.post(name: .heronShowHistory, object: nil)
                }
                .keyboardShortcut("y")
                Button(String(localized: "Snippets…")) {
                    NotificationCenter.default.post(name: .heronShowSnippets, object: nil)
                }
                .keyboardShortcut("b")
                Button(String(localized: "Logs…")) {
                    NotificationCenter.default.post(name: .heronShowLogs, object: nil)
                }
                .keyboardShortcut("l")
                Button(String(localized: "Remote Connections…")) {
                    NotificationCenter.default.post(name: .heronShowConnections, object: nil)
                }
                .keyboardShortcut("k", modifiers: [.command, .shift])
            }
        }
        Settings {
            // The Settings scene is separate from the window; the license pane reads this.
            SettingsView().environment(workspace.license)
        }
    }
}

/// Code ▸ Run (⌘R) and Stop (⌘.), so the shortcuts work wherever the focus is.
private struct RunCommands: View {
    let workspace: Workspace
    @AppStorage(EditorSettings.formatsOnRun) private var formatsOnRun = true
    @AppStorage(EditorSettings.indentWidth) private var indentWidth = 4
    @AppStorage(EditorSettings.usesTabs) private var usesTabs = false

    var body: some View {
        Button(String(localized: "Run")) {
            workspace.run(tidy: formatsOnRun, indent: EditorSettings.indentUnit(tabs: usesTabs, width: indentWidth))
        }
        .keyboardShortcut("r")
        Button(String(localized: "Stop")) { workspace.stop() }
            .keyboardShortcut(".")
            .disabled(!workspace.selected.isRunning)
    }
}
