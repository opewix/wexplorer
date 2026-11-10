import AppKit

/// Узел дерева. XP: Рабочий стол → Мои документы / Мой компьютер → диски / Домашняя папка → папки.
/// Windows 10: невидимый корень → Быстрый доступ (избранное и особые папки) / Этот компьютер.
final class TreeNode {
    enum Kind { case desktop, documents, computer, home, volume, folder, win10Root, quickAccess }

    let kind: Kind
    let url: URL?
    let title: String
    weak var parent: TreeNode?
    private var loaded: [TreeNode]?

    init(kind: Kind, url: URL?, title: String) {
        self.kind = kind
        self.url = url
        self.title = title
    }

    static func desktop() -> TreeNode {
        TreeNode(kind: .desktop, url: Places.desktop, title: tr(.desktop))
    }

    static func win10Root() -> TreeNode {
        TreeNode(kind: .win10Root, url: nil, title: "")
    }

    lazy var icon: NSImage = {
        if kind == .computer { return Places.computerIcon }
        if kind == .quickAccess { return XPIcons.image(.quickAccess, size: 16) }
        return url.map { Places.icon($0) } ?? NSImage()
    }()

    var path: String? { url?.standardizedFileURL.path }
    var isLoaded: Bool { loaded != nil }

    /// nil — узел ничего не открывает («Быстрый доступ» только раскрывается).
    var location: Location? {
        switch kind {
        case .computer: return .computer
        case .win10Root, .quickAccess: return nil
        default: return url.map { .folder($0) }
        }
    }

    func children(showHidden: Bool) -> [TreeNode] {
        if let loaded { return loaded }
        var result: [TreeNode] = []
        switch kind {
        case .desktop:
            result = [
                TreeNode(kind: .documents, url: Places.documents, title: tr(.myDocuments)),
                TreeNode(kind: .computer, url: nil, title: Places.computerTitle),
                TreeNode(kind: .home, url: Places.home, title: Places.displayName(of: Places.home)),
            ] + folderNodes(showHidden)
        case .computer where Theme.isWin10:
            let folders = [Places.home, Places.desktop, Places.documents, Places.downloads, Places.music,
                           Places.pictures, Places.movies]
            result = folders.map { TreeNode(kind: .folder, url: $0, title: Places.displayName(of: $0)) }
                + DirectoryLoader.volumes().map { TreeNode(kind: .volume, url: $0, title: Places.displayName(of: $0)) }
        case .computer:
            result = DirectoryLoader.volumes().map {
                TreeNode(kind: .volume, url: $0, title: Places.displayName(of: $0))
            }
        case .win10Root:
            result = [
                TreeNode(kind: .quickAccess, url: nil, title: tr(.quickAccess)),
                TreeNode(kind: .computer, url: nil, title: Places.computerTitle),
            ]
        case .quickAccess:
            // Избранное — это «закреплённые» папки; за ними стандартные, как в Windows 10.
            var seen = Set<String>()
            let urls = (Favorites.all + [Places.desktop, Places.downloads, Places.documents, Places.pictures])
                .filter { seen.insert($0.standardizedFileURL.path).inserted }
            result = urls.map { TreeNode(kind: .folder, url: $0, title: Places.displayName(of: $0)) }
        default:
            result = folderNodes(showHidden)
        }
        result.forEach { $0.parent = self }
        loaded = result
        return result
    }

    private func folderNodes(_ showHidden: Bool) -> [TreeNode] {
        guard let url else { return [] }
        return DirectoryLoader.subfolders(of: url, showHidden: showHidden).map {
            TreeNode(kind: .folder, url: $0, title: $0.lastPathComponent)
        }
    }
}

/// Дерево папок (режим «Папки»). Подгружает содержимое по мере раскрытия.
final class FolderTreeView: LunaView, NSOutlineViewDataSource, NSOutlineViewDelegate {
    var onSelect: ((Location) -> Void)?
    var onOpenInNewWindow: ((Location) -> Void)?
    var onDrop: (([URL], URL, Bool) -> Bool)?
    /// Контекстное меню папки в дереве.
    var menuProvider: ((Location) -> NSMenu?)?
    var showHidden = false {
        didSet { if oldValue != showHidden { reload() } }
    }

    private let outline = FolderOutlineView()
    private let scroll = NSScrollView()
    private var root = FolderTreeView.makeRoot()
    let hover = RowHover()

    private static func makeRoot() -> TreeNode {
        Theme.isWin10 ? TreeNode.win10Root() : TreeNode.desktop()
    }
    private var programmatic = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("tree"))
        column.resizingMask = .autoresizingMask
        outline.addTableColumn(column)
        outline.outlineTableColumn = column
        outline.headerView = nil
        outline.style = .plain
        outline.rowHeight = Theme.isWin10 ? Win10.rowHeight : 18
        outline.indentationPerLevel = Theme.isWin10 ? 16 : 14
        outline.backgroundColor = .white
        outline.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        outline.dataSource = self
        outline.delegate = self
        outline.onOpenInNewWindow = { [weak self] row in
            guard let node = self?.outline.item(atRow: row) as? TreeNode, let location = node.location else { return }
            self?.onOpenInNewWindow?(location)
        }
        hover.install(on: outline)
        outline.hover = hover
        outline.menuProvider = { [weak self] row in
            guard let node = self?.outline.item(atRow: row) as? TreeNode, let location = node.location else { return nil }
            return self?.menuProvider?(location)
        }
        outline.registerForDraggedTypes([.fileURL])
        outline.setDraggingSourceOperationMask([.copy, .move], forLocal: true)
        outline.setDraggingSourceOperationMask([.copy, .move], forLocal: false)

        scroll.documentView = outline
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: topAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        reload()
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Перечитывает дерево с нуля (после «Обновить» или смены показа скрытых файлов).
    func reload() {
        root = Self.makeRoot()
        hover.reset()
        outline.reloadData()
        if Theme.isWin10 {
            root.children(showHidden: showHidden).forEach { outline.expandItem($0) }
            return
        }
        outline.expandItem(root)
        if let computer = root.children(showHidden: showHidden).first(where: { $0.kind == .computer }) {
            outline.expandItem(computer)
        }
    }

    /// Раскрывает дерево до текущего места и выделяет его.
    func reveal(_ location: Location) {
        programmatic = true
        defer { programmatic = false }
        guard let node = findNode(for: location) else {
            outline.deselectAll(nil)
            return
        }
        var chain: [TreeNode] = []
        var parent = node.parent
        while let p = parent {
            chain.insert(p, at: 0)
            parent = p.parent
        }
        chain.forEach { outline.expandItem($0) }
        let row = outline.row(forItem: node)
        if row >= 0 {
            outline.selectRowIndexes([row], byExtendingSelection: false)
            outline.scrollRowToVisible(row)
        }
    }

    private func findNode(for location: Location) -> TreeNode? {
        let top = root.children(showHidden: showHidden)
        let computer = top.first { $0.kind == .computer }
        switch location {
        case .computer:
            return computer
        case .search:
            return nil
        case .folder(let url):
            let target = url.standardizedFileURL.path
            // В Windows 10 ищем под «Этим компьютером»: «Быстрый доступ» — лишь ярлыки на те же папки.
            let anchors = Theme.isWin10
                ? (computer?.children(showHidden: showHidden) ?? [])
                : [root] + top.filter { $0.kind == .documents || $0.kind == .home }
                    + (computer?.children(showHidden: showHidden) ?? [])
            let matching = anchors.filter { node in
                guard let p = node.path else { return false }
                return target == p || target.hasPrefix(p == "/" ? "/" : p + "/")
            }
            guard var node = matching.max(by: { ($0.path?.count ?? 0) < ($1.path?.count ?? 0) }) else { return nil }
            while let base = node.path, base != target {
                let rest = target.dropFirst(base == "/" ? 1 : base.count + 1)
                guard let component = rest.split(separator: "/").first else { break }
                let expected = (base as NSString).appendingPathComponent(String(component))
                guard let child = node.children(showHidden: showHidden).first(where: { $0.path == expected }) else { break }
                node = child
            }
            return node
        }
    }

    // MARK: NSOutlineViewDataSource

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        // В Windows 10 корень невидим: сверху сразу «Быстрый доступ» и «Этот компьютер».
        guard let node = item as? TreeNode else { return Theme.isWin10 ? root.children(showHidden: showHidden).count : 1 }
        return node.children(showHidden: showHidden).count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        guard let node = item as? TreeNode else {
            return Theme.isWin10 ? root.children(showHidden: showHidden)[index] : root
        }
        return node.children(showHidden: showHidden)[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        guard let node = item as? TreeNode else { return false }
        return node.isLoaded ? !node.children(showHidden: showHidden).isEmpty : true
    }

    // MARK: Перетаскивание

    func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> NSPasteboardWriting? {
        guard let node = item as? TreeNode, node.kind == .folder else { return nil }
        return node.url as NSURL?
    }

    func outlineView(_ outlineView: NSOutlineView, validateDrop info: NSDraggingInfo, proposedItem item: Any?,
                     proposedChildIndex index: Int) -> NSDragOperation {
        guard let node = item as? TreeNode, let url = node.url else { return [] }
        let operation = DropRules.operation(info, into: url)
        if !operation.isEmpty { outlineView.setDropItem(node, dropChildIndex: NSOutlineViewDropOnItemIndex) }
        return operation
    }

    func outlineView(_ outlineView: NSOutlineView, acceptDrop info: NSDraggingInfo, item: Any?, childIndex index: Int) -> Bool {
        guard let node = item as? TreeNode, let url = node.url else { return false }
        let operation = DropRules.operation(info, into: url)
        guard !operation.isEmpty else { return false }
        return onDrop?(DropRules.urls(info), url, operation == .copy) ?? false
    }

    // MARK: NSOutlineViewDelegate

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? TreeNode else { return nil }
        let cell = outlineView.makeView(withIdentifier: NameCellView.id, owner: self) as? NameCellView ?? NameCellView()
        cell.configure(name: node.title, icon: node.icon)
        return cell
    }

    func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
        LunaRowView()
    }

    func outlineViewItemDidExpand(_ notification: Notification) {
        guard let node = notification.userInfo?["NSObject"] as? TreeNode else { return }
        if node.children(showHidden: showHidden).isEmpty { outline.reloadItem(node) }
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard !programmatic, outline.selectedRow >= 0,
              let node = outline.item(atRow: outline.selectedRow) as? TreeNode, let location = node.location else { return }
        onSelect?(location)
    }
}

/// Cmd+щелчок или щелчок колёсиком по папке в дереве открывает её в новом окне.
final class FolderOutlineView: NSOutlineView {
    var onOpenInNewWindow: ((Int) -> Void)?
    var menuProvider: ((Int) -> NSMenu?)?
    weak var hover: RowHover?

    /// Правый щелчок по папке — её меню; выделение при этом не меняется, как в Проводнике.
    override func menu(for event: NSEvent) -> NSMenu? {
        let row = self.row(at: convert(event.locationInWindow, from: nil))
        return row >= 0 ? menuProvider?(row) : nil
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        hover?.track(self, event: event)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        hover?.track(self, event: nil)
    }

    /// Windows 10 рисует вместо треугольников тонкие шевроны › и ⌄.
    override func makeView(withIdentifier identifier: NSUserInterfaceItemIdentifier, owner: Any?) -> NSView? {
        let view = super.makeView(withIdentifier: identifier, owner: owner)
        if Theme.isWin10, identifier == NSOutlineView.disclosureButtonIdentifier, let button = view as? NSButton {
            button.image = Self.chevron(expanded: false)
            button.alternateImage = Self.chevron(expanded: true)
            button.imageScaling = .scaleNone
        }
        return view
    }

    private static func chevron(expanded: Bool) -> NSImage {
        NSImage(size: NSSize(width: 12, height: 12), flipped: true) { _ in
            let path = NSBezierPath()
            if expanded {
                path.move(to: NSPoint(x: 3, y: 4.5)); path.line(to: NSPoint(x: 6, y: 7.5)); path.line(to: NSPoint(x: 9, y: 4.5))
            } else {
                path.move(to: NSPoint(x: 4.5, y: 3)); path.line(to: NSPoint(x: 7.5, y: 6)); path.line(to: NSPoint(x: 4.5, y: 9))
            }
            path.lineWidth = 1.2
            Win10.glyph.setStroke()
            path.stroke()
            return true
        }
    }

    override func mouseDown(with event: NSEvent) {
        let row = self.row(at: convert(event.locationInWindow, from: nil))
        if event.modifierFlags.contains(.command), row >= 0 {
            onOpenInNewWindow?(row)
            return
        }
        super.mouseDown(with: event)
    }

    override func otherMouseDown(with event: NSEvent) {
        let row = self.row(at: convert(event.locationInWindow, from: nil))
        if row >= 0 { onOpenInNewWindow?(row) }
    }
}
