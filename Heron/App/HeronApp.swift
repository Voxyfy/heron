import SwiftUI

@main
struct HeronApp: App {
    @State private var workspace = Workspace()

    init() {
        EditorSettings.applyAppearance(UserDefaults.standard.string(forKey: EditorSettings.appearance) ?? "light")
    }

    var body: some Scene {
        Window("Heron", id: "main") {
            MainWindow(workspace: workspace)
                .frame(minWidth: 860, minHeight: 500)
                .tint(.heron)
        }
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1280, height: 760)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button(String(localized: "New Tab")) { workspace.newTab() }
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
            }
            CommandMenu(String(localized: "Code")) {
                RunCommands(workspace: workspace)
                Divider()
                Button(String(localized: "History…")) {
                    NotificationCenter.default.post(name: .heronShowHistory, object: nil)
                }
                .keyboardShortcut("y")
            }
        }
        Settings {
            SettingsView()
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

extension Color {
    /// The teal of the heron in the app icon, darker on light backgrounds so text stays readable.
    static let heron = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.36, green: 0.80, blue: 0.74, alpha: 1)
            : NSColor(red: 0.08, green: 0.52, blue: 0.47, alpha: 1)
    })
    /// The results area behind the cards.
    static let heronPanel = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(white: 0.13, alpha: 1)
            : NSColor(red: 0.973, green: 0.973, blue: 0.984, alpha: 1)
    })
    /// Lines with a result get this mark in the gutter.
    static let heronMark = Color(nsColor: .heronMark)
}

extension NSColor {
    static let heronMark = NSColor(red: 0.30, green: 0.69, blue: 0.31, alpha: 1)
}
