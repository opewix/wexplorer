import AppKit

/// Ячейка «значок + имя» для таблицы и дерева. Умеет переходить в режим переименования.
final class NameCellView: NSTableCellView {
    static let id = NSUserInterfaceItemIdentifier("NameCell")

    /// leading — отступ значка от левого края (в таблице больше, чем в дереве).
    init(leading: CGFloat = 3) {
        super.init(frame: .zero)
        identifier = Self.id
        let icon = NSImageView()
        icon.imageScaling = .scaleProportionallyUpOrDown
        let label = NSTextField(labelWithString: "")
        label.font = Theme.font
        label.lineBreakMode = .byTruncatingTail
        label.cell?.usesSingleLineMode = true
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        for v in [icon, label] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
        }
        imageView = icon
        textField = label
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: leading),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 16),
            icon.heightAnchor.constraint(equalToConstant: 16),
            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 4),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -2),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(name: String, icon: NSImage, isCut: Bool = false) {
        endEditing()
        textField?.stringValue = name
        imageView?.image = icon
        setCut(isCut)
    }

    /// Вырезанный файл — бледный значок, подпись как обычно.
    func setCut(_ isCut: Bool) {
        imageView?.alphaValue = isCut ? 0.5 : 1
    }

    func beginEditing() {
        guard let field = textField else { return }
        field.isEditable = true
        field.isBordered = true
        field.drawsBackground = true
        field.backgroundColor = .white
        field.textColor = .black
    }

    func endEditing() {
        guard let field = textField else { return }
        field.isEditable = false
        field.isSelectable = false
        field.isBordered = false
        field.drawsBackground = false
        field.textColor = .labelColor
    }
}

/// Простая текстовая ячейка для колонок «Размер», «Тип», «Изменён».
final class TextCellView: NSTableCellView {
    static let id = NSUserInterfaceItemIdentifier("TextCell")

    init() {
        super.init(frame: .zero)
        identifier = Self.id
        let label = NSTextField(labelWithString: "")
        label.font = Theme.font
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        addSubview(label)
        textField = label
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 7),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(_ text: String, alignment: NSTextAlignment) {
        textField?.stringValue = text
        textField?.alignment = alignment
    }
}

/// Строка таблицы. XP: синее выделение в активном окне, серое — без фокуса.
/// Windows 10: светло-голубое с рамкой, подсветка при наведении, текст остаётся чёрным.
final class LunaRowView: NSTableRowView {
    var isHovered = false {
        didSet { if oldValue != isHovered { needsDisplay = true } }
    }

    override func drawBackground(in dirtyRect: NSRect) {
        super.drawBackground(in: dirtyRect)
        if Theme.isWin10 && isHovered && !isSelected {
            NSBezierPath.win10Box(bounds, fill: Win10.hover, border: nil)
        }
    }

    override func drawSelection(in dirtyRect: NSRect) {
        guard Theme.isWin10 else {
            (isEmphasized ? Luna.selection : Luna.inactiveSelection).setFill()
            bounds.fill()
            return
        }
        if isEmphasized {
            NSBezierPath.win10Box(bounds, fill: Win10.selection, border: Win10.selectionBorder)
        } else {
            NSBezierPath.win10Box(bounds, fill: Win10.inactiveSelection, border: nil)
        }
    }

    override var interiorBackgroundStyle: NSView.BackgroundStyle {
        Theme.isWin10 ? .normal : super.interiorBackgroundStyle
    }
}

/// Заголовок колонки с дополнительным отступом слева. В Windows 10 рисуется плоским:
/// белый фон, серо-синий текст, тонкий разделитель справа и стрелка сортировки сверху.
final class PaddedHeaderCell: NSTableHeaderCell {
    static let padding: CGFloat = 3

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
        guard Theme.isWin10 else {
            super.draw(withFrame: cellFrame, in: controlView)
            return
        }
        NSColor.white.setFill()
        cellFrame.fill()
        Win10.headerSeparator.setFill()
        NSRect(x: cellFrame.maxX - 1, y: cellFrame.minY + 2, width: 1, height: cellFrame.height - 4).fill()
        let style = NSMutableParagraphStyle()
        style.alignment = alignment
        style.lineBreakMode = .byTruncatingTail
        let attrs: [NSAttributedString.Key: Any] = [.font: Win10.font, .foregroundColor: Win10.headerText, .paragraphStyle: style]
        let text = cellFrame.insetBy(dx: 6, dy: 0)
        let h = (stringValue as NSString).size(withAttributes: attrs).height
        (stringValue as NSString).draw(in: NSRect(x: text.minX, y: text.midY - h / 2 + 1, width: text.width, height: h),
                                       withAttributes: attrs)
        if let ascending = sortDirection(in: controlView) {
            let x = cellFrame.midX, y = cellFrame.minY + 3
            let chevron = NSBezierPath()
            chevron.move(to: NSPoint(x: x - 3.5, y: ascending ? y + 3 : y))
            chevron.line(to: NSPoint(x: x, y: ascending ? y : y + 3))
            chevron.line(to: NSPoint(x: x + 3.5, y: ascending ? y + 3 : y))
            chevron.lineWidth = 1
            Win10.glyph.setStroke()
            chevron.stroke()
        }
    }

    override func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {
        var frame = cellFrame
        frame.origin.x += Self.padding
        frame.size.width -= Self.padding
        super.drawInterior(withFrame: frame, in: controlView)
    }

    /// nil — таблица отсортирована не по этой колонке.
    private func sortDirection(in controlView: NSView) -> Bool? {
        guard let table = (controlView as? NSTableHeaderView)?.tableView,
              let column = table.tableColumns.first(where: { $0.headerCell === self }),
              let descriptor = table.sortDescriptors.first, descriptor.key == column.identifier.rawValue
        else { return nil }
        return descriptor.ascending
    }
}

/// Заголовок таблицы Windows 10: белый фон и под колонками, и справа от последней.
final class Win10HeaderView: NSTableHeaderView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill()
        dirtyRect.fill()
        super.draw(dirtyRect)
    }
}

/// Подсветка строки под мышью (Windows 10) для таблицы файлов и дерева папок.
final class RowHover {
    private var row = -1

    func install(on table: NSTableView) {
        guard Theme.isWin10 else { return }
        table.addTrackingArea(NSTrackingArea(
            rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: table))
    }

    /// event == nil — мышь ушла из таблицы.
    func track(_ table: NSTableView, event: NSEvent?) {
        guard Theme.isWin10 else { return }
        let hovered = event.map { table.row(at: table.convert($0.locationInWindow, from: nil)) } ?? -1
        guard hovered != row else { return }
        set(table, row, false)
        row = hovered
        set(table, row, true)
    }

    /// После перезагрузки строки создаются заново, без подсветки.
    func reset() { row = -1 }

    private func set(_ table: NSTableView, _ index: Int, _ on: Bool) {
        guard index >= 0, index < table.numberOfRows else { return }
        (table.rowView(atRow: index, makeIfNecessary: false) as? LunaRowView)?.isHovered = on
    }
}
