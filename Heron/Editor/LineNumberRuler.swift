import AppKit
import CoreText

/// The gutter: line numbers in the editor's own size, the current line highlighted, and a
/// small square after the number of every line the last run produced a value for.
final class LineNumberRuler: NSRulerView {
    var marks: [Int: NSColor] = [:] {
        didSet { needsDisplay = true }
    }
    var theme = Theme.heronDark {
        didSet { needsDisplay = true }
    }

    private var textView: NSTextView? { clientView as? NSTextView }

    init(textView: NSTextView, scrollView: NSScrollView) {
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        clientView = textView
        ruleThickness = 54
        clipsToBounds = true
        NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: NSText.didChangeNotification,
                                               object: textView)
        NotificationCenter.default.addObserver(self, selector: #selector(refresh),
                                               name: NSTextView.didChangeSelectionNotification, object: textView)
        NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: NSView.boundsDidChangeNotification,
                                               object: scrollView.contentView)
    }

    required init(coder: NSCoder) { fatalError("not used") }

    @objc private func refresh() { needsDisplay = true }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        // The gutter is part of the editor: same background, no divider, numbers hugging the left
        // edge and the code a short step after them. (Painting in draw(_:) instead stopped the
        // text view from drawing on macOS 26.)
        theme.background.setFill()
        bounds.fill()
        guard let textView, let layout = textView.layoutManager, let container = textView.textContainer else { return }
        let text = textView.string as NSString
        let editorFont = textView.font ?? .monospacedSystemFont(ofSize: 13, weight: .regular)
        // The editor's own font, so digits and code share a baseline and a look.
        let font = editorFont
        let visible = textView.visibleRect
        let glyphs = layout.glyphRange(forBoundingRect: visible, in: container)
        let characters = layout.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        let cursorLine = lineNumber(at: textView.selectedRange().location, in: text)
        // Just wide enough for the biggest line number, like the reference; grows past 99 lines.
        let digits = max(2, String(lineNumber(at: text.length, in: text)).count)
        let digitWidth = ("0" as NSString).size(withAttributes: [.font: font]).width
        let wanted = (CGFloat(digits) * digitWidth + 26).rounded()
        if abs(ruleThickness - wanted) > 0.5 {
            ruleThickness = wanted
            return // the scroll view re-tiles and asks us to draw again
        }

        var line = lineNumber(at: characters.location, in: text)
        var index = text.lineRange(for: NSRange(location: characters.location, length: 0)).location
        let originY = convert(NSPoint.zero, from: textView).y + textView.textContainerOrigin.y
        let numberRight = ruleThickness - 16

        // Extra line spacing sits below the text in each fragment; the highlight band is centered
        // on the digits instead, with the same breathing room above and below.
        let lineHeight = layout.defaultLineHeight(for: editorFont)
        func draw(_ number: Int, fragment: NSRect, baseline: CGFloat) {
            let y = originY + fragment.minY
            let isCurrent = number == cursorLine
            if isCurrent {
                // Centered on the digits themselves (cap height), so the gap above and below looks equal.
                let height = fragment.height
                let middle = originY + baseline - editorFont.capHeight / 2
                theme.currentLine.setFill()
                NSRect(x: 0, y: (middle - height / 2).rounded(), width: ruleThickness, height: height).fill()
            }
            let label = NSAttributedString(string: "\(number)", attributes: [
                .font: font,
                .foregroundColor: isCurrent ? theme.text : theme.muted,
            ])
            // Digits stand on exactly the code's baseline: Core Text draws from the baseline, so no
            // ascender arithmetic can drift by half a point.
            let ctLine = CTLineCreateWithAttributedString(label)
            let width = CTLineGetTypographicBounds(ctLine, nil, nil, nil)
            if let context = NSGraphicsContext.current?.cgContext {
                context.saveGState()
                context.textMatrix = .identity
                context.translateBy(x: numberRight - width, y: originY + baseline)
                context.scaleBy(x: 1, y: -1)
                CTLineDraw(ctLine, context)
                context.restoreGState()
            }
            if let color = marks[number] {
                color.setFill()
                let side: CGFloat = 6
                let middle = originY + baseline - font.capHeight / 2
                NSBezierPath(roundedRect: NSRect(x: numberRight + 5, y: middle - side / 2, width: side, height: side),
                             xRadius: 1, yRadius: 1).fill()
            }
        }

        // Where the code's glyphs really stand; a blank line (only a newline glyph) reuses the
        // offset of the last line that had text, since every row is laid out the same way.
        var baselineOffset = layout.defaultBaselineOffset(for: editorFont)
        while index < NSMaxRange(characters) {
            let range = text.lineRange(for: NSRange(location: index, length: 0))
            let glyph = layout.glyphIndexForCharacter(at: range.location)
            let fragment = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            if range.length > 0, text.character(at: range.location) != 0x0A {
                baselineOffset = layout.location(forGlyphAt: glyph).y
            }
            draw(line, fragment: fragment, baseline: fragment.minY + baselineOffset)
            line += 1
            index = NSMaxRange(range)
        }
        // The empty last line after a final newline.
        if text.length == 0 || text.hasSuffix("\n"), NSMaxRange(characters) >= text.length {
            let extra = layout.extraLineFragmentRect
            if extra.height > 0 {
                draw(lineNumber(at: text.length, in: text), fragment: extra, baseline: extra.minY + baselineOffset)
            }
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
