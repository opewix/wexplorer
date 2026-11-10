import AppKit

/// Окно проводника: текущее место, история, настройки; связывает все панели между собой.
/// Рамка окна — родная macOS, содержимое — в стиле XP или Windows 10 (`Theme.current`).
final class MainWindowController: NSWindowController, NSWindowDelegate {
    // Панели XP
    let menuBar = MenuBarView()
    let toolbar = ToolbarView()
    let address = AddressBarView()
    // Панели Windows 10
    let ribbon = RibbonView()
    let navBar = NavigationBarView()
    // Общие
    let sidebar = SidebarContainer()
    let browser = FileBrowserView()
    let status = StatusBarView()
    private let split = ThemedSplitView()
    static let navigationPaneHiddenKey = "navigationPaneHidden"

    private(set) var location: Location
    var history = NavigationHistory()
    var settings = Settings.load()
    private(set) var ops: FileOperations!
    private let watcher = DirectoryWatcher()
    private let search = FileSearch()
    private var loadGeneration = 0
    private var scrollToTopOnApply = false
    private var reloadAfterRename = false
    var pendingSelection: [URL]?
    var pendingRename: URL?
    /// «Вырезанные» файлы — общие для всех окон, чтобы Cmd+X в одном и Cmd+V в другом переносили файлы.
    static var cutURLs: [URL] = []
    static var cutChangeCount = -1

    init(location: Location, history: NavigationHistory = NavigationHistory()) {
        self.location = location
        self.history = history
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false)
        window.minSize = NSSize(width: 560, height: 340)
        window.appearance = NSAppearance(named: .aqua)
        window.tabbingMode = .disallowed
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        ops = FileOperations(window: window)
        window.contentView = buildContent()
        connect()
        browser.mode = settings.viewMode
        status.mode = settings.viewMode
        browser.setSortIndicator(settings.sortKey, ascending: settings.ascending)
        sidebar.folderTree.showHidden = settings.showHidden
        navigate(to: location, recordHistory: false)
        window.initialFirstResponder = browser.activeView
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: Раскладка

    private var sidebarWidth: CGFloat { Theme.isWin10 ? Win10.sidebarWidth : Luna.sidebarWidth }

    private func buildContent() -> NSView {
        split.isVertical = true
        split.dividerStyle = .thin
        // NSSplitView запоминает начальную ширину панели как «запасной размер» — задаём её заранее.
        sidebar.frame = NSRect(x: 0, y: 0, width: sidebarWidth, height: 400)
        split.addArrangedSubview(sidebar)
        split.addArrangedSubview(browser)
        split.setHoldingPriority(.init(260), forSubviewAt: 0)
        split.setHoldingPriority(.defaultLow, forSubviewAt: 1)
        return Theme.isWin10 ? buildWin10Content() : buildXPContent()
    }

    /// Windows 10: лента, строка навигации, область навигации + список, строка состояния.
    private func buildWin10Content() -> NSView {
        let root = LunaView()
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.white.cgColor
        sidebar.mode = .folders
        sidebar.isHidden = UserDefaults.standard.bool(forKey: Self.navigationPaneHiddenKey)
        ribbon.overlayHost = root

        for v in [ribbon, navBar, split, status] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(v)
            v.leadingAnchor.constraint(equalTo: root.leadingAnchor).isActive = true
            v.trailingAnchor.constraint(equalTo: root.trailingAnchor).isActive = true
        }
        NSLayoutConstraint.activate([
            ribbon.topAnchor.constraint(equalTo: root.topAnchor),
            navBar.topAnchor.constraint(equalTo: ribbon.bottomAnchor),
            navBar.heightAnchor.constraint(equalToConstant: Win10.navigationBarHeight),
            split.topAnchor.constraint(equalTo: navBar.bottomAnchor),
            status.topAnchor.constraint(equalTo: split.bottomAnchor),
            status.heightAnchor.constraint(equalToConstant: Win10.statusBarHeight),
            status.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            browser.widthAnchor.constraint(greaterThanOrEqualToConstant: 250),
        ])
        // Скрытая область навигации сворачивается в ноль — ограничения ширины не должны этому мешать.
        for constraint in [sidebar.widthAnchor.constraint(greaterThanOrEqualToConstant: 120),
                           sidebar.widthAnchor.constraint(lessThanOrEqualToConstant: 420)] {
            constraint.priority = .init(999)
            constraint.isActive = true
        }
        return root
    }

    private func buildXPContent() -> NSView {
        let root = LunaView()
        let sep2 = SeparatorView()

        let views: [NSView] = [menuBar, toolbar, sep2, address, split, status]
        for v in views {
            v.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(v)
        }

        func pin(_ v: NSView, below prev: NSView?, height: CGFloat? = nil) {
            v.leadingAnchor.constraint(equalTo: root.leadingAnchor).isActive = true
            v.trailingAnchor.constraint(equalTo: root.trailingAnchor).isActive = true
            v.topAnchor.constraint(equalTo: prev?.bottomAnchor ?? root.topAnchor).isActive = true
            if let height { v.heightAnchor.constraint(equalToConstant: height).isActive = true }
        }

        pin(menuBar, below: nil, height: Luna.menuBarHeight)
        pin(toolbar, below: menuBar, height: Luna.toolbarHeight)
        pin(sep2, below: toolbar, height: 2)
        pin(address, below: sep2, height: Luna.addressBarHeight)
        pin(split, below: address)
        pin(status, below: split, height: Luna.statusBarHeight)
        status.bottomAnchor.constraint(equalTo: root.bottomAnchor).isActive = true
        sidebar.widthAnchor.constraint(greaterThanOrEqualToConstant: 150).isActive = true
        sidebar.widthAnchor.constraint(lessThanOrEqualToConstant: 420).isActive = true
        browser.widthAnchor.constraint(greaterThanOrEqualToConstant: 250).isActive = true
        return root
    }

    private func connect() {
        Theme.isWin10 ? connectWin10() : connectXP()

        sidebar.folderTree.onSelect = { [weak self] location in self?.navigate(to: location) }
        sidebar.folderTree.onOpenInNewWindow = { [weak self] location in self?.appDelegate?.openWindow(at: location) }
        sidebar.folderTree.onDrop = { [weak self] urls, folder, copy in
            self?.browserDrop(urls, into: folder, copy: copy) ?? false
        }
        sidebar.folderTree.menuProvider = { [weak self] location in self?.treeMenu(for: location) }

        browser.delegate = self

        watcher.onChange = { [weak self] in
            guard let self else { return }
            if self.browser.isRenaming {
                self.reloadAfterRename = true
            } else {
                self.reload(preserveSelection: true)
            }
        }
        search.onResults = { [weak self] urls, finished in self?.showSearchResults(urls, finished: finished) }
    }

    private func connectWin10() {
        navBar.back.onClick = { [weak self] _ in self?.goBack(nil) }
        navBar.forward.onClick = { [weak self] _ in self?.goForward(nil) }
        navBar.up.onClick = { [weak self] _ in self?.goUp(nil) }
        navBar.recent.onClick = { [weak self] button in
            self?.recentMenu().popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.maxY + 2), in: button)
        }
        navBar.address.onNavigate = { [weak self] location in self?.navigate(to: location) }
        navBar.address.onSubmit = { [weak self] text in self?.openAddress(text) }
        navBar.address.onCancel = { [weak self] in self?.focusList() }
        navBar.address.onRefresh = { [weak self] in self?.refresh(nil) }
        navBar.address.menuProvider = { [weak self] in self?.addressMenu() ?? NSMenu() }
        navBar.search.onSearch = { [weak self] text in self?.startSearch(text, scopeIndex: 0) }
        navBar.search.onClear = { [weak self] in
            guard let self, case .search(_, let scope) = self.location else { return }
            self.navigate(to: scope.path == "/" ? .computer : .folder(scope))
        }

        ribbon.tabs = ribbonTabs()
        ribbon.fileMenu = { [weak self] in self?.ribbonFileMenu() ?? NSMenu() }
        ribbon.validate = { [weak self] item in self?.validateMenuItem(item) ?? false }
        ribbon.perform = { [weak self] command, view in self?.performRibbon(command, from: view) }
        ribbon.onHelp = { [weak self] in self?.showShortcuts(nil) }

        status.onSelectMode = { [weak self] mode in self?.applyViewMode(mode) }
    }

    private func connectXP() {
        menuBar.menuProvider = { Menus.windowMenu(at: $0) }

        toolbar.back.onClick = { [weak self] _ in self?.goBack(nil) }
        toolbar.forward.onClick = { [weak self] _ in self?.goForward(nil) }
        toolbar.up.onClick = { [weak self] _ in self?.goUp(nil) }
        toolbar.search.onClick = { [weak self] _ in self?.toggleSearch(nil) }
        toolbar.folders.onClick = { [weak self] _ in self?.toggleFolders(nil) }
        toolbar.views.onClick = { button in
            Menus.menu(tr(.views), Menus.viewModes())
                .popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.maxY + 2), in: button)
        }

        address.onSubmit = { [weak self] text in self?.openAddress(text) }
        address.onCancel = { [weak self] in self?.focusList() }
        address.menuProvider = { [weak self] in self?.addressMenu() ?? NSMenu() }

        sidebar.onClose = { [weak self] in self?.setSidebarMode(.tasks) }
        address.onCopyPath = { [weak self] in self?.copyPath(nil) }
        sidebar.searchPane.onSearch = { [weak self] text, scope in self?.startSearch(text, scopeIndex: scope) }
    }

    /// Начальная ширина левой панели. Вызывается после показа окна, когда раскладка уже посчитана,
    /// иначе разделитель сбрасывается.
    func applyInitialSidebarWidth() {
        window?.layoutIfNeeded()
        guard !sidebar.isHidden else { return }
        split.setPosition(sidebarWidth, ofDividerAt: 0)
    }

    /// Показать или скрыть область навигации (Windows 10). Скрытая панель сворачивается в ноль.
    func setNavigationPaneHidden(_ hidden: Bool) {
        sidebar.isHidden = hidden
        UserDefaults.standard.set(hidden, forKey: Self.navigationPaneHiddenKey)
        split.adjustSubviews()
        if !hidden {
            applyInitialSidebarWidth()
            sidebar.folderTree.reveal(location)
        }
    }

    func windowWillClose(_ notification: Notification) {
        search.stop()
        watcher.watch(nil)
        (NSApp.delegate as? AppDelegate)?.windowDidClose(self)
    }

    // MARK: Навигация

    func navigate(to newLocation: Location, recordHistory: Bool = true, select: [URL] = []) {
        if recordHistory, newLocation != location { history.push(location) }
        if case .search = newLocation {} else { search.stop() }
        location = newLocation
        pendingSelection = select
        pendingRename = nil
        if let url = newLocation.url {
            settings.lastPath = url.path
            settings.save()
        }
        scrollToTopOnApply = true
        browser.setItems([], selecting: [])
        reload(preserveSelection: false)
        updateChrome()
    }

    func reload(preserveSelection: Bool) {
        if preserveSelection && pendingSelection == nil {
            pendingSelection = browser.selectedItems.map(\.url)
        }
        loadGeneration += 1
        let generation = loadGeneration
        let showHidden = settings.showHidden
        switch location {
        case .folder(let url):
            watcher.watch(url)
            DispatchQueue.global(qos: .userInitiated).async {
                let result = Result { try DirectoryLoader.contents(of: url, showHidden: showHidden) }
                DispatchQueue.main.async { [weak self] in
                    guard let self, generation == self.loadGeneration else { return }
                    switch result {
                    case .success(let items): self.apply(items)
                    case .failure(let error): self.handleLoadError(error, url: url)
                    }
                }
            }
        case .computer:
            watcher.watch(nil)
            apply(DirectoryLoader.computerItems())
        case .search(let query, let scope):
            watcher.watch(nil)
            if !preserveSelection {
                status.leftText = tr(.searching)
                status.middleText = ""
                search.start(query, in: scope)
            }
        }
    }

    func apply(_ items: [FileItem]) {
        let sorted = FileItem.sorted(items, by: settings.sortKey, ascending: settings.ascending)
        browser.setItems(sorted, selecting: pendingSelection ?? [])
        pendingSelection = nil
        if scrollToTopOnApply && browser.selectedItems.isEmpty { browser.scrollToTop() }
        scrollToTopOnApply = false
        if let url = pendingRename,
           let index = sorted.firstIndex(where: { $0.url.standardizedFileURL.path == url.standardizedFileURL.path }) {
            pendingRename = nil
            browser.beginRename(at: index)
        }
        selectionChanged()
    }

    private func handleLoadError(_ error: Error, url: URL) {
        // Папку удалили, пока она была открыта — поднимаемся выше, как XP.
        if !FileManager.default.fileExists(atPath: url.path), let parent = location.parent {
            navigate(to: parent, recordHistory: false)
            return
        }
        apply([])
        status.leftText = tr(.noAccess)
        let code = (error as NSError).code
        let underlying = ((error as NSError).userInfo[NSUnderlyingErrorKey] as? NSError)?.code
        let denied = code == NSFileReadNoPermissionError || underlying == Int(EPERM) || underlying == Int(EACCES)
        Alerts.error(
            tr(.noAccessTitle, Places.displayName(of: url)),
            info: denied
                ? tr(.noAccessFullDisk, L10n.appName)
                : error.localizedDescription)
    }

    private func showSearchResults(_ urls: [URL], finished: Bool) {
        guard case .search = location else { return }
        let generation = loadGeneration
        DispatchQueue.global(qos: .userInitiated).async {
            let items = urls.map(FileItem.init(url:))
            DispatchQueue.main.async { [weak self] in
                guard let self, generation == self.loadGeneration else { return }
                if self.pendingSelection == nil { self.pendingSelection = self.browser.selectedItems.map(\.url) }
                self.apply(items)
            }
        }
    }

    func updateChrome() {
        window?.title = location.title
        window?.representedURL = location.url
        if Theme.isWin10 {
            navBar.address.showHidden = settings.showHidden
            navBar.update(location, canGoBack: history.canGoBack, canGoForward: history.canGoForward,
                          canGoUp: location.parent != nil)
            status.mode = settings.viewMode
            if !sidebar.isHidden { sidebar.folderTree.reveal(location) }
            ribbon.refresh()
            return
        }
        address.show(location)
        toolbar.back.isEnabled = history.canGoBack
        toolbar.forward.isEnabled = history.canGoForward
        toolbar.up.isEnabled = location.parent != nil
        address.canCopyPath = location.url != nil
        toolbar.folders.isToggled = sidebar.mode == .folders
        toolbar.search.isToggled = sidebar.mode == .search
        if sidebar.mode == .folders { sidebar.folderTree.reveal(location) }
        status.rightIcon = Places.computerIcon
        status.rightText = Places.computerTitle
    }

    func selectionChanged() {
        updateStatus()
        updateTaskPane()
        if Theme.isWin10 { ribbon.refresh() }
    }

    private func updateStatus() {
        let selected = browser.selectedItems
        let all = browser.items
        func total(_ items: [FileItem]) -> Int64 {
            items.filter { !$0.isDirectory }.compactMap(\.size).reduce(0, +)
        }
        if Theme.isWin10 {
            // «Элементов: 11    Выбран 1 элемент  5,4 КБ» — размер только у выбранных файлов.
            status.leftText = all.count == 1 ? tr(.itemsCountOne) : tr(.itemsCount, all.count)
            if selected.isEmpty {
                status.middleText = ""
            } else {
                let files = selected.filter { !$0.isDirectory }
                let size = files.isEmpty ? "" : "  " + Format.size(total(files))
                status.middleText = (selected.count == 1 ? tr(.itemSelectedOne) : tr(.itemsSelected, selected.count)) + size
            }
            return
        }
        if selected.isEmpty {
            if case .search = location {
                status.leftText = tr(.foundCount, all.count)
            } else {
                var text = tr(.objectsCount, all.count)
                if let url = location.url, let free = Places.freeSpace(url) {
                    text += tr(.freeSpace, Format.size(free))
                }
                status.leftText = text
            }
            status.middleText = location.url == nil ? "" : Format.size(total(all))
        } else {
            status.leftText = tr(.selectedCount, selected.count)
            let files = selected.filter { !$0.isDirectory }
            status.middleText = files.isEmpty ? "" : Format.size(total(files))
        }
    }

    // MARK: Адресная строка

    func openAddress(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        let named: [String: Location] = [
            Places.computerTitle.lowercased(): .computer,
            tr(.desktop).lowercased(): .folder(Places.desktop),
            tr(.myDocuments).lowercased(): .folder(Places.documents),
        ]
        if let place = named[text.lowercased()] {
            navigate(to: place)
            focusList()
            return
        }
        let path = (text as NSString).expandingTildeInPath
        var isDir: ObjCBool = false
        if path.hasPrefix("/"), FileManager.default.fileExists(atPath: path, isDirectory: &isDir) {
            let url = URL(fileURLWithPath: path)
            if isDir.boolValue && !Places.isPackage(url) {
                navigate(to: .folder(url))
            } else {
                NSWorkspace.shared.open(url)
                address.show(location)
            }
            focusList()
        } else if let url = URL(string: text), let scheme = url.scheme, ["http", "https"].contains(scheme) {
            NSWorkspace.shared.open(url)
        } else {
            Alerts.error(tr(.cannotFind, text), info: tr(.checkSpelling))
        }
    }

    /// Выпадающий список адресной строки: дерево основных мест и недавние папки.
    func addressMenu() -> NSMenu {
        let menu = NSMenu()
        func add(_ location: Location, indent: Int = 0) {
            let item = NSMenuItem(title: location.title, action: #selector(pickLocation(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = LocationRef(location)
            item.image = location.icon
            item.indentationLevel = indent
            menu.addItem(item)
        }
        add(.folder(Places.desktop))
        add(.folder(Places.documents), indent: 1)
        add(.computer, indent: 1)
        for volume in DirectoryLoader.volumes() { add(.folder(volume), indent: 2) }
        add(.folder(Places.home), indent: 1)
        let recent = history.recent(8)
        if !recent.isEmpty {
            menu.addItem(.separator())
            recent.forEach { add($0) }
        }
        return menu
    }

    /// Кнопка ⌄ рядом со стрелками Windows 10: последние места.
    func recentMenu() -> NSMenu {
        let menu = NSMenu()
        for place in history.recent(10) {
            let item = NSMenuItem(title: place.title, action: #selector(pickLocation(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = LocationRef(place)
            item.image = place.icon
            menu.addItem(item)
        }
        if menu.numberOfItems == 0 {
            let item = NSMenuItem(title: location.title, action: nil, keyEquivalent: "")
            item.image = location.icon
            menu.addItem(item)
        }
        return menu
    }

    /// Контекстное меню папки в дереве: действует на эту папку, а не на выделение в списке.
    func treeMenu(for place: Location) -> NSMenu {
        let menu = NSMenu()
        func add(_ title: String, bold: Bool = false, _ action: @escaping () -> Void) {
            let item = ActionMenuItem(title: title, handler: action)
            if bold {
                item.attributedTitle = NSAttributedString(string: title, attributes: [.font: NSFont.boldSystemFont(ofSize: 13)])
            }
            menu.addItem(item)
        }
        add(tr(.open), bold: true) { [weak self] in self?.navigate(to: place) }
        add(tr(.openInNewWindow)) { [weak self] in self?.appDelegate?.openWindow(at: place) }
        guard let url = place.url else { return menu }
        add(tr(.showInFinder)) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        add(tr(.openInTerminal)) {
            guard let terminal = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") else { return }
            NSWorkspace.shared.open([url], withApplicationAt: terminal, configuration: NSWorkspace.OpenConfiguration())
        }
        menu.addItem(.separator())
        add(tr(.copyPath)) { [weak self] in
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(url.path, forType: .string)
            self?.status.leftText = tr(.pathCopied, url.path)
        }
        let pinned = Favorites.all.contains { $0.standardizedFileURL.path == url.standardizedFileURL.path }
        if Theme.isWin10 {
            add(pinned ? tr(.unpinFromQuickAccess) : tr(.pinToQuickAccess)) { [weak self] in
                pinned ? Favorites.remove(url) : Favorites.add(url)
                self?.sidebar.folderTree.reload()
                self?.sidebar.folderTree.reveal(self?.location ?? place)
            }
        } else if !pinned {
            add(tr(.addToFavorites)) { Favorites.add(url) }
        }
        menu.addItem(.separator())
        add(tr(.properties)) { [weak self] in PropertiesWindowController.show(for: FileItem(url: url), near: self?.window) }
        return menu
    }

    @objc func pickLocation(_ sender: NSMenuItem) {
        guard let ref = sender.representedObject as? LocationRef else { return }
        navigate(to: ref.location)
    }

    func focusList() {
        window?.makeFirstResponder(browser.activeView)
    }

    func applyViewMode(_ mode: ViewMode) {
        settings.viewMode = mode
        settings.save()
        browser.mode = mode
        status.mode = mode
        if Theme.isWin10 { ribbon.refresh() }
    }

    // MARK: Левая панель и поиск

    func setSidebarMode(_ mode: SidebarContainer.Mode) {
        sidebar.mode = mode
        updateChrome()
        updateTaskPane()
        if mode == .search { sidebar.searchPane.focus() }
    }

    private func startSearch(_ text: String, scopeIndex: Int) {
        let scope: URL
        switch scopeIndex {
        case 0:
            if case .search(_, let previous) = location {
                scope = previous
            } else {
                scope = location.url ?? URL(fileURLWithPath: "/")
            }
        case 1: scope = Places.home
        default: scope = URL(fileURLWithPath: "/")
        }
        navigate(to: .search(query: text, scope: scope))
    }

    // MARK: Окна

    var appDelegate: AppDelegate? { NSApp.delegate as? AppDelegate }

    func open(_ items: [FileItem]) {
        guard !items.isEmpty else { return }
        if items.count == 1, items[0].isDirectory {
            navigate(to: .folder(items[0].url))
            return
        }
        for item in items {
            if item.isDirectory {
                appDelegate?.openWindow(at: .folder(item.url))
            } else {
                NSWorkspace.shared.open(item.url)
            }
        }
    }

    func finishRename() {
        if reloadAfterRename {
            reloadAfterRename = false
            reload(preserveSelection: true)
        }
    }
}

// MARK: - FileBrowserDelegate

extension MainWindowController: FileBrowserDelegate {
    var browserCurrentFolder: URL? { location.url }

    func browserSelectionDidChange() {
        selectionChanged()
    }

    func browserOpen(_ indexes: IndexSet) {
        open(indexes.filter { $0 < browser.items.count }.map { browser.items[$0] })
    }

    func browserOpenInNewWindow(_ index: Int) {
        let item = browser.items[index]
        if item.isDirectory {
            appDelegate?.openWindow(at: .folder(item.url))
        } else {
            NSWorkspace.shared.open(item.url)
        }
    }

    func browserHandleKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .option, .shift, .control])
        switch Int(event.keyCode) {
        case 36 where flags.isEmpty, 76 where flags.isEmpty:  // Return, Enter — открыть
            openSelection(nil)
            return true
        case 51 where flags.isEmpty:  // Backspace: в XP — на уровень вверх, в Windows 10 — назад
            Theme.isWin10 ? goBack(nil) : goUp(nil)
            return true
        case 117 where flags.isEmpty:  // Forward Delete — в корзину
            moveToTrash(nil)
            return true
        case 96:  // F5 — обновить
            refresh(nil)
            return true
        case 123 where flags == .option:  // Option+← — назад
            goBack(nil)
            return true
        case 124 where flags == .option:  // Option+→ — вперёд
            goForward(nil)
            return true
        default:
            return false
        }
    }

    func browserContextMenu(onItem: Bool) -> NSMenu? {
        if onItem {
            let selected = browser.selectedItems
            return Menus.itemContext(hasFolder: selected.contains { $0.isDirectory },
                                     archives: Menus.archiveMenus(for: selected))
        }
        return location.url == nil ? nil : Menus.backgroundContext()
    }

    func browserRename(_ index: Int, to name: String?) {
        defer { finishRename() }
        guard let name, index < browser.items.count else { return }
        let item = browser.items[index]
        if let renamed = ops.rename(item.url, to: name) {
            pendingSelection = [renamed]
            reloadAfterRename = false
            reload(preserveSelection: true)
        }
    }

    func browserSortDidChange(_ key: SortKey, ascending: Bool) {
        settings.sortKey = key
        settings.ascending = ascending
        settings.save()
        resort()
    }

    func browserDrop(_ urls: [URL], into folder: URL, copy: Bool) -> Bool {
        ops.transfer(urls, to: folder, kind: copy ? .copy : .move) { [weak self] created in
            guard let self else { return }
            if folder.standardizedFileURL.path == self.location.url?.standardizedFileURL.path {
                self.pendingSelection = created
            }
            self.reload(preserveSelection: true)
        }
        return true
    }

    func resort() {
        pendingSelection = browser.selectedItems.map(\.url)
        apply(browser.items)
    }
}
