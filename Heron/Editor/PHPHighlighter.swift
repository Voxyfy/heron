import AppKit

/// Colors PHP by pattern, with the theme's palette. Snippets are short, so the whole text is
/// recolored on every change; strings and comments are matched last, in one left-to-right pass,
/// so a "//" inside a string stays a string and keywords inside either don't stay colored.
enum PHPHighlighter {
    private static let keywords = """
        abstract and array as break callable case catch class clone const continue declare default do echo else \
        elseif empty enum extends final finally fn for foreach function global if implements instanceof \
        insteadof interface isset list match namespace new or print private protected public readonly \
        require require_once include include_once return static switch throw trait try unset use var while \
        yield true false null self parent
        """.split(separator: " ").map(String.init)

    private static let keywordPattern = regex("\\b(" + keywords.joined(separator: "|") + ")\\b", caseInsensitive: true)
    private static let classPattern = regex("\\b[A-Z][A-Za-z0-9_]*(\\\\[A-Z][A-Za-z0-9_]*)*\\b")
    private static let memberPattern = regex("(?<=->|::|\\?->)[A-Za-z_][A-Za-z0-9_]*")
    private static let variablePattern = regex("\\$[A-Za-z_][A-Za-z0-9_]*")
    private static let numberPattern = regex("\\b\\d+(\\.\\d+)?\\b")
    /// Group 1 is a string, group 2 a comment.
    private static let stringsAndComments = regex(
        "('(?:\\\\.|[^'\\\\])*'|\"(?:\\\\.|[^\"\\\\])*\")|(//[^\\n]*|#(?!\\[)[^\\n]*|/\\*[\\s\\S]*?\\*/)")

    private static func regex(_ pattern: String, caseInsensitive: Bool = false) -> NSRegularExpression {
        try! NSRegularExpression(pattern: pattern, options: caseInsensitive ? [.caseInsensitive] : [])
    }

    static func highlight(_ storage: NSTextStorage, font: NSFont, theme: Theme) {
        let full = NSRange(location: 0, length: storage.length)
        let rules: [(NSRegularExpression, NSColor)] = [
            (keywordPattern, theme.keyword), (classPattern, theme.className), (memberPattern, theme.member),
            (variablePattern, theme.variable), (numberPattern, theme.number),
        ]
        storage.beginEditing()
        storage.addAttributes([.foregroundColor: theme.text, .font: font], range: full)
        for (pattern, color) in rules {
            for match in pattern.matches(in: storage.string, range: full) {
                storage.addAttribute(.foregroundColor, value: color, range: match.range)
            }
        }
        for match in stringsAndComments.matches(in: storage.string, range: full) {
            let isString = match.range(at: 1).location != NSNotFound
            storage.addAttribute(.foregroundColor, value: isString ? theme.string : theme.comment, range: match.range)
        }
        storage.endEditing()
    }
}
