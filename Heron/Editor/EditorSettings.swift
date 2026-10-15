import AppKit
import SwiftUI

/// Preference keys shared by the editor, the formatter and the Settings window.
enum EditorSettings {
    static let fontName = "editor.fontName"
    static let fontSize = "editor.fontSize"
    static let indentWidth = "editor.indentWidth"
    static let usesTabs = "editor.usesTabs"
    static let wrapsLines = "editor.wrapsLines"
    static let formatsOnRun = "editor.formatsOnRun"
    /// "double", "single" or "keep": how tidying writes plain strings.
    static let quoteStyle = "editor.quoteStyle"

    /// Empty means the system's monospaced font (SF Mono).
    static let systemFont = ""

    static func font(name: String, size: Double) -> NSFont {
        if !name.isEmpty, let font = NSFont(name: name, size: size) { return font }
        return .monospacedSystemFont(ofSize: size, weight: .regular)
    }

    /// Fixed-width fonts installed on this Mac, for the font menu.
    static var monospacedFonts: [String] {
        let families = NSFontManager.shared.availableFontNames(with: .fixedPitchFontMask) ?? []
        return families
            .filter { !$0.hasPrefix(".") && !$0.lowercased().contains("italic") && !$0.lowercased().contains("bold") }
            .sorted()
    }

    /// One level of indentation: a tab, or the chosen number of spaces.
    static func indentUnit(tabs: Bool, width: Int) -> String {
        tabs ? "\t" : String(repeating: " ", count: width)
    }
}

/// Settings: a sidebar of sections, like most developer tools.
struct SettingsView: View {
    enum Section: String, CaseIterable, Identifiable {
        case general, editor, appearance, about
        var id: Self { self }
        var title: String {
            switch self {
            case .general: String(localized: "General")
            case .editor: String(localized: "Editor")
            case .appearance: String(localized: "Appearance")
            case .about: String(localized: "About")
            }
        }
        var symbol: String {
            switch self {
            case .general: "gearshape"
            case .editor: "text.alignleft"
            case .appearance: "paintpalette"
            case .about: "info.circle"
            }
        }
    }

    @State private var section = Section.general

    var body: some View {
        HStack(spacing: 0) {
            #if DEBUG
            // `-heron.settingsSection editor` opens that pane, for screenshots.
            Color.clear.frame(width: 0, height: 0).onAppear {
                if let name = UserDefaults.standard.string(forKey: "heron.settingsSection"), let wanted = Section(rawValue: name) {
                    section = wanted
                }
            }
            #endif
            List(Section.allCases, selection: $section) { item in
                Label(item.title, systemImage: item.symbol).tag(item)
            }
            .listStyle(.sidebar)
            .frame(width: 170)
            Divider()
            ScrollView {
                Group {
                    switch section {
                    case .general: GeneralSettings()
                    case .editor: EditorSettingsPane()
                    case .appearance: AppearanceSettings()
                    case .about: AboutPane()
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: 780, height: 480)
    }
}

/// A titled row with an explanation on the left and the control on the right.
private struct SettingRow<Content: View>: View {
    let title: String
    var detail: String?
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).fontWeight(.medium)
                if let detail { Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            }
            .frame(width: 180, alignment: .leading)
            content.frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 10)
    }
}

private struct GeneralSettings: View {
    @AppStorage(PHPBinary.customKey) private var phpPath = ""
    @AppStorage(Workspace.welcomeKey) private var welcome = true
    @AppStorage(EditorSettings.formatsOnRun) private var formatsOnRun = true
    @AppStorage(EditorSettings.quoteStyle) private var quoteStyle = "double"
    @State private var version: String?

    private var effective: URL? { PHPBinary.find() }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(String(localized: "General")).font(.title2.weight(.semibold)).padding(.bottom, 12)
            SettingRow(title: String(localized: "PHP Binary"),
                       detail: String(localized: "Leave empty to use Laravel Herd or Homebrew's PHP automatically.")) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        TextField("", text: $phpPath, prompt: Text(effective?.path(percentEncoded: false) ?? "/opt/homebrew/bin/php"))
                            .textFieldStyle(.roundedBorder)
                        Button(String(localized: "Choose…")) { choose() }
                    }
                    Text(version.map { "PHP \($0)" } ?? String(localized: "No PHP found"))
                        .font(.caption).foregroundStyle(version == nil ? .red : .secondary)
                }
            }
            Divider()
            SettingRow(title: String(localized: "Tidy code when running"),
                       detail: String(localized: "⌘R first fixes indentation and spacing, like a formatter.")) {
                Toggle("", isOn: $formatsOnRun).labelsHidden()
            }
            Divider()
            SettingRow(title: String(localized: "Quotes when tidying"),
                       detail: String(localized: "Plain strings are rewritten with this quote; strings with variables or escapes stay as they are.")) {
                Picker("", selection: $quoteStyle) {
                    Text(String(localized: "Double \"…\"")).tag("double")
                    Text(String(localized: "Single '…'")).tag("single")
                    Text(String(localized: "Leave as written")).tag("keep")
                }
                .labelsHidden()
                .frame(width: 180)
            }
            Divider()
            SettingRow(title: String(localized: "Welcome Tab"),
                       detail: String(localized: "Show the Get started tab when Heron opens.")) {
                Toggle("", isOn: $welcome).labelsHidden()
            }
        }
        .onAppear(perform: check)
        .onChange(of: phpPath) { check() }
    }

    private func check() {
        version = effective.flatMap(PHPRunner.version(of:))
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.showsHiddenFiles = true
        panel.message = String(localized: "Choose the php executable to run snippets with.")
        if panel.runModal() == .OK, let url = panel.url { phpPath = url.path(percentEncoded: false) }
    }
}

private struct EditorSettingsPane: View {
    @AppStorage(EditorSettings.fontName) private var fontName = EditorSettings.systemFont
    @AppStorage(EditorSettings.fontSize) private var fontSize = 15.0
    @AppStorage(EditorSettings.indentWidth) private var indentWidth = 4
    @AppStorage(EditorSettings.usesTabs) private var usesTabs = false
    @AppStorage(EditorSettings.wrapsLines) private var wrapsLines = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(String(localized: "Editor")).font(.title2.weight(.semibold)).padding(.bottom, 12)
            SettingRow(title: String(localized: "Font")) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        Picker("", selection: $fontName) {
                            Text(String(localized: "System (SF Mono)")).tag(EditorSettings.systemFont)
                            Divider()
                            ForEach(EditorSettings.monospacedFonts, id: \.self) { name in
                                Text(NSFont(name: name, size: 13)?.displayName ?? name).tag(name)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 200)
                        Stepper(value: $fontSize, in: 9...32, step: 1) {
                            Text("\(Int(fontSize)) pt").monospacedDigit().frame(width: 40, alignment: .trailing)
                        }
                        .fixedSize()
                    }
                    Text("User::where('active', true)->count()")
                        .font(Font(EditorSettings.font(name: fontName, size: min(fontSize, 15))))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            SettingRow(title: String(localized: "Indentation")) {
                HStack {
                    Picker("", selection: $usesTabs) {
                        Text(String(localized: "Spaces")).tag(false)
                        Text(String(localized: "Tabs")).tag(true)
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 140)
                    Picker("", selection: $indentWidth) {
                        ForEach([2, 4, 8], id: \.self) { Text(String(localized: "\($0) spaces")).tag($0) }
                    }
                    .labelsHidden().frame(width: 100).disabled(usesTabs)
                }
            }
            Divider()
            SettingRow(title: String(localized: "Wrap long lines")) {
                Toggle("", isOn: $wrapsLines).labelsHidden()
            }
        }
    }
}

private struct AppearanceSettings: View {
    @AppStorage(Theme.key) private var themeID = Theme.defaultID

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "Appearance")).font(.title2.weight(.semibold))
            Text(String(localized: "Themes color the editor, the results and the window.")).foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 16) {
                VStack(spacing: 4) {
                    ForEach(Theme.all) { theme in
                        Button {
                            themeID = theme.id
                            theme.apply()
                        } label: {
                            HStack {
                                Circle().fill(Color(nsColor: theme.accent)).frame(width: 10, height: 10)
                                Text(theme.name)
                                Spacer()
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(theme.id == themeID ? Color.accentColor.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 6))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(width: 180)
                ThemePreview(theme: Theme.named(themeID))
            }
        }
    }
}

/// A few lines of PHP in the theme's colors.
private struct ThemePreview: View {
    let theme: Theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                ForEach([Color.red, .yellow, .green], id: \.self) { Circle().fill($0.opacity(0.8)).frame(width: 9, height: 9) }
                Spacer()
            }
            .padding(10)
            .background(theme.panelColor)
            VStack(alignment: .leading, spacing: 5) {
                line(1, [("function ", theme.keywordColor), ("greet", theme.textColor), ("(", theme.textColor), ("string ", theme.keywordColor), ("$name", theme.variableColor), (") {", theme.textColor)])
                line(2, [("    $hello", theme.variableColor), (" = ", theme.textColor), ("\"Hello, $name!\"", theme.stringColor), (";", theme.textColor)])
                line(3, [("    return ", theme.keywordColor), ("$hello", theme.variableColor), (";", theme.textColor)])
                line(4, [("}", theme.textColor)])
                line(5, [])
                line(6, [("greet", theme.textColor), ("(", theme.textColor), ("'Heron'", theme.stringColor), (") ", theme.textColor), ("// 42", Color(nsColor: theme.comment)), (" ", theme.textColor), ("42", theme.numberColor)])
            }
            .font(.system(size: 12, design: .monospaced))
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.backgroundColor)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(theme.borderColor))
    }

    private func line(_ number: Int, _ parts: [(String, Color)]) -> some View {
        HStack(spacing: 0) {
            Text("\(number)").foregroundStyle(theme.mutedColor).frame(width: 22, alignment: .trailing).padding(.trailing, 12)
            ForEach(Array(parts.enumerated()), id: \.offset) { _, part in Text(part.0).foregroundStyle(part.1) }
            Spacer()
        }
    }
}

private struct AboutPane: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Heron").font(.title2.weight(.semibold))
                    Text(String(localized: "Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""))"))
                        .foregroundStyle(.secondary)
                }
            }
            Text(String(localized: "A PHP and Laravel scratchpad for macOS, by Voxyfy."))
            Text("© 2026 Batuhan Haymana").foregroundStyle(.secondary)
        }
    }
}
