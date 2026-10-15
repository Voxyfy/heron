import AppKit
import SwiftUI

/// A color set for the whole window: editor, results, bars and the code palette.
/// Themes decide the window's appearance (dark or light) as well.
struct Theme: Identifiable, Equatable {
    let id: String
    let name: String
    let isDark: Bool
    let background: NSColor
    let panel: NSColor
    /// Behind the result cards; a little lighter than the editor in dark themes.
    let results: NSColor
    let card: NSColor
    let border: NSColor
    let text: NSColor
    let muted: NSColor
    let currentLine: NSColor
    let keyword: NSColor
    let variable: NSColor
    let string: NSColor
    let number: NSColor
    let comment: NSColor
    let className: NSColor
    let member: NSColor
    let accent: NSColor
    let mark: NSColor

    static let key = "app.theme"
    static let defaultID = "heron-dark"

    static let heronDark = Theme(
        id: "heron-dark", name: "Heron Dark", isDark: true,
        background: NSColor(hex: 0x282A36), panel: NSColor(hex: 0x282A36), results: NSColor(hex: 0x2E303D),
        card: NSColor(hex: 0x2E303D), border: NSColor(hex: 0x44475A), text: NSColor(hex: 0xFFFFFF),
        muted: NSColor(hex: 0x858585), currentLine: NSColor(hex: 0x44475A), keyword: NSColor(hex: 0xFF79C6),
        variable: NSColor(hex: 0x74B0DF), string: NSColor(hex: 0xF1FA8C), number: NSColor(hex: 0xB5CEA7),
        comment: NSColor(hex: 0x6272A4), className: NSColor(hex: 0xFFFFFF), member: NSColor(hex: 0xFFFFFF),
        accent: NSColor(hex: 0xDB578E), mark: NSColor(hex: 0x189F6D))

    static let heronLight = Theme(
        id: "heron-light", name: "Heron Light", isDark: false,
        background: NSColor(hex: 0xFFFFFF), panel: NSColor(hex: 0xF7F7FA), results: NSColor(hex: 0xF7F7FA), card: NSColor(hex: 0xFFFFFF),
        border: NSColor(hex: 0xE3E4EA), text: NSColor(hex: 0x1F2024), muted: NSColor(hex: 0x9A9DAE),
        currentLine: NSColor(hex: 0xF0F1F5), keyword: NSColor(hex: 0x7A3CA0), variable: NSColor(hex: 0xCC3E5C),
        string: NSColor(hex: 0xB3386F), number: NSColor(hex: 0x2E8B45), comment: NSColor(hex: 0x8C8F9E),
        className: NSColor(hex: 0x1F2024), member: NSColor(hex: 0x1F2024), accent: NSColor(hex: 0x15857A),
        mark: NSColor(hex: 0x4CAF50))

    static let dracula = Theme(
        id: "dracula", name: "Dracula", isDark: true,
        background: NSColor(hex: 0x282A36), panel: NSColor(hex: 0x21222C), results: NSColor(hex: 0x21222C), card: NSColor(hex: 0x2C2E3A),
        border: NSColor(hex: 0x44475A), text: NSColor(hex: 0xF8F8F2), muted: NSColor(hex: 0x6272A4),
        currentLine: NSColor(hex: 0x343746), keyword: NSColor(hex: 0xFF79C6), variable: NSColor(hex: 0x8BE9FD),
        string: NSColor(hex: 0xF1FA8C), number: NSColor(hex: 0xBD93F9), comment: NSColor(hex: 0x6272A4),
        className: NSColor(hex: 0x50FA7B), member: NSColor(hex: 0xF8F8F2), accent: NSColor(hex: 0xBD93F9),
        mark: NSColor(hex: 0x50FA7B))

    static let nord = Theme(
        id: "nord", name: "Nord", isDark: true,
        background: NSColor(hex: 0x2E3440), panel: NSColor(hex: 0x272C36), results: NSColor(hex: 0x272C36), card: NSColor(hex: 0x3B4252),
        border: NSColor(hex: 0x434C5E), text: NSColor(hex: 0xECEFF4), muted: NSColor(hex: 0x616E88),
        currentLine: NSColor(hex: 0x3B4252), keyword: NSColor(hex: 0x81A1C1), variable: NSColor(hex: 0xD8DEE9),
        string: NSColor(hex: 0xA3BE8C), number: NSColor(hex: 0xB48EAD), comment: NSColor(hex: 0x616E88),
        className: NSColor(hex: 0x8FBCBB), member: NSColor(hex: 0x88C0D0), accent: NSColor(hex: 0x88C0D0),
        mark: NSColor(hex: 0xA3BE8C))

    static let github = Theme(
        id: "github", name: "GitHub Light", isDark: false,
        background: NSColor(hex: 0xFFFFFF), panel: NSColor(hex: 0xF6F8FA), results: NSColor(hex: 0xF6F8FA), card: NSColor(hex: 0xFFFFFF),
        border: NSColor(hex: 0xD0D7DE), text: NSColor(hex: 0x24292F), muted: NSColor(hex: 0x8C959F),
        currentLine: NSColor(hex: 0xF6F8FA), keyword: NSColor(hex: 0xCF222E), variable: NSColor(hex: 0x953800),
        string: NSColor(hex: 0x0A3069), number: NSColor(hex: 0x0550AE), comment: NSColor(hex: 0x6E7781),
        className: NSColor(hex: 0x8250DF), member: NSColor(hex: 0x24292F), accent: NSColor(hex: 0x0969DA),
        mark: NSColor(hex: 0x1A7F37))

    static let all = [heronDark, heronLight, dracula, nord, github]

    static func named(_ id: String?) -> Theme {
        all.first { $0.id == id } ?? heronDark
    }

    static var current: Theme {
        named(UserDefaults.standard.string(forKey: key))
    }

    /// Dark themes get dark controls, light themes light ones.
    func apply() {
        NSApplication.shared.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
    }
}

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

private struct ThemeKey: EnvironmentKey {
    static let defaultValue = Theme.heronDark
}

extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

extension Theme {
    var backgroundColor: Color { Color(nsColor: background) }
    var panelColor: Color { Color(nsColor: panel) }
    var resultsColor: Color { Color(nsColor: results) }
    var cardColor: Color { Color(nsColor: card) }
    var borderColor: Color { Color(nsColor: border) }
    var textColor: Color { Color(nsColor: text) }
    var mutedColor: Color { Color(nsColor: muted) }
    var accentColor: Color { Color(nsColor: accent) }
    var stringColor: Color { Color(nsColor: string) }
    var numberColor: Color { Color(nsColor: number) }
    var keywordColor: Color { Color(nsColor: keyword) }
    var classColor: Color { Color(nsColor: className) }
    var variableColor: Color { Color(nsColor: variable) }
}
