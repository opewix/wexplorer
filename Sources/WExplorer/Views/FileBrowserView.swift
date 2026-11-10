import AppKit
import QuickLookThumbnailing

protocol FileBrowserDelegate: AnyObject {
    var browserCurrentFolder: URL? { get }
    func browserSelectionDidChange()
    func browserOpen(_ indexes: IndexSet)
    /// Cmd+двойной щелчок или щелчок колёсиком — открыть папку в новом окне.
    func browserOpenInNewWindow(_ index: Int)
    func browserHandleKey(_ event: NSEvent) -> Bool
    func browserContextMenu(onItem: Bool) -> NSMenu?
    /// name == nil — переименование отменено.
    func browserRename(_ index: Int, to name: String?)
    func browserSortDidChange(_ key: SortKey, ascending: Bool)
    func browserDrop(_ urls: [URL], into folder: URL, copy: Bool) -> Bool
}

/// Список файлов: «Таблица» — на NSTableView, остальные виды — на NSCollectionView.
final class FileBrowserView: LunaView {
    weak var delegate: FileBrowserDelegate?
    private(set) var items: [FileItem] = []

    var mode: ViewMode = .details {
        willSet { carriedSelection = selectedItems.map(\.url) }
        didSet { applyMode() }
    }

    var isRenaming: Bool { renamingIndex != nil }
    var activeView: NSView { mode == .details ? table : collection }

    let table = FileTableView()
    let collection = FileCollectionView()
    private let tableScroll = NSScrollView()
    private let collectionScroll = NSScrollView()
    private let flow = LeftAlignedFlowLayout()
    private let thumbnails = NSCache<NSURL, NSImage>()
    private var requestedThumbnails = Set<URL>()
    private var carriedSelection: [URL] = []
    private var renamingIndex: Int?
    private var renameCancelled = false
    private var updatingSort = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setUpTable()
        setUpCollection()
        for scroll in [tableScroll, collectionScroll] {
            scroll.translatesAutoresizingMaskIntoConstraints = false
            scroll.borderType = .noBorder
            scroll.autohidesScrollers = true
            addSubview(scroll)
            NSLayoutConstraint.activate([
                scroll.topAnchor.constraint(equalTo: topAnchor),
                scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
                scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
                scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            ])
        }
        applyMode()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setUpTable() {
        table.browser = self
        table.dataSource = self
        table.delegate = self
        table.style = .plain
        table.rowHeight = 18
        table.intercellSpacing = NSSize(width: 0, height: 0)
        table.allowsMultipleSelection = true
        table.allowsEmptySelection = true
        table.backgroundColor = .white
        table.gridStyleMask = []
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.target = self
        table.doubleAction = #selector(tableDoubleClicked(_:))
        let widths: [SortKey: CGFloat] = [.name: 260, .size: 80, .type: 170, .modified: 120]
        for key in SortKey.allCases {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(key.columnID))
            let header = PaddedHeaderCell(textCell: key.title)
            header.font = column.headerCell.font
            header.alignment = .left
            column.headerCell = header
            column.width = widths[key] ?? 100
            column.minWidth = 40
            column.sortDescriptorPrototype = NSSortDescriptor(key: key.columnID, ascending: true)
            table.addTableColumn(column)
        }
        table.registerForDraggedTypes([.fileURL])
        table.setDraggingSourceOperationMask([.copy, .move], forLocal: true)
        table.setDraggingSourceOperationMask([.copy, .move], forLocal: false)
        tableScroll.documentView = table
        tableScroll.hasVerticalScroller = true
        tableScroll.hasHorizontalScroller = true
    }

    private func setUpCollection() {
        collection.browser = self
        collection.collectionViewLayout = flow
        collection.dataSource = self
        collection.delegate = self
        collection.isSelectable = true
        collection.allowsMultipleSelection = true
        collection.allowsEmptySelection = true
        collection.backgroundColors = [.white]
        collection.register(IconItem.self, forItemWithIdentifier: IconItem.id)
        collection.registerForDraggedTypes([.fileURL])
        collection.setDraggingSourceOperationMask([.copy, .move], forLocal: true)
        collection.setDraggingSourceOperationMask([.copy, .move], forLocal: false)
        collectionScroll.documentView = collection
    }

    private func applyMode() {
        let isTable = mode == .details
        tableScroll.isHidden = !isTable
        collectionScroll.isHidden = isTable
        configureFlow()
        table.reloadData()
        collection.reloadData()
        select(urls: carriedSelection)
        carriedSelection = []
        if let responder = window?.firstResponder, responder === table || responder === collection {
            window?.makeFirstResponder(activeView)
        }
    }

    private func configureFlow() {
        flow.scrollDirection = mode == .list ? .horizontal : .vertical
        flow.sectionInset = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        switch mode {
        case .thumbnails:
            flow.itemSize = NSSize(width: 120, height: 140)
            flow.minimumInteritemSpacing = 8
            flow.minimumLineSpacing = 8
        case .tiles:
            flow.itemSize = NSSize(width: 250, height: 58)
            flow.minimumInteritemSpacing = 6
            flow.minimumLineSpacing = 4
        case .icons:
            flow.itemSize = NSSize(width: 84, height: 72)
            flow.minimumInteritemSpacing = 2
            flow.minimumLineSpacing = 8
        case .list:
            flow.itemSize = NSSize(width: 220, height: 18)
            flow.minimumInteritemSpacing = 0
            flow.minimumLineSpacing = 16
        case .details:
            break
        }
        collectionScroll.hasVerticalScroller = mode != .list
        collectionScroll.hasHorizontalScroller = mode == .list
        flow.invalidateLayout()
    }

    // MARK: Данные и выделение

    func setItems(_ newItems: [FileItem], selecting urls: [URL]) {
        renamingIndex = nil
        items = newItems
        table.reloadData()
        collection.reloadData()
        select(urls: urls)
    }

    var selectedIndexes: IndexSet {
        let raw = mode == .details ? table.selectedRowIndexes : IndexSet(collection.selectionIndexPaths.map(\.item))
        return raw.filteredIndexSet { $0 < items.count }
    }

    var selectedItems: [FileItem] { selectedIndexes.map { items[$0] } }

    func select(urls: [URL]) {
        let paths = Set(urls.map { $0.standardizedFileURL.path })
        select(IndexSet(items.indices.filter { paths.contains(items[$0].url.standardizedFileURL.path) }))
    }

    func select(_ indexes: IndexSet) {
        if mode == .details {
            table.selectRowIndexes(indexes, byExtendingSelection: false)
            if let first = indexes.first { table.scrollRowToVisible(first) }
        } else {
            collection.selectionIndexPaths = Set(indexes.map { IndexPath(item: $0, section: 0) })
            if let first = indexes.first {
                collection.scrollToItems(at: [IndexPath(item: first, section: 0)],
                                         scrollPosition: mode == .list ? .nearestVerticalEdge : .nearestHorizontalEdge)
            }
            delegate?.browserSelectionDidChange()
        }
    }

    func selectAllItems() {
        select(IndexSet(integersIn: 0..<items.count))
    }

    func invertSelection() {
        let current = selectedIndexes
        select(IndexSet(integersIn: 0..<items.count).subtracting(current))
    }

    func scrollToTop() {
        table.scroll(.zero)
        collection.scroll(.zero)
    }

    func setSortIndicator(_ key: SortKey, ascending: Bool) {
        updatingSort = true
        table.sortDescriptors = [NSSortDescriptor(key: key.columnID, ascending: ascending)]
        updatingSort = false
    }

    // MARK: Переименование

    func beginRename(at index: Int) {
        guard index < items.count else { return }
        select(IndexSet(integer: index))
        guard mode == .details else {
            renameWithDialog(index)
            return
        }
        table.scrollRowToVisible(index)
        guard let cell = table.view(atColumn: 0, row: index, makeIfNecessary: true) as? NameCellView,
              let field = cell.textField else { return }
        renamingIndex = index
        renameCancelled = false
        cell.beginEditing()
        field.delegate = self
        window?.makeFirstResponder(field)
        let name = items[index].name as NSString
        let ext = name.pathExtension as NSString
        let length = items[index].isDirectory || ext.length == 0 ? name.length : name.length - ext.length - 1
        field.currentEditor()?.selectedRange = NSRange(location: 0, length: length)
    }

    private func renameWithDialog(_ index: Int) {
        let item = items[index]
        let alert = NSAlert()
        alert.messageText = tr(.renameTitle)
        alert.informativeText = tr(.renamePrompt, item.name)
        let field = NSTextField(string: item.name)
        field.frame = NSRect(x: 0, y: 0, width: 280, height: 22)
        alert.accessoryView = field
        alert.addButton(withTitle: tr(.ok))
        alert.addButton(withTitle: tr(.cancel))
        alert.window.initialFirstResponder = field
        let ok = alert.runModal() == .alertFirstButtonReturn
        delegate?.browserRename(index, to: ok ? field.stringValue : nil)
    }

    // MARK: Для FileTableView / FileCollectionView

    func handleKey(_ event: NSEvent) -> Bool {
        delegate?.browserHandleKey(event) ?? false
    }

    func contextMenu(onItem: Bool) -> NSMenu? {
        delegate?.browserContextMenu(onItem: onItem)
    }

    func open(_ indexes: IndexSet) {
        guard !indexes.isEmpty else { return }
        delegate?.browserOpen(indexes)
    }

    func notifySelection() {
        delegate?.browserSelectionDidChange()
    }

    @objc private func tableDoubleClicked(_ sender: Any?) {
        let row = table.clickedRow
        guard row >= 0 else { return }
        if NSApp.currentEvent?.modifierFlags.contains(.command) == true {
            openInNewWindow(row)
            return
        }
        open(table.selectedRowIndexes.contains(row) ? table.selectedRowIndexes : IndexSet(integer: row))
    }

    func openInNewWindow(_ index: Int) {
        guard index >= 0, index < items.count else { return }
        delegate?.browserOpenInNewWindow(index)
    }

    // MARK: Эскизы

    private func image(for item: FileItem) -> NSImage {
        guard mode == .thumbnails, !item.isDirectory else { return item.icon }
        if let cached = thumbnails.object(forKey: item.url as NSURL) { return cached }
        requestThumbnail(item.url)
        return item.icon
    }

    private func requestThumbnail(_ url: URL) {
        guard !requestedThumbnails.contains(url) else { return }
        requestedThumbnails.insert(url)
        let request = QLThumbnailGenerator.Request(
            fileAt: url, size: CGSize(width: 96, height: 96),
            scale: window?.backingScaleFactor ?? 2, representationTypes: .thumbnail)
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak self] representation, _ in
            guard let image = representation?.nsImage else { return }
            DispatchQueue.main.async {
                guard let self else { return }
                self.thumbnails.setObject(image, forKey: url as NSURL)
                if let index = self.items.firstIndex(where: { $0.url == url }),
                   let cell = self.collection.item(at: IndexPath(item: index, section: 0)) as? IconItem {
                    cell.setImage(image)
                }
            }
        }
    }

    // MARK: Перетаскивание

    fileprivate func performDrop(_ info: NSDraggingInfo, into folder: URL) -> Bool {
        let operation = DropRules.operation(info, into: folder)
        guard !operation.isEmpty else { return false }
        return delegate?.browserDrop(DropRules.urls(info), into: folder, copy: operation == .copy) ?? false
    }
}

// MARK: - Таблица

extension FileBrowserView: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int { items.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let column = tableColumn, row < items.count else { return nil }
        let item = items[row]
        if column.identifier.rawValue == SortKey.name.columnID {
            let cell = tableView.makeView(withIdentifier: NameCellView.id, owner: self) as? NameCellView ?? NameCellView(leading: 6)
            cell.configure(name: item.name, icon: item.icon)
            return cell
        }
        let cell = tableView.makeView(withIdentifier: TextCellView.id, owner: self) as? TextCellView ?? TextCellView()
        switch SortKey(columnID: column.identifier.rawValue) {
        case .size:
            let text = item.isVolume ? item.size.map(Format.size) : (item.isDirectory ? nil : item.size.map(Format.kilobytes))
            cell.configure(text ?? "", alignment: .right)
        case .type:
            cell.configure(item.typeName, alignment: .left)
        case .modified:
            cell.configure(Format.date(item.modified), alignment: .left)
        default:
            cell.configure("", alignment: .left)
        }
        return cell
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        LunaRowView()
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        delegate?.browserSelectionDidChange()
    }

    func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        guard !updatingSort, let descriptor = tableView.sortDescriptors.first,
              let key = descriptor.key.flatMap(SortKey.init(columnID:)) else { return }
        delegate?.browserSortDidChange(key, ascending: descriptor.ascending)
    }

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        guard row < items.count, !isRenaming else { return nil }
        return items[row].url as NSURL
    }

    func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int,
                   proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
        if dropOperation == .on, row >= 0, row < items.count, items[row].isDirectory {
            let operation = DropRules.operation(info, into: items[row].url)
            if !operation.isEmpty { return operation }
        }
        guard let folder = delegate?.browserCurrentFolder else { return [] }
        tableView.setDropRow(-1, dropOperation: .on)
        return DropRules.operation(info, into: folder)
    }

    func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int,
                   dropOperation: NSTableView.DropOperation) -> Bool {
        if dropOperation == .on, row >= 0, row < items.count, items[row].isDirectory {
            return performDrop(info, into: items[row].url)
        }
        guard let folder = delegate?.browserCurrentFolder else { return false }
        return performDrop(info, into: folder)
    }
}

// MARK: - Коллекция

extension FileBrowserView: NSCollectionViewDataSource, NSCollectionViewDelegate {
    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        mode == .details ? 0 : items.count
    }

    func collectionView(_ collectionView: NSCollectionView,
                        itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let cell = collectionView.makeItem(withIdentifier: IconItem.id, for: indexPath) as! IconItem
        let item = items[indexPath.item]
        cell.configure(item, mode: mode, image: image(for: item))
        return cell
    }

    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        delegate?.browserSelectionDidChange()
    }

    func collectionView(_ collectionView: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>) {
        delegate?.browserSelectionDidChange()
    }

    func collectionView(_ collectionView: NSCollectionView, canDragItemsAt indexPaths: Set<IndexPath>,
                        with event: NSEvent) -> Bool { true }

    func collectionView(_ collectionView: NSCollectionView,
                        pasteboardWriterForItemAt indexPath: IndexPath) -> NSPasteboardWriting? {
        indexPath.item < items.count ? items[indexPath.item].url as NSURL : nil
    }

    func collectionView(_ collectionView: NSCollectionView, validateDrop draggingInfo: NSDraggingInfo,
                        proposedIndexPath proposedDropIndexPath: AutoreleasingUnsafeMutablePointer<NSIndexPath>,
                        dropOperation proposedDropOperation: UnsafeMutablePointer<NSCollectionView.DropOperation>)
        -> NSDragOperation {
        let index = (proposedDropIndexPath.pointee as IndexPath).item
        if proposedDropOperation.pointee == .on, index < items.count, items[index].isDirectory {
            let operation = DropRules.operation(draggingInfo, into: items[index].url)
            if !operation.isEmpty { return operation }
        }
        guard let folder = delegate?.browserCurrentFolder else { return [] }
        proposedDropOperation.pointee = .before
        proposedDropIndexPath.pointee = IndexPath(item: items.count, section: 0) as NSIndexPath
        return DropRules.operation(draggingInfo, into: folder)
    }

    func collectionView(_ collectionView: NSCollectionView, acceptDrop draggingInfo: NSDraggingInfo,
                        indexPath: IndexPath, dropOperation: NSCollectionView.DropOperation) -> Bool {
        if dropOperation == .on, indexPath.item < items.count, items[indexPath.item].isDirectory {
            return performDrop(draggingInfo, into: items[indexPath.item].url)
        }
        guard let folder = delegate?.browserCurrentFolder else { return false }
        return performDrop(draggingInfo, into: folder)
    }
}

// MARK: - Переименование на месте

extension FileBrowserView: NSTextFieldDelegate {
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard renamingIndex != nil, commandSelector == #selector(NSResponder.cancelOperation(_:)) else { return false }
        renameCancelled = true
        window?.makeFirstResponder(table)
        return true
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField, let index = renamingIndex else { return }
        renamingIndex = nil
        (field.superview as? NameCellView)?.endEditing()
        let newName = field.stringValue
        if index < items.count { field.stringValue = items[index].name }
        let cancelled = renameCancelled
        let movement = obj.userInfo?["NSTextMovement"] as? Int
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if cancelled || movement == NSTextMovement.return.rawValue {
                self.window?.makeFirstResponder(self.table)
            }
            self.delegate?.browserRename(index, to: cancelled ? nil : newName)
        }
    }
}

// MARK: - Подклассы с клавиатурой и контекстным меню

final class FileTableView: NSTableView {
    weak var browser: FileBrowserView?

    override func keyDown(with event: NSEvent) {
        if browser?.handleKey(event) == true { return }
        super.keyDown(with: event)
    }

    override func otherMouseDown(with event: NSEvent) {
        browser?.openInNewWindow(row(at: convert(event.locationInWindow, from: nil)))
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let row = self.row(at: convert(event.locationInWindow, from: nil))
        if row >= 0 {
            if !selectedRowIndexes.contains(row) { selectRowIndexes([row], byExtendingSelection: false) }
        } else {
            deselectAll(nil)
        }
        return browser?.contextMenu(onItem: row >= 0)
    }
}

final class FileCollectionView: NSCollectionView {
    weak var browser: FileBrowserView?

    override func keyDown(with event: NSEvent) {
        if browser?.handleKey(event) == true { return }
        super.keyDown(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        if event.clickCount == 2,
           let indexPath = indexPathForItem(at: convert(event.locationInWindow, from: nil)) {
            if event.modifierFlags.contains(.command) {
                browser?.openInNewWindow(indexPath.item)
            } else {
                browser?.open(IndexSet(integer: indexPath.item))
            }
        }
    }

    override func otherMouseDown(with event: NSEvent) {
        if let indexPath = indexPathForItem(at: convert(event.locationInWindow, from: nil)) {
            browser?.openInNewWindow(indexPath.item)
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let indexPath = indexPathForItem(at: convert(event.locationInWindow, from: nil))
        if let indexPath {
            if !selectionIndexPaths.contains(indexPath) { selectionIndexPaths = [indexPath] }
        } else {
            selectionIndexPaths = []
        }
        browser?.notifySelection()
        return browser?.contextMenu(onItem: indexPath != nil)
    }
}

/// Раскладка как в XP: элементы прижаты влево с фиксированным шагом,
/// а не растянуты на всю ширину строки, как в стандартной NSCollectionViewFlowLayout.
final class LeftAlignedFlowLayout: NSCollectionViewFlowLayout {
    override func layoutAttributesForElements(in rect: NSRect) -> [NSCollectionViewLayoutAttributes] {
        let attributes = super.layoutAttributesForElements(in: rect)
            .compactMap { $0.copy() as? NSCollectionViewLayoutAttributes }
        guard scrollDirection == .vertical else { return attributes }
        var x = sectionInset.left
        var rowY = -CGFloat.greatestFiniteMagnitude
        let items = attributes
            .filter { $0.representedElementCategory == .item }
            .sorted { ($0.indexPath ?? IndexPath()) < ($1.indexPath ?? IndexPath()) }
        for item in items {
            if abs(item.frame.minY - rowY) > 1 {
                x = sectionInset.left
                rowY = item.frame.minY
            }
            item.frame.origin.x = x
            x += item.frame.width + minimumInteritemSpacing
        }
        return attributes
    }

    override func layoutAttributesForItem(at indexPath: IndexPath) -> NSCollectionViewLayoutAttributes? {
        guard let base = super.layoutAttributesForItem(at: indexPath) else { return nil }
        guard scrollDirection == .vertical else { return base }
        let row = NSRect(x: 0, y: base.frame.minY, width: collectionViewContentSize.width, height: base.frame.height)
        return layoutAttributesForElements(in: row).first { $0.indexPath == indexPath } ?? base
    }
}
