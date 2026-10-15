import AppKit
import SwiftUI

/// Editor preferences, shared by the editor, the formatter and the Settings window.
enum EditorSettings {
    static let fontName = "editor.fontName"
    static let fontSize = "editor.fontSize"
    static let indentWidth = "editor.indentWidth"
    static let usesTabs = "editor.usesTabs"
    static let wrapsLines = "editor.wrapsLines"
    static let formatsOnRun = "editor.formatsOnRun"
    /// "light" (the default, like most PHP tools), "dark" or "system".
    static let appearance = "app.appearance"

    static func applyAppearance(_ value: String) {
        switch value {
        case "dark": NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
        case "system": NSApplication.shared.appearance = nil
        default: NSApplication.shared.appearance = NSAppearance(named: .aqua)
        }
    }

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

/// Settings ▸ Editor.
struct SettingsView: View {
    @AppStorage(EditorSettings.fontName) private var fontName = EditorSettings.systemFont
    @AppStorage(EditorSettings.fontSize) private var fontSize = 13.0
    @AppStorage(EditorSettings.indentWidth) private var indentWidth = 4
    @AppStorage(EditorSettings.usesTabs) private var usesTabs = false
    @AppStorage(EditorSettings.wrapsLines) private var wrapsLines = true
    @AppStorage(EditorSettings.formatsOnRun) private var formatsOnRun = true
    @AppStorage(EditorSettings.appearance) private var appearance = "light"

    var body: some View {
        Form {
            Section(String(localized: "Appearance")) {
                Picker(String(localized: "Theme"), selection: $appearance) {
                    Text(String(localized: "Light")).tag("light")
                    Text(String(localized: "Dark")).tag("dark")
                    Text(String(localized: "Match System")).tag("system")
                }
                .pickerStyle(.segmented)
                .onChange(of: appearance) { EditorSettings.applyAppearance(appearance) }
            }
            Section(String(localized: "Font")) {
                Picker(String(localized: "Font"), selection: $fontName) {
                    Text(String(localized: "System (SF Mono)")).tag(EditorSettings.systemFont)
                    Divider()
                    ForEach(EditorSettings.monospacedFonts, id: \.self) { name in
                        Text(NSFont(name: name, size: 13)?.displayName ?? name).tag(name)
                    }
                }
                Stepper(value: $fontSize, in: 9...32, step: 1) {
                    LabeledContent(String(localized: "Size"), value: "\(Int(fontSize)) pt")
                }
                Text("User::where('active', true)->count()")
                    .font(Font(EditorSettings.font(name: fontName, size: fontSize)))
                    .foregroundStyle(.secondary)
            }
            Section(String(localized: "Indentation")) {
                Picker(String(localized: "Indent with"), selection: $usesTabs) {
                    Text(String(localized: "Spaces")).tag(false)
                    Text(String(localized: "Tabs")).tag(true)
                }
                .pickerStyle(.segmented)
                Picker(String(localized: "Indent width"), selection: $indentWidth) {
                    ForEach([2, 4, 8], id: \.self) { Text(String(localized: "\($0) spaces")).tag($0) }
                }
                .disabled(usesTabs)
            }
            Section(String(localized: "Behavior")) {
                Toggle(String(localized: "Tidy code when running (⌘R)"), isOn: $formatsOnRun)
                Toggle(String(localized: "Wrap long lines"), isOn: $wrapsLines)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
    }
}
