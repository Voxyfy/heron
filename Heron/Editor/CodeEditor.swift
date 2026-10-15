import AppKit
import CoreText
import SwiftUI

/// A note shown at a line of the snippet: the last expression's value, a warning or the error.
struct LineNote: Hashable {
    /// `mark` only puts a dot in the gutter: the line produced a value, shown in the result panel.
    enum Level { case mark, warning, error }
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
    var theme: Theme
    /// The project whose classes Tab can complete; nil for plain PHP.
    var project: URL?

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = CodeTextView.scrollableTextView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        let textView = scroll.documentView as! CodeTextView
        _ = textView.layoutManager // stay on TextKit 1 from the start, so measuring and drawing agree
        scroll.clipsToBounds = true
        textView.clipsToBounds = true
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
        textView.textContainerInset = NSSize(width: 6, height: 10)
        textView.string = text
        textView.insertionPointColor = theme.text
        let ruler = LineNumberRuler(textView: textView, scrollView: scroll)
        ruler.theme = theme
        scroll.verticalRulerView = ruler
        scroll.hasVerticalRuler = true
        scroll.rulersVisible = true
        apply(to: textView)
        textView.theme = theme
        textView.completer = ClassCompleter.index(project: project)
        textView.completerProject = project
        textView.engine = CompletionEngine(project: project)
        PHPHighlighter.highlight(textView.textStorage!, font: font, theme: theme)
        #if DEBUG
        // `-heron.demoCompletion YES` opens the list at the end of the text, for screenshots.
        if UserDefaults.standard.bool(forKey: "heron.demoCompletion") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                textView.window?.makeFirstResponder(textView)
                textView.setSelectedRange(NSRange(location: textView.string.utf16.count, length: 0))
                textView.refreshCompletions()
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { textView.refreshCompletions() }
            }
        }
        #endif
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
        if textView.completerProject != project {
            textView.completer = ClassCompleter.index(project: project)
            textView.completerProject = project
            textView.engine?.setProject(project)
        }
        if textView.theme != theme {
            textView.theme = theme
            textView.insertionPointColor = theme.text
            (scroll.verticalRulerView as? LineNumberRuler)?.theme = theme
            PHPHighlighter.highlight(textView.textStorage!, font: font, theme: theme)
            (scroll.verticalRulerView as? LineNumberRuler)?.marks = Self.marks(for: notes, theme: theme)
        }
        if textView.notes != notes {
            textView.notes = notes
            textView.needsDisplay = true
            (scroll.verticalRulerView as? LineNumberRuler)?.marks = Self.marks(for: notes, theme: theme)
        }
    }

    static func marks(for notes: [LineNote], theme: Theme) -> [Int: NSColor] {
        var marks: [Int: NSColor] = [:]
        // Sorted so an error wins over a warning on the same line.
        for note in notes.sorted(by: { $0.level.rank < $1.level.rank }) { marks[note.line] = note.level.color(theme) }
        return marks
    }

    private func apply(to textView: CodeTextView) {
        textView.indentUnit = indentUnit
        if textView.font != font {
            textView.font = font
            textView.typingAttributes[.font] = font
            PHPHighlighter.highlight(textView.textStorage!, font: font, theme: theme)
        }
        // A tab shows as wide as the chosen indent.
        let paragraph = NSMutableParagraphStyle()
        // Space goes below each line, so the caret is as tall as the text and the text sits at the top
        // of its row; stretching the line box (lineHeightMultiple) made the caret taller than the letters.
        let natural = textView.layoutManager?.defaultLineHeight(for: font) ?? font.pointSize * 1.2
        paragraph.lineSpacing = (natural * 0.62).rounded()
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
            PHPHighlighter.highlight(textView.textStorage!, font: parent.font, theme: parent.theme)
            parent.text = textView.string
            textView.offerCompletionsIfTyping()
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
    var theme = Theme.heronDark
    var completer = ClassCompleter(candidates: ClassCompleter.laravel)
    var completerProject: URL?
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

    // MARK: Completion

    /// The engine knows classes, members and functions; the panel shows them under the caret.
    var engine: CompletionEngine?
    private let panel = CompletionPanel()
    private var panelRange = NSRange(location: 0, length: 0)
    /// Tests set the range a choice replaces, since they don't open the panel.
    @objc var panelRangeForTests: NSRange {
        get { panelRange }
        set { panelRange = newValue }
    }
    private var isApplyingCompletion = false

    /// After typing a letter, "$", "->" or "::", the list opens or updates; on anything else it closes.
    func offerCompletionsIfTyping() {
        guard !isApplyingCompletion else { return }
        guard let event = NSApp.currentEvent, event.type == .keyDown, selectedRange().length == 0,
              let typed = event.characters, let last = typed.last,
              last.isLetter || last.isNumber || last == "_" || last == "$" || last == ">" || last == ":" || event.keyCode == 51
        else { hideCompletions(); return }
        refreshCompletions()
    }

    func refreshCompletions() {
        guard let engine, let window else { return }
        engine.onDataArrived = { [weak self] in self?.refreshCompletions() }
        let text = string as NSString
        guard let (range, items) = engine.suggestions(in: text, cursor: selectedRange().location), !items.isEmpty else {
            hideCompletions()
            return
        }
        panelRange = range
        panel.onChoose = { [weak self] item in self?.choose(item) }
        panel.onSelectionChange = { [weak self] in self?.needsDisplay = true }
        let rect = firstRect(forCharacterRange: NSRange(location: range.location, length: 0), actualRange: nil)
        panel.show(items, prefix: text.substring(with: range), theme: theme,
                   font: font ?? .monospacedSystemFont(ofSize: 15, weight: .regular), below: rect, in: window)
        needsDisplay = true
    }

    func hideCompletions() {
        if panel.isVisible {
            panel.hide()
            needsDisplay = true
        }
    }

    /// The rest of the chosen entry, faint and italic after the caret, so Return's effect is visible.
    private func drawGhostText() {
        guard panel.isVisible, let item = panel.selected, let font, let layout = layoutManager, let container = textContainer else { return }
        let text = string as NSString
        guard panelRange.location + panelRange.length <= text.length else { return }
        let typed = text.substring(with: panelRange)
        guard item.label.lowercased().hasPrefix(typed.lowercased()), item.label.count > typed.count else { return }
        let rest = String(item.label.dropFirst(typed.count))
        let caret = NSRange(location: panelRange.location + panelRange.length, length: 0)
        let glyph = layout.glyphRange(forCharacterRange: caret, actualCharacterRange: nil)
        var rect = layout.boundingRect(forGlyphRange: NSRange(location: max(glyph.location - 1, 0), length: glyph.location > 0 ? 1 : 0), in: container)
        if glyph.location == 0 { rect = layout.lineFragmentRect(forGlyphAt: 0, effectiveRange: nil); rect.size.width = 0 }
        let x = (glyph.location > 0 ? rect.maxX : rect.minX + container.lineFragmentPadding) + textContainerOrigin.x
        let baseline = rect.minY + textContainerOrigin.y + layout.location(forGlyphAt: max(glyph.location - 1, 0)).y
        let italic = NSFont(descriptor: font.fontDescriptor.withSymbolicTraits(.italic), size: font.pointSize)
            .flatMap { $0.familyName == nil ? nil : $0 } ?? font
        let label = NSAttributedString(string: rest, attributes: [.font: italic, .foregroundColor: theme.muted.withAlphaComponent(0.8)])
        let line = CTLineCreateWithAttributedString(label)
        if let context = NSGraphicsContext.current?.cgContext {
            context.saveGState()
            context.textMatrix = .identity
            context.translateBy(x: x, y: baseline)
            context.scaleBy(x: 1, y: -1)
            CTLineDraw(line, context)
            context.restoreGState()
        }
    }

    /// The chosen entry replaces the typed prefix. A callable with required parameters comes with
    /// them as placeholders, the first one selected; Tab moves to the next, then past the ")".
    func choose(_ item: CompletionItem) {
        isApplyingCompletion = true
        defer { isApplyingCompletion = false }
        hideCompletions()
        let text = string as NSString
        guard panelRange.location + panelRange.length <= text.length else { return }
        let (expansion, relative) = item.expansion()
        if shouldChangeText(in: panelRange, replacementString: expansion) {
            replaceCharacters(in: panelRange, with: expansion)
            didChangeText()
        }
        let start = panelRange.location
        placeholders = relative.map { NSRange(location: start + $0.location, length: $0.length) }
        if let first = placeholders.first {
            placeholderEnd = start + expansion.utf16.count
            setSelectedRange(first)
        } else {
            setSelectedRange(NSRange(location: start + expansion.utf16.count, length: 0))
        }
        if let use = item.use {
            addUseLine(for: ClassCompleter.Candidate(name: item.label, fullName: use))
        }
    }

    // MARK: Placeholders

    /// Parameter placeholders of the last completion, in order; the first is the one being filled.
    private(set) var placeholders: [NSRange] = []
    private var placeholderEnd = 0
    private var pendingEdit: (location: Int, delta: Int)?

    /// Selects the next placeholder; after the last one the caret goes past the closing ")".
    func jumpToNextPlaceholder() -> Bool {
        guard !placeholders.isEmpty else { return false }
        placeholders.removeFirst()
        if let next = placeholders.first {
            setSelectedRange(next)
        } else {
            setSelectedRange(NSRange(location: min(placeholderEnd, string.utf16.count), length: 0))
        }
        return true
    }

    override func shouldChangeText(in affectedCharRange: NSRange, replacementString: String?) -> Bool {
        let allowed = super.shouldChangeText(in: affectedCharRange, replacementString: replacementString)
        if allowed, !placeholders.isEmpty {
            pendingEdit = (affectedCharRange.location, (replacementString?.utf16.count ?? 0) - affectedCharRange.length)
        }
        return allowed
    }

    override func didChangeText() {
        super.didChangeText()
        // Keep the remaining placeholders where the text moved them; an edit outside ends the round.
        guard let edit = pendingEdit else { return }
        pendingEdit = nil
        guard let current = placeholders.first, edit.location >= current.location,
              edit.location <= current.location + current.length else {
            placeholders = []
            return
        }
        placeholders[0] = NSRange(location: current.location, length: max(current.length + edit.delta, 0))
        for index in placeholders.indices.dropFirst() { placeholders[index].location += edit.delta }
        placeholderEnd += edit.delta
    }

    override func keyDown(with event: NSEvent) {
        if panel.isVisible {
            switch event.keyCode {
            case 125: panel.move(by: 1); return      // down
            case 126: panel.move(by: -1); return     // up
            case 36, 48:                             // return, tab
                if let selected = panel.selected { choose(selected) }
                return
            case 53: hideCompletions(); return       // escape
            default: break
            }
        }
        super.keyDown(with: event)
    }

    override func resignFirstResponder() -> Bool {
        hideCompletions()
        return super.resignFirstResponder()
    }

    override func mouseDown(with event: NSEvent) {
        hideCompletions()
        placeholders = []
        super.mouseDown(with: event)
    }

    /// Tab moves between placeholders; after a class name it completes it and adds its `use` line;
    /// otherwise it indents.
    override func insertTab(_ sender: Any?) {
        if jumpToNextPlaceholder() { return }
        if selectedRange().length == 0, completeClass() { return }
        insertText(indentUnit, replacementRange: selectedRange())
    }

    private func completeClass() -> Bool {
        let text = string as NSString
        guard let (name, range) = ClassCompleter.word(before: selectedRange().location, in: text) else { return false }
        let matches = completer.matches(for: name)
        guard let first = matches.first else { return false }
        // Already complete and imported: nothing to do, so Tab indents like anywhere else.
        if first.name == name, ClassCompleter.adding(use: first.fullName, to: string).insertedAt == nil { return false }
        if matches.count == 1 || first.name == name {
            apply(first, replacing: range)
        } else {
            // Several classes start like this: let the user pick.
            let menu = NSMenu()
            for candidate in matches.prefix(12) {
                let item = NSMenuItem(title: candidate.fullName, action: #selector(pickCompletion(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = [candidate.name, candidate.fullName, range.location, range.length]
                menu.addItem(item)
            }
            let origin = layoutManager?.boundingRect(forGlyphRange: NSRange(location: range.location, length: 0), in: textContainer!).origin ?? .zero
            menu.popUp(positioning: nil, at: NSPoint(x: origin.x + textContainerOrigin.x, y: origin.y + textContainerOrigin.y + (font?.pointSize ?? 13) * 1.6), in: self)
        }
        return true
    }

    @objc private func pickCompletion(_ sender: NSMenuItem) {
        guard let values = sender.representedObject as? [Any], values.count == 4,
              let name = values[0] as? String, let fullName = values[1] as? String,
              let location = values[2] as? Int, let length = values[3] as? Int else { return }
        apply(ClassCompleter.Candidate(name: name, fullName: fullName), replacing: NSRange(location: location, length: length))
    }

    /// Writes the short name over the typed prefix, then the use line at the top, keeping the caret in place.
    private func apply(_ candidate: ClassCompleter.Candidate, replacing range: NSRange) {
        var cursor = selectedRange().location
        if shouldChangeText(in: range, replacementString: candidate.name) {
            replaceCharacters(in: range, with: candidate.name)
            didChangeText()
            cursor += candidate.name.utf16.count - range.length
        }
        setSelectedRange(NSRange(location: min(cursor, string.utf16.count), length: 0))
        addUseLine(for: candidate)
    }

    /// Adds `use Full\Name;` at the top unless it is there, keeping the caret on the same code.
    func addUseLine(for candidate: ClassCompleter.Candidate) {
        var cursor = selectedRange().location
        let (code, insertedAt) = ClassCompleter.adding(use: candidate.fullName, to: string)
        guard let insertedAt else { return }
        let whole = NSRange(location: 0, length: string.utf16.count)
        if shouldChangeText(in: whole, replacementString: code) {
            let added = code.utf16.count - string.utf16.count
            replaceCharacters(in: whole, with: code)
            didChangeText()
            cursor += insertedAt <= cursor ? added : 0
        }
        setSelectedRange(NSRange(location: min(cursor, string.utf16.count), length: 0))
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

    /// Brackets and quotes come in pairs: "(" gives "()" with the caret inside, a closer that is
    /// already there is stepped over, a selection gets wrapped. A closing bracket on an empty
    /// line moves it back one level.
    override func insertText(_ string: Any, replacementRange: NSRange) {
        if let typed = string as? String, typed.count == 1, replacementRange.length == 0 || replacementRange == selectedRange(),
           handlePairs(typed) {
            return
        }
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

    // MARK: Caret

    /// The blinking caret is as tall as the letters, whatever the line spacing is.
    override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn flag: Bool) {
        var caret = rect
        if let font, let layoutManager {
            caret.size.height = min(rect.height, layoutManager.defaultLineHeight(for: font))
        }
        super.drawInsertionPoint(in: caret, color: color, turnedOn: flag)
    }

    /// Asked to repaint the caret's old place when it moves or blinks: cover the taller area the
    /// system assumes too, so no stale bar stays behind.
    override func setNeedsDisplay(_ invalidRect: NSRect) {
        var area = invalidRect
        area.size.width += 1
        super.setNeedsDisplay(area)
    }

    private static let pairs: [String: String] = ["(": ")", "[": "]", "{": "}", "'": "'", "\"": "\""]

    private func handlePairs(_ typed: String) -> Bool {
        let text = string as NSString
        let selection = selectedRange()
        let next = selection.location + selection.length < text.length
            ? text.substring(with: NSRange(location: selection.location + selection.length, length: 1)) : ""
        let previous = selection.location > 0 ? text.substring(with: NSRange(location: selection.location - 1, length: 1)) : ""
        // Step over a closer that is already there.
        if Self.pairs.values.contains(typed), selection.length == 0, next == typed {
            setSelectedRange(NSRange(location: selection.location + 1, length: 0))
            return true
        }
        guard let closer = Self.pairs[typed] else { return false }
        // Wrap a selection: (selected) or 'selected'.
        if selection.length > 0 {
            let inner = text.substring(with: selection)
            super.insertText(typed + inner + closer, replacementRange: selection)
            setSelectedRange(NSRange(location: selection.location + 1, length: inner.utf16.count))
            return true
        }
        // A quote right after a letter or digit is an apostrophe or the end of a word, not a pair.
        if typed == closer, let last = previous.last, last.isLetter || last.isNumber || last == "\\" { return false }
        // Only pair before whitespace, a closer, or the end, so typing into existing text stays sane.
        guard next.isEmpty || next.first!.isWhitespace || [")", "]", "}", ",", ";", "'", "\""].contains(next) else { return false }
        super.insertText(typed + closer, replacementRange: selection)
        setSelectedRange(NSRange(location: selection.location + 1, length: 0))
        return true
    }

    /// Backspace inside an empty pair removes both characters.
    override func deleteBackward(_ sender: Any?) {
        let text = string as NSString
        let selection = selectedRange()
        if selection.length == 0, selection.location > 0, selection.location < text.length {
            let before = text.substring(with: NSRange(location: selection.location - 1, length: 1))
            let after = text.substring(with: NSRange(location: selection.location, length: 1))
            if Self.pairs[before] == after {
                let range = NSRange(location: selection.location - 1, length: 2)
                if shouldChangeText(in: range, replacementString: "") {
                    replaceCharacters(in: range, with: "")
                    didChangeText()
                }
                return
            }
        }
        super.deleteBackward(sender)
    }

    // MARK: Notes

    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
        needsDisplay = true
    }

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        drawIndentGuides(in: rect)
        for note in notes where note.level == .error || note.level == .warning {
            guard let lineRect = rectForLine(note.line) else { continue }
            color(for: note.level).withAlphaComponent(0.13).setFill()
            NSRect(x: 0, y: lineRect.minY - extraLineSpace / 2, width: bounds.width, height: lineRect.height).fill()
        }
    }

    /// The line spacing added below each line, so bands can be centered on the text.
    private var extraLineSpace: CGFloat { defaultParagraphStyle?.lineSpacing ?? 0 }

    /// Errors and warnings: a tinted line with a small pill after the code that says what went wrong.
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawGhostText()
        let font = self.font ?? .monospacedSystemFont(ofSize: 13, weight: .regular)
        let noteFont = NSFont.systemFont(ofSize: max(font.pointSize - 1, 10), weight: .medium)
        for note in notes where note.level == .error || note.level == .warning {
            guard let lineRect = rectForLine(note.line, lastFragmentOnly: true) else { continue }
            let symbol = note.level == .error ? "xmark.octagon.fill" : "exclamationmark.triangle.fill"
            let attributes: [NSAttributedString.Key: Any] = [.font: noteFont, .foregroundColor: color(for: note.level)]
            let label = NSAttributedString(string: note.message, attributes: attributes)
            let size = label.size()
            let padding: CGFloat = 8
            let iconSize = noteFont.pointSize + 2
            // Right after the line's text; pushed left only as far as needed to stay in view.
            let available = bounds.width - textContainerInset.width - 12
            let width = min(size.width + iconSize + padding * 3, available * 0.7)
            let x = min(lineRect.maxX + 20, available - width)
            let pill = NSRect(x: max(x, textContainerOrigin.x), y: lineRect.minY + 1, width: width,
                              height: lineRect.height - 2)
            color(for: note.level).withAlphaComponent(0.16).setFill()
            NSBezierPath(roundedRect: pill, xRadius: 5, yRadius: 5).fill()
            if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: noteFont.pointSize, weight: .semibold)
                    .applying(.init(paletteColors: [color(for: note.level)]))) {
                image.draw(in: NSRect(x: pill.minX + padding, y: pill.midY - iconSize / 2, width: iconSize, height: iconSize))
            }
            label.draw(with: NSRect(x: pill.minX + padding * 2 + iconSize, y: pill.midY - size.height / 2,
                                    width: pill.width - padding * 3 - iconSize, height: size.height),
                       options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
        }
    }

    private func color(for level: LineNote.Level) -> NSColor { level.color(theme) }

    /// A faint vertical line at every indentation level, like most code editors.
    private func drawIndentGuides(in rect: NSRect) {
        guard let layout = layoutManager, let container = textContainer, let font else { return }
        let unitWidth = (indentUnit == "\t" ? "    " : indentUnit).size(withAttributes: [.font: font]).width
        guard unitWidth > 0 else { return }
        let text = string as NSString
        let visible = layout.glyphRange(forBoundingRect: rect, in: container)
        let characters = layout.characterRange(forGlyphRange: visible, actualGlyphRange: nil)
        theme.border.withAlphaComponent(0.7).setFill()
        var index = text.lineRange(for: NSRange(location: characters.location, length: 0)).location
        var previousLevels = 0
        while index < NSMaxRange(characters) {
            let range = text.lineRange(for: NSRange(location: index, length: 0))
            let line = text.substring(with: range)
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            var levels = 0
            if trimmed.isEmpty {
                levels = previousLevels   // blank lines keep the guides of the line above
            } else {
                let leading = line.prefix { $0 == " " || $0 == "\t" }
                let columns = leading.reduce(0) { $0 + ($1 == "\t" ? 4 : 1) }
                levels = columns / max(indentUnit == "\t" ? 4 : indentUnit.count, 1)
            }
            previousLevels = levels
            if levels > 0 {
                let glyph = layout.glyphIndexForCharacter(at: range.location)
                var fragment = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
                fragment.origin.x += textContainerOrigin.x
                fragment.origin.y += textContainerOrigin.y
                for level in 0..<levels {
                    let x = (fragment.minX + container.lineFragmentPadding + CGFloat(level) * unitWidth).rounded() + 0.5
                    NSRect(x: x, y: fragment.minY, width: 1, height: fragment.height).fill()
                }
            }
            index = NSMaxRange(range)
        }
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
    func color(_ theme: Theme) -> NSColor {
        switch self {
        case .mark: theme.mark
        case .warning: .systemOrange
        case .error: .systemRed
        }
    }

    var rank: Int {
        switch self {
        case .mark: 0
        case .warning: 1
        case .error: 2
        }
    }
}
