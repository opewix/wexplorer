import AppKit

/// Адресная строка: «Адрес» + значок места + поле с автодополнением + список мест + «Переход».
final class AddressBarView: LunaView, NSTextFieldDelegate {
    var onSubmit: ((String) -> Void)?
    var onCancel: (() -> Void)?
    var menuProvider: (() -> NSMenu)?
    var onCopyPath: (() -> Void)?
    var canCopyPath = true { didSet { copyPath.isEnabled = canCopyPath } }

    let field = NSTextField()
    private let iconView = NSImageView()
    private let box = LunaView()
    private let dropdown = LunaButton(title: tr(.placesList), symbol: "chevron.down", style: .iconOnly, imageSide: 9)
    private let go = LunaButton(title: tr(.go), symbol: nil,
                                style: .horizontal, imageSide: 16)
    private let copyPath = LunaButton(title: tr(.copyPath), symbol: nil, style: .iconOnly, imageSide: 16)
    private var displayed = ""
    /// Длина текста, набранного пользователем (без подставленного автодополнения).
    private var typedLength = 0

    override init(frame: NSRect) {
        super.init(frame: frame)

        let label = NSTextField(labelWithString: tr(.address))
        label.font = Luna.font
        label.textColor = NSColor(hex: 0x6D6B60)

        field.font = Luna.font
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.delegate = self
        field.cell?.usesSingleLineMode = true
        field.cell?.wraps = false
        field.cell?.isScrollable = true

        iconView.imageScaling = .scaleProportionallyDown

        box.wantsLayer = true
        box.layer?.backgroundColor = NSColor.white.cgColor
        box.layer?.borderColor = Luna.border.cgColor
        box.layer?.borderWidth = 1

        go.image = XPIcons.image(.go, size: 16)
        copyPath.image = XPIcons.image(.copyPath, size: 16)
        copyPath.onClick = { [weak self] _ in self?.onCopyPath?() }
        dropdown.onClick = { [weak self] _ in self?.showMenu() }
        go.onClick = { [weak self] _ in
            guard let self else { return }
            self.onSubmit?(self.field.stringValue)
        }

        for v in [label, box, go, copyPath] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
        }
        for v in [iconView, field, dropdown] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            box.addSubview(v)
        }

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            box.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 6),
            box.centerYAnchor.constraint(equalTo: centerYAnchor),
            box.heightAnchor.constraint(equalToConstant: 20),
            go.leadingAnchor.constraint(equalTo: box.trailingAnchor, constant: 6),
            go.trailingAnchor.constraint(equalTo: copyPath.leadingAnchor, constant: -2),
            copyPath.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            copyPath.centerYAnchor.constraint(equalTo: centerYAnchor),
            copyPath.heightAnchor.constraint(equalToConstant: 22),
            copyPath.widthAnchor.constraint(equalToConstant: 26),
            go.centerYAnchor.constraint(equalTo: centerYAnchor),
            go.heightAnchor.constraint(equalToConstant: 22),

            iconView.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 3),
            iconView.centerYAnchor.constraint(equalTo: box.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),
            field.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 3),
            field.trailingAnchor.constraint(equalTo: dropdown.leadingAnchor, constant: -2),
            field.centerYAnchor.constraint(equalTo: box.centerYAnchor),
            dropdown.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -1),
            dropdown.topAnchor.constraint(equalTo: box.topAnchor, constant: 1),
            dropdown.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -1),
            dropdown.widthAnchor.constraint(equalToConstant: 16),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        Luna.face.setFill()
        bounds.fill()
    }

    func show(_ location: Location) {
        displayed = location.addressText
        field.stringValue = displayed
        iconView.image = location.icon
    }

    func focus() {
        window?.makeFirstResponder(field)
        field.currentEditor()?.selectAll(nil)
    }

    private func showMenu() {
        guard let menu = menuProvider?() else { return }
        menu.minimumWidth = box.bounds.width
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: box.bounds.maxY + 2), in: box)
    }

    // MARK: NSTextFieldDelegate

    func controlTextDidBeginEditing(_ obj: Notification) {
        typedLength = (field.stringValue as NSString).length
    }

    /// Автодополнение как в XP: остаток имени подставляется выделенным, набор текста его заменяет.
    func controlTextDidChange(_ obj: Notification) {
        guard let editor = field.currentEditor() else { return }
        let text = field.stringValue
        let length = (text as NSString).length
        defer { typedLength = length }
        guard length > typedLength, editor.selectedRange.location == length,
              let completion = Self.completion(for: text) else { return }
        field.stringValue = text + completion
        editor.selectedRange = NSRange(location: length, length: (completion as NSString).length)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.insertNewline(_:)) {
            onSubmit?(field.stringValue)
            return true
        }
        if selector == #selector(NSResponder.cancelOperation(_:)) {
            field.stringValue = displayed
            onCancel?()
            return true
        }
        return false
    }

    static func completion(for text: String) -> String? {
        guard text.hasPrefix("/") || text.hasPrefix("~"), !text.hasSuffix("/") else { return nil }
        let expanded = (text as NSString).expandingTildeInPath as NSString
        let dir = expanded.deletingLastPathComponent
        let prefix = expanded.lastPathComponent.lowercased()
        guard !prefix.isEmpty, let names = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return nil }
        let match = names
            .filter { (!$0.hasPrefix(".") || prefix.hasPrefix(".")) && $0.count > prefix.count }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            .first { $0.lowercased().hasPrefix(prefix) }
        guard let match else { return nil }
        return String(match.dropFirst(prefix.count))
    }
}
