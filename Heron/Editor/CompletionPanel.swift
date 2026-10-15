import AppKit

/// The list that pops up under the caret, in the editor's own type: a small kind tag, the name
/// with the typed letters emphasized, and a footer saying how to insert. The editor owns the
/// keyboard: it tells the panel to move or to choose.
@MainActor
final class CompletionPanel: NSPanel {
    private let table = NSTableView()
    private let scroll = NSScrollView()
    private let footer = NSView()
    private let insertHint = NSTextField(labelWithString: "")
    private let closeHint = NSTextField(labelWithString: "")
    private let container = NSView()
    private var rule: NSView?
    private var items: [CompletionItem] = []
    private var prefix = ""
    private var theme = Theme.heronDark
    private var font = NSFont.monospacedSystemFont(ofSize: 15, weight: .regular)
    var onChoose: ((CompletionItem) -> Void)?
    var onSelectionChange: (() -> Void)?

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 480, height: 200), styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: true)
        isFloatingPanel = true
        level = .popUpMenu
        hasShadow = true
        isOpaque = false
        backgroundColor = .clear
        hidesOnDeactivate = true

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("item"))
        table.addTableColumn(column)
        table.headerView = nil
        table.style = .plain   // the default inset style pads the rows top and bottom
        table.intercellSpacing = NSSize(width: 0, height: 0)
        table.selectionHighlightStyle = .regular
        table.backgroundColor = .clear
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.action = #selector(rowClicked)
        table.focusRingType = .none
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        // No automatic insets: they pushed the rows down, leaving a lone row against the footer.
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets = NSEdgeInsetsZero
        scroll.scrollerInsets = NSEdgeInsetsZero
        scroll.translatesAutoresizingMaskIntoConstraints = false
        footer.translatesAutoresizingMaskIntoConstraints = false
        footer.wantsLayer = true
        insertHint.translatesAutoresizingMaskIntoConstraints = false
        closeHint.translatesAutoresizingMaskIntoConstraints = false
        footer.addSubview(insertHint)
        footer.addSubview(closeHint)
        container.wantsLayer = true
        container.layer?.cornerRadius = 8
        container.layer?.borderWidth = 1
        container.layer?.masksToBounds = true
        container.addSubview(scroll)
        container.addSubview(footer)
        let rule = NSView()
        rule.translatesAutoresizingMaskIntoConstraints = false
        rule.wantsLayer = true
        container.addSubview(rule)
        self.rule = rule
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            scroll.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            rule.topAnchor.constraint(equalTo: scroll.bottomAnchor, constant: 8),
            rule.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            rule.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            rule.heightAnchor.constraint(equalToConstant: 1),
            footer.topAnchor.constraint(equalTo: rule.bottomAnchor),
            footer.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            footer.heightAnchor.constraint(equalToConstant: 28),
            insertHint.leadingAnchor.constraint(equalTo: footer.leadingAnchor, constant: 10),
            insertHint.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
            closeHint.trailingAnchor.constraint(equalTo: footer.trailingAnchor, constant: -10),
            closeHint.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
        ])
        contentView = container
    }

    func show(_ items: [CompletionItem], prefix: String, theme: Theme, font: NSFont, below rect: NSRect, in parent: NSWindow) {
        self.items = items
        self.prefix = prefix
        self.theme = theme
        self.font = font
        container.layer?.backgroundColor = theme.card.cgColor
        container.layer?.borderColor = theme.border.cgColor
        footer.layer?.backgroundColor = theme.panel.cgColor
        rule?.layer?.backgroundColor = theme.border.cgColor
        for hint in [insertHint, closeHint] {
            hint.font = .systemFont(ofSize: 11)
            hint.textColor = theme.muted
        }
        insertHint.stringValue = String(localized: "Insert (⏎)")
        closeHint.stringValue = String(localized: "Esc closes")
        table.rowHeight = (font.pointSize * 2.2).rounded()
        table.reloadData()
        let rows = min(items.count, 6)
        // The list area is exactly as tall as the rows it shows (plain style adds nothing), with
        // room above and below.
        let height = CGFloat(rows) * table.rowHeight + 8 + 8 + 1 + 28
        // No scroller when every row is in view.
        scroll.hasVerticalScroller = items.count > rows
        let width: CGFloat = max(420, min(640, rect.width + 480))
        var origin = NSPoint(x: rect.minX - 6, y: rect.minY - height - 6)
        if let screen = parent.screen {
            if origin.y < screen.visibleFrame.minY { origin.y = rect.maxY + 6 }
            if origin.x + width > screen.visibleFrame.maxX { origin.x = screen.visibleFrame.maxX - width - 8 }
        }
        setFrame(NSRect(origin: origin, size: NSSize(width: width, height: height)), display: true)
        table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        table.scrollRowToVisible(0)
        if parent.childWindows?.contains(self) != true { parent.addChildWindow(self, ordered: .above) }
        orderFront(nil)
    }

    func hide() {
        parent?.removeChildWindow(self)
        orderOut(nil)
        items = []
    }

    func move(by delta: Int) {
        guard !items.isEmpty else { return }
        let row = max(0, min(items.count - 1, table.selectedRow + delta))
        table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        table.scrollRowToVisible(row)
        onSelectionChange?()
    }

    var selected: CompletionItem? {
        items.indices.contains(table.selectedRow) ? items[table.selectedRow] : nil
    }

    @objc private func rowClicked() {
        if let selected { onChoose?(selected) }
    }

    override var canBecomeKey: Bool { false }

    /// The small word on the left of a row, saying what kind of thing it is.
    private static func kindTag(for kind: CompletionItem.Kind) -> String {
        switch kind {
        case .class: "class"
        case .method, .static, .function: "fn"
        case .property, .column, .word: "abc"
        case .relation: "rel"
        case .scope: "scope"
        case .variable: "var"
        }
    }
}

extension CompletionPanel: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int { items.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let item = items[row]
        let cell = CompletionCell()
        cell.configure(tag: Self.kindTag(for: item.kind), name: item.label, prefix: prefix,
                       detail: item.kind == .class || item.kind == .method || item.kind == .static ? item.detail : "",
                       font: font, theme: theme)
        return cell
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let view = AccentRowView()
        view.accent = theme.accent
        return view
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        onSelectionChange?()
    }
}

/// One row. Recolors itself when it becomes the selected row: white text on the accent fill.
private final class CompletionCell: NSTableCellView {
    private let kindTag = NSTextField(labelWithString: "")
    private let name = NSTextField(labelWithString: "")
    private let detail = NSTextField(labelWithString: "")
    private var plainName = ""
    private var prefix = ""
    private var font = NSFont.monospacedSystemFont(ofSize: 15, weight: .regular)
    private var theme = Theme.heronDark

    func configure(tag text: String, name: String, prefix: String, detail: String, font: NSFont, theme: Theme) {
        plainName = name
        self.prefix = prefix
        self.font = font
        self.theme = theme
        kindTag.stringValue = text
        kindTag.font = .systemFont(ofSize: max(font.pointSize * 0.62, 9), weight: .medium)
        self.detail.stringValue = detail
        self.detail.font = .monospacedSystemFont(ofSize: max(font.pointSize * 0.7, 10), weight: .regular)
        self.detail.lineBreakMode = .byTruncatingMiddle
        self.name.lineBreakMode = .byTruncatingTail
        if subviews.isEmpty {
            let spacer = NSView()
            let stack = NSStackView(views: [kindTag, self.name, spacer, self.detail])
            stack.orientation = .horizontal
            stack.spacing = 10
            stack.edgeInsets = NSEdgeInsets(top: 0, left: 12, bottom: 0, right: 12)
            stack.translatesAutoresizingMaskIntoConstraints = false
            kindTag.widthAnchor.constraint(equalToConstant: 34).isActive = true
            self.detail.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            addSubview(stack)
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: leadingAnchor), stack.trailingAnchor.constraint(equalTo: trailingAnchor),
                stack.topAnchor.constraint(equalTo: topAnchor), stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
        }
        recolor()
    }

    override var backgroundStyle: NSView.BackgroundStyle {
        didSet { recolor() }
    }

    private func recolor() {
        let selected = backgroundStyle == .emphasized
        kindTag.textColor = selected ? NSColor.white.withAlphaComponent(0.8) : theme.muted
        detail.textColor = selected ? NSColor.white.withAlphaComponent(0.8) : theme.muted
        let base = selected ? NSColor.white : theme.text
        let text = NSMutableAttributedString(string: plainName, attributes: [.font: font, .foregroundColor: base])
        if !prefix.isEmpty {
            // Bold through the descriptor: NSFontManager's conversion of the system mono font gave a
            // font that drew nothing, so whole names vanished when they matched the prefix exactly.
            let bold = NSFont(descriptor: font.fontDescriptor.withSymbolicTraits(.bold), size: font.pointSize)
                .flatMap { $0.familyName == nil ? nil : $0 } ?? font
            let accent = selected ? NSColor.white : theme.accent
            let lowerName = plainName.lowercased()
            let lowerPrefix = prefix.lowercased()
            if let range = lowerName.range(of: lowerPrefix) {
                text.addAttributes([.font: bold, .foregroundColor: accent], range: NSRange(range, in: plainName))
            } else {
                var searchFrom = lowerName.startIndex
                for letter in lowerPrefix {
                    guard let found = lowerName[searchFrom...].firstIndex(of: letter) else { break }
                    text.addAttributes([.font: bold, .foregroundColor: accent], range: NSRange(found...found, in: plainName))
                    searchFrom = lowerName.index(after: found)
                }
            }
        }
        name.attributedStringValue = text
    }
}

/// A selected row filled with the theme's accent, like the reference, not the system blue.
private final class AccentRowView: NSTableRowView {
    var accent = NSColor.controlAccentColor

    override func drawSelection(in dirtyRect: NSRect) {
        guard selectionHighlightStyle != .none else { return }
        accent.setFill()
        // The fill stays inside the row, so a lone row never touches the panel's edges.
        NSBezierPath(roundedRect: bounds.insetBy(dx: 6, dy: 3), xRadius: 5, yRadius: 5).fill()
    }

    override var isEmphasized: Bool {
        get { true }
        set {}
    }
}
