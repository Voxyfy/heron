import AppKit

/// The gutter: line numbers in the editor's own size, the current line in full color, and a
/// small green square after the number of every line the last run produced a value for.
final class LineNumberRuler: NSRulerView {
    var marks: [Int: NSColor] = [:] {
        didSet { needsDisplay = true }
    }

    private var textView: NSTextView? { clientView as? NSTextView }

    init(textView: NSTextView, scrollView: NSScrollView) {
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        clientView = textView
        ruleThickness = 60
        // Same background as the text, so the gutter is part of the editor, not a separate strip.
        // Set on the layer: painting it in draw(_:) made the text view stop drawing on macOS 26.
        wantsLayer = true
        layer?.backgroundColor = NSColor.textBackgroundColor.cgColor
        NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: NSText.didChangeNotification,
                                               object: textView)
        NotificationCenter.default.addObserver(self, selector: #selector(refresh),
                                               name: NSTextView.didChangeSelectionNotification, object: textView)
        NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: NSView.boundsDidChangeNotification,
                                               object: scrollView.contentView)
    }

    required init(coder: NSCoder) { fatalError("not used") }

    @objc private func refresh() { needsDisplay = true }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.textBackgroundColor.cgColor
        }
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView, let layout = textView.layoutManager, let container = textView.textContainer else { return }
        let text = textView.string as NSString
        let editorFont = textView.font ?? .monospacedSystemFont(ofSize: 13, weight: .regular)
        let font = NSFont.monospacedDigitSystemFont(ofSize: editorFont.pointSize, weight: .regular)
        let visible = textView.visibleRect
        let glyphs = layout.glyphRange(forBoundingRect: visible, in: container)
        let characters = layout.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        let cursorLine = lineNumber(at: textView.selectedRange().location, in: text)

        var line = lineNumber(at: characters.location, in: text)
        var index = text.lineRange(for: NSRange(location: characters.location, length: 0)).location
        let originY = convert(NSPoint.zero, from: textView).y + textView.textContainerOrigin.y
        let numberRight = ruleThickness - 22

        func draw(_ number: Int, fragment: NSRect) {
            let y = originY + fragment.minY
            let isCurrent = number == cursorLine
            if isCurrent {
                NSColor.labelColor.withAlphaComponent(0.05).setFill()
                NSRect(x: 0, y: y, width: ruleThickness, height: fragment.height).fill()
            }
            let label = NSAttributedString(string: "\(number)", attributes: [
                .font: font,
                .foregroundColor: isCurrent ? NSColor.labelColor : NSColor.tertiaryLabelColor,
            ])
            let size = label.size()
            label.draw(at: NSPoint(x: numberRight - size.width, y: y + (fragment.height - size.height) / 2))
            if let color = marks[number] {
                color.setFill()
                let side: CGFloat = 6
                NSBezierPath(roundedRect: NSRect(x: numberRight + 7, y: y + (fragment.height - side) / 2,
                                                 width: side, height: side), xRadius: 1.5, yRadius: 1.5).fill()
            }
        }

        while index < NSMaxRange(characters) {
            let range = text.lineRange(for: NSRange(location: index, length: 0))
            let glyph = layout.glyphIndexForCharacter(at: range.location)
            draw(line, fragment: layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil))
            line += 1
            index = NSMaxRange(range)
        }
        // The empty last line after a final newline.
        if text.length == 0 || text.hasSuffix("\n"), NSMaxRange(characters) >= text.length {
            let extra = layout.extraLineFragmentRect
            if extra.height > 0 { draw(lineNumber(at: text.length, in: text), fragment: extra) }
        }
    }

    private func lineNumber(at location: Int, in text: NSString) -> Int {
        var count = 1
        var index = 0
        let end = min(location, text.length)
        while index < end {
            let found = text.range(of: "\n", options: [], range: NSRange(location: index, length: end - index))
            guard found.location != NSNotFound else { break }
            count += 1
            index = found.location + 1
        }
        return count
    }
}
