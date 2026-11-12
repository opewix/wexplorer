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
    /// Бросили то, что тянули правой кнопкой: спросить меню, что сделать.
    func browserRightDrop(_ urls: [URL], into folder: URL, suggested: NSDragOperation)
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
    private var typedPrefix = ""
    private var lastTypeTime: TimeInterval = 0

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
        NotificationCenter.default.addObserver(
            self, selector: #selector(cutFilesDidChange), name: CutFiles.didChange, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(extensionsDidChange), name: FileExtensions.didChange, object: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setUpTable() {
        table.browser = self
        table.dataSource = self
        table.delegate = self
        table.style = .plain
        table.rowHeight = Theme.isWin10 ? Win10.rowHeight : 18
        table.intercellSpacing = NSSize(width: 0, height: 0)
        table.allowsMultipleSelection = true
        // Поиск по первым буквам свой (`typeSelect`) — один на все виды.
        table.allowsTypeSelect = false
        table.allowsEmptySelection = true
        table.backgroundColor = .white
        table.gridStyleMask = []
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.target = self
        table.doubleAction = #selector(tableDoubleClicked(_:))
        let widths: [SortKey: CGFloat] = Theme.isWin10
            ? [.name: 260, .size: 90, .type: 150, .modified: 140]
            : [.name: 260, .size: 80, .type: 170, .modified: 120]
        // В Windows 10 колонки идут в другом порядке: Имя, Дата изменения, Тип, Размер.
        let order: [SortKey] = Theme.isWin10 ? [.name, .modified, .type, .size] : SortKey.allCases
        if Theme.isWin10 {
            table.headerView = Win10HeaderView(frame: NSRect(x: 0, y: 0, width: 100, height: 25))
            table.cornerView = nil
        }
        for key in order {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(key.columnID))
            let header = PaddedHeaderCell(textCell: key.title)
            header.font = column.headerCell.font
            header.alignment = Theme.isWin10 && key == .size ? .right : .left
            column.headerCell = header
            column.width = widths[key] ?? 100
            column.minWidth = 40
            column.sortDescriptorPrototype = NSSortDescriptor(key: key.columnID, ascending: true)
            table.addTableColumn(column)
        }
        table.registerForDraggedTypes([.fileURL])
        table.setDraggingSourceOperationMask([.copy, .move], forLocal: true)
        table.setDraggingSourceOperationMask([.copy, .move], forLocal: false)
        table.hover.install(on: table)
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
            flow.itemSize = Theme.isWin10 ? NSSize(width: 90, height: 80) : NSSize(width: 84, height: 72)
            flow.minimumInteritemSpacing = 2
            flow.minimumLineSpacing = 8
        case .list:
            flow.itemSize = NSSize(width: 220, height: Theme.isWin10 ? Win10.rowHeight : 18)
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

    /// Расширения спрятали или показали — имена перерисовываются, выделение остаётся.
    @objc private func extensionsDidChange() {
        guard !isRenaming else { return }
        let selected = selectedItems.map(\.url)
        table.reloadData()
        collection.reloadData()
        select(urls: selected)
    }

    /// Буфер обмена сменился — перерисовать значки видимых файлов (вырезанные бледнеют).
    @objc private func cutFilesDidChange() {
        let nameColumn = table.column(withIdentifier: NSUserInterfaceItemIdentifier(SortKey.name.columnID))
        if nameColumn >= 0 {
            let rows = table.rows(in: table.visibleRect)
            for row in rows.lowerBound..<rows.upperBound where row < items.count {
                (table.view(atColumn: nameColumn, row: row, makeIfNecessary: false) as? NameCellView)?
                    .setCut(CutFiles.contains(items[row].url))
            }
        }
        for indexPath in collection.indexPathsForVisibleItems() where indexPath.item < items.count {
            (collection.item(at: indexPath) as? IconItem)?.setCut(CutFiles.contains(items[indexPath.item].url))
        }
    }

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
        // Спрятанное расширение не показывается и при переименовании — выделяется всё имя.
        let item = items[index]
        let name = item.displayName as NSString
        let ext = name.pathExtension as NSString
        let length = item.isDirectory || item.hiddenExtension != nil || ext.length == 0
            ? name.length : name.length - ext.length - 1
        field.currentEditor()?.selectedRange = NSRange(location: 0, length: length)
    }

    private func renameWithDialog(_ index: Int) {
        let item = items[index]
        let alert = NSAlert()
        alert.messageText = tr(.renameTitle)
        alert.informativeText = tr(.renamePrompt, item.displayName)
        let field = NSTextField(string: item.displayName)
        field.frame = NSRect(x: 0, y: 0, width: 280, height: 22)
        alert.accessoryView = field
        alert.addButton(withTitle: tr(.ok))
        alert.addButton(withTitle: tr(.cancel))
        alert.window.initialFirstResponder = field
        let ok = alert.runModal() == .alertFirstButtonReturn
        delegate?.browserRename(index, to: ok ? item.fullName(fromEdited: field.stringValue) : nil)
    }

    // MARK: Для FileTableView / FileCollectionView

    func handleKey(_ event: NSEvent) -> Bool {
        delegate?.browserHandleKey(event) == true || typeSelect(event)
    }

    // MARK: Поиск по первым буквам

    /// Как в Проводнике: набранные подряд (с паузой меньше секунды) буквы выделяют первый объект,
    /// имя которого так начинается; одна и та же буква несколько раз — перебор объектов на эту букву.
    /// Работает во всех видах и сравнивает с именем, как оно показано (без спрятанного расширения).
    private func typeSelect(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
              let chars = event.characters, !chars.isEmpty, !items.isEmpty,
              chars.unicodeScalars.allSatisfy({ $0.value >= 0x20 && $0.value != 0x7f && !(0xF700...0xF8FF).contains($0.value) })
        else { return false }
        if event.timestamp - lastTypeTime > 1 { typedPrefix = "" }
        lastTypeTime = event.timestamp
        if typedPrefix.isEmpty && chars == " " { return false }
        typedPrefix += chars
        let lowered = typedPrefix.lowercased()
        let repeated = lowered.count > 1 && Set(lowered).count == 1
        let prefix = repeated ? String(typedPrefix.prefix(1)) : typedPrefix
        // Первая буква и повтор ищут со следующего объекта, продолжение слова — с текущего.
        let fromNext = typedPrefix.count == 1 || repeated
        let start = selectedIndexes.first.map { fromNext ? $0 + 1 : $0 } ?? 0
        let order = Array(min(start, items.count)..<items.count) + Array(0..<min(start, items.count))
        if let match = order.first(where: {
            items[$0].displayName.range(of: prefix, options: [.caseInsensitive, .anchored]) != nil
        }) {
            select(IndexSet(integer: match))
        }
        return true
    }

    // MARK: Перетаскивание правой кнопкой

    /// После нажатия правой кнопки на объекте: отпустили на месте — nil (будет контекстное меню),
    /// повели — событие сдвига, с которого начинается перетаскивание.
    static func waitForRightDrag(in window: NSWindow?, from down: NSEvent) -> NSEvent? {
        let start = down.locationInWindow
        while let event = window?.nextEvent(matching: [.rightMouseDragged, .rightMouseUp]) {
            if event.type == .rightMouseUp { return nil }
            if hypot(event.locationInWindow.x - start.x, event.locationInWindow.y - start.y) > 4 { return event }
        }
        return nil
    }

    /// Тянет выделенные объекты правой кнопкой. В данных — отметка `DropRules.rightDragMarker`:
    /// по ней место, куда бросили, показывает меню «Копировать / Переместить / Создать ярлыки».
    func beginRightDrag(with event: NSEvent, in view: NSView) {
        let dragged = selectedItems.filter { !$0.isVolume }
        guard !dragged.isEmpty else { return }
        let point = view.convert(event.locationInWindow, from: nil)
        let step: CGFloat = view.isFlipped ? 6 : -6
        let items = dragged.enumerated().map { index, item -> NSDraggingItem in
            let data = NSPasteboardItem()
            data.setString(item.url.absoluteString, forType: .fileURL)
            data.setData(Data(), forType: DropRules.rightDragMarker)
            let dragging = NSDraggingItem(pasteboardWriter: data)
            let offset = CGFloat(min(index, 4)) * step
            dragging.setDraggingFrame(NSRect(x: point.x - 16 + abs(offset), y: point.y - 16 + offset, width: 32, height: 32),
                                      contents: item.icon)
            return dragging
        }
        view.beginDraggingSession(with: items, event: event, source: self)
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
        if DropRules.isRightDrag(info) {
            delegate?.browserRightDrop(DropRules.urls(info), into: folder, suggested: operation)
            return true
        }
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
            cell.configure(name: item.displayName, icon: item.icon, isCut: CutFiles.contains(item.url))
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
        var newName = field.stringValue
        if index < items.count {
            newName = items[index].fullName(fromEdited: newName)
            field.stringValue = items[index].displayName
        }
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
    let hover = RowHover()

    override func reloadData() {
        hover.reset()
        super.reloadData()
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        hover.track(self, event: event)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        hover.track(self, event: nil)
    }

    override func keyDown(with event: NSEvent) {
        if browser?.handleKey(event) == true { return }
        super.keyDown(with: event)
    }

    /// Рамка выделения: NSTableView при протягивании по пустому месту выделяет строки, но рамку
    /// не рисует. Рамку начинает нажатие мимо строк, а в XP ещё и мимо колонки «Имя» — там в
    /// «Таблице» к файлу относится только имя. Простой щелчок отдаём таблице как был.
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard event.clickCount == 1, browser?.isRenaming == false, startsMarquee(at: point) else {
            super.mouseDown(with: event)
            return
        }
        window?.makeFirstResponder(self)
        let result = Marquee.track(in: self, from: event, selected: selectedRowIndexes, items: { rect in
            let range = self.rows(in: rect)
            return IndexSet(integersIn: range.location..<(range.location + range.length))
        }, apply: { selection in
            self.selectRowIndexes(selection, byExtendingSelection: false)
        })
        if case .click(let up) = result {
            window?.postEvent(up, atStart: true)
            super.mouseDown(with: event)
        }
    }

    private func startsMarquee(at point: NSPoint) -> Bool {
        guard row(at: point) >= 0 else { return true }
        guard !Theme.isWin10 else { return false }
        let column = self.column(at: point)
        return column < 0 || tableColumns[column].identifier.rawValue != SortKey.name.columnID
    }

    override func otherMouseDown(with event: NSEvent) {
        browser?.openInNewWindow(row(at: convert(event.locationInWindow, from: nil)))
    }

    /// Правая кнопка на строке: повели — перетаскивание с меню в конце, отпустили — контекстное меню.
    override func rightMouseDown(with event: NSEvent) {
        let row = self.row(at: convert(event.locationInWindow, from: nil))
        guard row >= 0, let browser, !browser.isRenaming,
              let drag = FileBrowserView.waitForRightDrag(in: window, from: event) else {
            super.rightMouseDown(with: event)
            return
        }
        if !selectedRowIndexes.contains(row) { selectRowIndexes([row], byExtendingSelection: false) }
        browser.beginRightDrag(with: drag, in: self)
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

    /// Рамку по пустому месту ведём сами, как в таблице, — чтобы во всех видах она была одна.
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if event.clickCount == 1, indexPathForItem(at: point) == nil {
            window?.makeFirstResponder(self)
            let selected = IndexSet(selectionIndexPaths.map(\.item))
            let result = Marquee.track(in: self, from: event, selected: selected, items: { rect in
                let hit = (self.collectionViewLayout?.layoutAttributesForElements(in: rect) ?? [])
                    .filter { $0.representedElementCategory == .item && $0.frame.intersects(rect) }
                    .compactMap { $0.indexPath?.item }
                return IndexSet(hit)
            }, apply: { selection in
                self.selectionIndexPaths = Set(selection.map { IndexPath(item: $0, section: 0) })
                self.browser?.notifySelection()
            })
            if case .click = result, event.modifierFlags.intersection([.command, .shift]).isEmpty {
                selectionIndexPaths = []
                browser?.notifySelection()
            }
            return
        }
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

    /// Правая кнопка на значке: повели — перетаскивание с меню в конце, отпустили — контекстное меню.
    override func rightMouseDown(with event: NSEvent) {
        guard let indexPath = indexPathForItem(at: convert(event.locationInWindow, from: nil)), let browser,
              let drag = FileBrowserView.waitForRightDrag(in: window, from: event) else {
            super.rightMouseDown(with: event)
            return
        }
        if !selectionIndexPaths.contains(indexPath) {
            selectionIndexPaths = [indexPath]
            browser.notifySelection()
        }
        browser.beginRightDrag(with: drag, in: self)
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

// MARK: - Источник перетаскивания правой кнопкой

extension FileBrowserView: NSDraggingSource {
    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        [.copy, .move]
    }
}
