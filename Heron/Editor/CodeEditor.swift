import AppKit
import SwiftUI

/// A note shown at a line of the snippet: the last expression's value, a warning or the error.
struct LineNote: Hashable {
    /// `mark` only puts a dot in the gutter: the line produced a value, shown in the result panel.
    enum Level { case mark, value, warning, error }
    let line: Int
    let message: String
    let level: Level
}

/// The PHP editor: a plain NSTextView with highlighting, smart indentation and notes drawn
/// at the lines they belong to, like Xcode's inline errors.
struct CodeEditor: NSViewRepresentable {
    @Binding var text: String
    var notes: [LineNote]
    var font: NSFont
    var indentUnit: String
    var wrapsLines: Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = CodeTextView.scrollableTextView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        let textView = scroll.documentView as! CodeTextView
        _ = textView.layoutManager // stay on TextKit 1 from the start, so measuring and drawing agree
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 10, height: 10)
        textView.string = text
        let ruler = LineNumberRuler(textView: textView, scrollView: scroll)
        scroll.verticalRulerView = ruler
        scroll.hasVerticalRuler = true
        scroll.rulersVisible = true
        apply(to: textView)
        PHPHighlighter.highlight(textView.textStorage!, font: font)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let textView = scroll.documentView as! CodeTextView
        context.coordinator.parent = self
        if textView.string != text {
            // Replaced from outside (tidying, a snippet): keep undo and the cursor's line.
            let selection = textView.selectedRange()
            if textView.shouldChangeText(in: NSRange(location: 0, length: textView.string.utf16.count), replacementString: text) {
                textView.string = text
                textView.didChangeText()
            }
            let location = min(selection.location, text.utf16.count)
            textView.setSelectedRange(NSRange(location: location, length: 0))
        }
        apply(to: textView)
        if textView.notes != notes {
            textView.notes = notes
            textView.needsDisplay = true
            (scroll.verticalRulerView as? LineNumberRuler)?.marks = Self.marks(for: notes)
        }
    }

    static func marks(for notes: [LineNote]) -> [Int: NSColor] {
        var marks: [Int: NSColor] = [:]
        // Sorted so an error wins over a warning on the same line.
        for note in notes.sorted(by: { $0.level.rank < $1.level.rank }) { marks[note.line] = note.level.color }
        return marks
    }

    private func apply(to textView: CodeTextView) {
        textView.indentUnit = indentUnit
        if textView.font != font {
            textView.font = font
            textView.typingAttributes[.font] = font
            PHPHighlighter.highlight(textView.textStorage!, font: font)
        }
        // A tab shows as wide as the chosen indent.
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineHeightMultiple = 1.6
        let space = (" " as NSString).size(withAttributes: [.font: font]).width
        paragraph.defaultTabInterval = space * CGFloat(max(indentUnit == "\t" ? 4 : indentUnit.count, 1))
        paragraph.tabStops = []
        textView.defaultParagraphStyle = paragraph
        textView.typingAttributes[.paragraphStyle] = paragraph
        textView.textStorage?.addAttribute(.paragraphStyle, value: paragraph,
                                           range: NSRange(location: 0, length: textView.string.utf16.count))
        if textView.wrapsLines != wrapsLines {
            textView.wrapsLines = wrapsLines
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CodeEditor
        init(_ parent: CodeEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? CodeTextView else { return }
            PHPHighlighter.highlight(textView.textStorage!, font: parent.font)
            parent.text = textView.string
            // A note belongs to the code it was about; editing makes it stale.
            if !textView.notes.isEmpty {
                textView.notes = []
                textView.needsDisplay = true
                (textView.enclosingScrollView?.verticalRulerView as? LineNumberRuler)?.marks = [:]
            }
        }
    }
}

final class CodeTextView: NSTextView {
    var notes: [LineNote] = []
    var indentUnit = "    "
    var wrapsLines = true {
        didSet {
            guard let container = textContainer, let scroll = enclosingScrollView else { return }
            container.widthTracksTextView = wrapsLines
            isHorizontallyResizable = !wrapsLines
            scroll.hasHorizontalScroller = !wrapsLines
            if wrapsLines {
                container.size = NSSize(width: scroll.contentSize.width, height: .greatestFiniteMagnitude)
                frame.size.width = scroll.contentSize.width
            } else {
                container.size = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
            }
        }
    }

    // MARK: Indentation

    override func insertTab(_ sender: Any?) {
        insertText(indentUnit, replacementRange: selectedRange())
    }

    /// A new line keeps the current line's indentation, one level more after "{", "(" or "[".
    override func insertNewline(_ sender: Any?) {
        let text = string as NSString
        let cursor = selectedRange().location
        let line = text.lineRange(for: NSRange(location: cursor, length: 0))
        let before = text.substring(with: NSRange(location: line.location, length: cursor - line.location))
        var indent = String(before.prefix { $0 == " " || $0 == "\t" })
        let trimmed = before.trimmingCharacters(in: .whitespaces)
        if let last = trimmed.last, "{([".contains(last) { indent += indentUnit }
        insertText("\n" + indent, replacementRange: selectedRange())
    }

    /// Typing a closing bracket on an empty line moves it back one level.
    override func insertText(_ string: Any, replacementRange: NSRange) {
        if let typed = string as? String, ["}", ")", "]"].contains(typed) {
            let text = self.string as NSString
            let cursor = selectedRange().location
            let line = text.lineRange(for: NSRange(location: cursor, length: 0))
            let before = text.substring(with: NSRange(location: line.location, length: cursor - line.location))
            if !before.isEmpty, before.allSatisfy({ $0 == " " || $0 == "\t" }) {
                let unit = before.hasSuffix(indentUnit) ? indentUnit.count : (before.hasSuffix("\t") ? 1 : 0)
                let start = cursor - (before as NSString).length
                let kept = (before as NSString).substring(to: (before as NSString).length - unit)
                super.insertText(kept + typed, replacementRange: NSRange(location: start, length: cursor - start))
                return
            }
        }
        super.insertText(string, replacementRange: replacementRange)
    }

    // MARK: Notes

    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
        needsDisplay = true
    }

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        // The current line, faintly.
        if let current = rectForLine(currentLine) {
            NSColor.labelColor.withAlphaComponent(0.04).setFill()
            NSRect(x: 0, y: current.minY, width: bounds.width, height: current.height).fill()
        }
        for note in notes where note.level == .error || note.level == .warning {
            guard let lineRect = rectForLine(note.line) else { continue }
            color(for: note.level).withAlphaComponent(0.13).setFill()
            NSRect(x: 0, y: lineRect.minY, width: bounds.width, height: lineRect.height).fill()
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let font = self.font ?? .monospacedSystemFont(ofSize: 13, weight: .regular)
        let noteFont = NSFont.systemFont(ofSize: max(font.pointSize - 1, 10), weight: .medium)
        for note in notes where note.level != .mark {
            guard let lineRect = rectForLine(note.line, lastFragmentOnly: true) else { continue }
            let symbol = switch note.level {
            case .error: "xmark.octagon.fill"
            case .warning: "exclamationmark.triangle.fill"
            case .value, .mark: "equal"
            }
            let attributes: [NSAttributedString.Key: Any] = [.font: noteFont, .foregroundColor: color(for: note.level)]
            let label = NSAttributedString(string: note.message, attributes: attributes)
            let size = label.size()
            let padding: CGFloat = 8
            let iconSize: CGFloat = note.level == .value ? 0 : noteFont.pointSize + 2
            // Right after the line's text; pushed left only as far as needed to stay in view.
            let available = bounds.width - textContainerInset.width - 12
            let width = min(size.width + iconSize + padding * (iconSize > 0 ? 3 : 2), available * 0.7)
            let x = min(lineRect.maxX + 20, available - width)
            let pill = NSRect(x: max(x, textContainerOrigin.x), y: lineRect.minY + 1, width: width,
                              height: lineRect.height - 2)
            color(for: note.level).withAlphaComponent(0.16).setFill()
            NSBezierPath(roundedRect: pill, xRadius: 5, yRadius: 5).fill()
            if note.level != .value, let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: noteFont.pointSize, weight: .semibold)
                    .applying(.init(paletteColors: [color(for: note.level)]))) {
                image.draw(in: NSRect(x: pill.minX + padding, y: pill.midY - iconSize / 2, width: iconSize, height: iconSize))
            }
            label.draw(with: NSRect(x: pill.minX + padding + (iconSize > 0 ? padding + iconSize : 0), y: pill.midY - size.height / 2,
                                    width: pill.width - padding * (iconSize > 0 ? 3 : 2) - iconSize, height: size.height),
                       options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
        }
    }

    private func color(for level: LineNote.Level) -> NSColor { level.color }

    private var currentLine: Int {
        let text = string as NSString
        let location = min(selectedRange().location, text.length)
        return text.substring(to: location).reduce(1) { $1 == "\n" ? $0 + 1 : $0 }
    }

    /// The rectangle of a 1-based line in view coordinates, covering all its wrapped fragments.
    private func rectForLine(_ number: Int, lastFragmentOnly: Bool = false) -> NSRect? {
        guard let layout = layoutManager, let container = textContainer, number >= 1 else { return nil }
        // Tidying may have just replaced the text; measure the new layout, not the old one.
        layout.ensureLayout(for: container)
        let text = string as NSString
        var location = 0
        for _ in 1..<number {
            let range = text.lineRange(for: NSRange(location: location, length: 0))
            guard NSMaxRange(range) < text.length || range.length > 0 else { return nil }
            location = NSMaxRange(range)
            if location >= text.length { break }
        }
        let lineRange = text.lineRange(for: NSRange(location: min(location, text.length), length: 0))
        let glyphs = layout.glyphRange(forCharacterRange: lineRange, actualCharacterRange: nil)
        var rect: NSRect
        if glyphs.length == 0 {
            rect = layout.extraLineFragmentRect
            if rect == .zero { return nil }
        } else if lastFragmentOnly {
            // The line's last wrapped fragment; its width is measured from the text itself, since
            // the glyph layout can disagree with the drawn ligatures (→ for ->) by a few characters.
            var fragment = NSRange()
            rect = layout.lineFragmentRect(forGlyphAt: NSMaxRange(glyphs) - 1, effectiveRange: &fragment)
            let visible = NSIntersectionRange(fragment, glyphs)
            let characters = layout.characterRange(forGlyphRange: visible.length > 0 ? visible : fragment,
                                                   actualGlyphRange: nil)
            var piece = textStorage?.attributedSubstring(from: characters) ?? NSAttributedString()
            if piece.string.hasSuffix("\n") {
                piece = piece.attributedSubstring(from: NSRange(location: 0, length: piece.length - 1))
            }
            rect.origin.x += container.lineFragmentPadding
            rect.size.width = piece.size().width
        } else {
            rect = layout.boundingRect(forGlyphRange: glyphs, in: container)
        }
        rect.origin.x += textContainerOrigin.x
        rect.origin.y += textContainerOrigin.y
        return rect
    }
}

extension LineNote.Level {
    var color: NSColor {
        switch self {
        case .value, .mark: .heronMark
        case .warning: .systemOrange
        case .error: .systemRed
        }
    }

    var rank: Int {
        switch self {
        case .mark: 0
        case .value: 1
        case .warning: 2
        case .error: 3
        }
    }
}
