import AppKit

/// Левая панель: «Панель задач», «Папки» или «Поиск».
final class SidebarContainer: LunaView {
    enum Mode { case tasks, folders, search }

    let taskPane = TaskPaneView()
    let folderTree = FolderTreeView()
    let searchPane = SearchPaneView()
    var onClose: (() -> Void)?

    var mode: Mode = .tasks { didSet { apply() } }

    private let header = PaneHeaderView()
    private var headerHeight: NSLayoutConstraint!

    override init(frame: NSRect) {
        super.init(frame: frame)
        header.onClose = { [weak self] in self?.onClose?() }
        for v in [header, taskPane, folderTree, searchPane] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
            v.leadingAnchor.constraint(equalTo: leadingAnchor).isActive = true
            v.trailingAnchor.constraint(equalTo: trailingAnchor).isActive = true
        }
        headerHeight = header.heightAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: topAnchor),
            headerHeight,
        ])
        for v in [taskPane, folderTree, searchPane] as [NSView] {
            v.topAnchor.constraint(equalTo: header.bottomAnchor).isActive = true
            v.bottomAnchor.constraint(equalTo: bottomAnchor).isActive = true
        }
        apply()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func apply() {
        taskPane.isHidden = mode != .tasks
        folderTree.isHidden = mode != .folders
        searchPane.isHidden = mode != .search
        // В Windows 10 левая панель — только область навигации, без заголовка с крестиком.
        let showsHeader = mode != .tasks && !Theme.isWin10
        header.isHidden = !showsHeader
        headerHeight.constant = showsHeader ? 24 : 0
        header.title = mode == .folders ? tr(.folders) : tr(.search)
    }
}

/// Заголовок панели «Папки»/«Поиск» с крестиком закрытия.
final class PaneHeaderView: LunaView {
    var title = "" { didSet { needsDisplay = true } }
    var onClose: (() -> Void)?
    private let close = LunaButton(title: tr(.close), symbol: "xmark", style: .iconOnly, imageSide: 9)

    override init(frame: NSRect) {
        super.init(frame: frame)
        close.onClick = { [weak self] _ in self?.onClose?() }
        close.translatesAutoresizingMaskIntoConstraints = false
        addSubview(close)
        NSLayoutConstraint.activate([
            close.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            close.centerYAnchor.constraint(equalTo: centerYAnchor),
            close.widthAnchor.constraint(equalToConstant: 18),
            close.heightAnchor.constraint(equalToConstant: 18),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        Luna.face.setFill()
        bounds.fill()
        Luna.separator.setFill()
        NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1).fill()
        let attrs: [NSAttributedString.Key: Any] = [.font: Luna.font, .foregroundColor: Luna.text]
        let h = (title as NSString).size(withAttributes: attrs).height
        (title as NSString).draw(at: NSPoint(x: 8, y: (bounds.height - h) / 2), withAttributes: attrs)
    }
}

/// Панель поиска: имя файла и где искать.
final class SearchPaneView: LunaView {
    var onSearch: ((String, Int) -> Void)?

    private let field = NSTextField()
    private let scope = NSPopUpButton()

    static var scopes: [String] { [tr(.searchScopeCurrent), tr(.searchScopeHome), tr(.searchScopeComputer)] }

    override init(frame: NSRect) {
        super.init(frame: frame)

        let title = NSTextField(labelWithString: tr(.searchHeading))
        title.font = Luna.fontBold
        title.textColor = Luna.linkBlue
        let nameLabel = NSTextField(wrappingLabelWithString: tr(.searchNamePrompt))
        nameLabel.font = Luna.font
        field.font = Luna.font
        field.target = self
        field.action = #selector(submit)
        let scopeLabel = NSTextField(labelWithString: tr(.searchWhere))
        scopeLabel.font = Luna.font
        scope.addItems(withTitles: Self.scopes)
        scope.font = Luna.font
        let button = NSButton(title: tr(.searchButton), target: self, action: #selector(submit))

        let stack = NSStackView(views: [title, nameLabel, field, scopeLabel, scope, button])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.setCustomSpacing(12, after: title)
        stack.setCustomSpacing(12, after: scope)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            field.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scope.widthAnchor.constraint(equalTo: stack.widthAnchor),
            nameLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        // Растянутые на всю ширину элементы не должны ни растягивать левую панель, ни мешать её сузить.
        for v in [field, scope, nameLabel] as [NSView] {
            v.setContentHuggingPriority(.init(1), for: .horizontal)
        }
        for v in [title, field, scope, nameLabel, scopeLabel, button] as [NSView] {
            v.setContentCompressionResistancePriority(.init(1), for: .horizontal)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        Luna.groupBody.setFill()
        bounds.fill()
    }

    func focus() {
        window?.makeFirstResponder(field)
    }

    @objc private func submit() {
        let text = field.stringValue.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        onSearch?(text, scope.indexOfSelectedItem)
    }
}
