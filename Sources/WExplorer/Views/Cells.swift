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
        label.font = Luna.font
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

    func configure(name: String, icon: NSImage) {
        endEditing()
        textField?.stringValue = name
        imageView?.image = icon
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
        label.font = Luna.font
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

/// Строка таблицы с выделением XP: синее в активном окне, серое — без фокуса.
final class LunaRowView: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        (isEmphasized ? Luna.selection : Luna.inactiveSelection).setFill()
        bounds.fill()
    }
}

/// Заголовок колонки с дополнительным отступом слева.
final class PaddedHeaderCell: NSTableHeaderCell {
    static let padding: CGFloat = 3

    override func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {
        var frame = cellFrame
        frame.origin.x += Self.padding
        frame.size.width -= Self.padding
        super.drawInterior(withFrame: frame, in: controlView)
    }
}
