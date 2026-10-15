import AppKit

/// Colors PHP by pattern. Snippets are short, so the whole text is recolored on every change;
/// strings and comments are matched last, in one left-to-right pass, so a "//" inside a string
/// stays a string and keywords inside either don't stay colored.
enum PHPHighlighter {
    private static let keywords = """
        abstract and array as break callable case catch class clone const continue declare default do echo else \
        elseif empty enum extends final finally fn for foreach function global if implements instanceof \
        insteadof interface isset list match namespace new or print private protected public readonly \
        require require_once include include_once return static switch throw trait try unset use var while \
        yield true false null self parent
        """.split(separator: " ").map(String.init)

    /// Light: the muted editor palette common in PHP tools. Dark: brighter system colors.
    private static func tone(light: (CGFloat, CGFloat, CGFloat), dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? dark : NSColor(red: light.0, green: light.1, blue: light.2, alpha: 1)
        }
    }

    static let keyword = tone(light: (0.48, 0.23, 0.62), dark: .systemPink)
    static let className = tone(light: (0.12, 0.12, 0.14), dark: .systemTeal)
    static let member = tone(light: (0.12, 0.12, 0.14), dark: .systemBlue)
    static let variable = tone(light: (0.80, 0.25, 0.36), dark: .systemCyan)
    static let number = tone(light: (0.20, 0.55, 0.26), dark: .systemPurple)
    static let string = tone(light: (0.70, 0.22, 0.45), dark: .systemOrange)
    static let comment = tone(light: (0.55, 0.55, 0.58), dark: .secondaryLabelColor)

    private static let rules: [(NSRegularExpression, NSColor)] = [
        (regex("\\b(" + keywords.joined(separator: "|") + ")\\b", caseInsensitive: true), keyword),
        (regex("\\b[A-Z][A-Za-z0-9_]*(\\\\[A-Z][A-Za-z0-9_]*)*\\b"), className),
        (regex("(?<=->|::|\\?->)[A-Za-z_][A-Za-z0-9_]*"), member),
        (regex("\\$[A-Za-z_][A-Za-z0-9_]*"), variable),
        (regex("\\b\\d+(\\.\\d+)?\\b"), number),
    ]

    /// Group 1 is a string, group 2 a comment.
    private static let stringsAndComments = regex(
        "('(?:\\\\.|[^'\\\\])*'|\"(?:\\\\.|[^\"\\\\])*\")|(//[^\\n]*|#(?!\\[)[^\\n]*|/\\*[\\s\\S]*?\\*/)")

    private static func regex(_ pattern: String, caseInsensitive: Bool = false) -> NSRegularExpression {
        try! NSRegularExpression(pattern: pattern, options: caseInsensitive ? [.caseInsensitive] : [])
    }

    static func highlight(_ storage: NSTextStorage, font: NSFont) {
        let full = NSRange(location: 0, length: storage.length)
        storage.beginEditing()
        storage.addAttributes([.foregroundColor: NSColor.labelColor, .font: font], range: full)
        for (pattern, color) in rules {
            for match in pattern.matches(in: storage.string, range: full) {
                storage.addAttribute(.foregroundColor, value: color, range: match.range)
            }
        }
        for match in stringsAndComments.matches(in: storage.string, range: full) {
            let isString = match.range(at: 1).location != NSNotFound
            storage.addAttribute(.foregroundColor, value: isString ? string : comment, range: match.range)
        }
        storage.endEditing()
    }
}
