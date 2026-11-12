import AppKit

/// Команды меню, тулбара и панели задач. Все они доступны через цепочку ответчиков.
extension MainWindowController: NSMenuItemValidation {
    private var selectedURLs: [URL] {
        browser.selectedItems.filter { !$0.isVolume }.map(\.url)
    }

    private var isEditingText: Bool {
        window?.firstResponder is NSText
    }

    private var pasteboardHasFiles: Bool {
        NSPasteboard.general.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
    }

    // MARK: Файл

    @objc func newFolder(_ sender: Any?) {
        guard let dir = location.url, let url = ops.createFolder(in: dir) else { return }
        pendingSelection = [url]
        pendingRename = url
        reload(preserveSelection: true)
    }

    @objc func newTextFile(_ sender: Any?) {
        guard let dir = location.url, let url = ops.createTextFile(in: dir) else { return }
        pendingSelection = [url]
        pendingRename = url
        reload(preserveSelection: true)
    }

    @objc func openSelection(_ sender: Any?) {
        open(browser.selectedItems)
    }

    @objc func openInNewWindow(_ sender: Any?) {
        for item in browser.selectedItems where item.isDirectory {
            openNewWindow(at: .folder(item.url))
        }
    }

    @objc func showInFinder(_ sender: Any?) {
        let urls = browser.selectedItems.map(\.url)
        if !urls.isEmpty {
            NSWorkspace.shared.activateFileViewerSelecting(urls)
        } else if let url = location.url {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    @objc func openInTerminal(_ sender: Any?) {
        let selected = browser.selectedItems
        let dir = selected.count == 1 && selected[0].isDirectory ? selected[0].url : location.url
        guard let dir,
              let terminal = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal")
        else { return }
        NSWorkspace.shared.open([dir], withApplicationAt: terminal, configuration: NSWorkspace.OpenConfiguration())
    }

    @objc func moveToTrash(_ sender: Any?) {
        let urls = selectedURLs
        guard !urls.isEmpty else { return }
        if ops.trash(urls, confirm: true) {
            reload(preserveSelection: false)
        }
    }

    @objc func renameSelection(_ sender: Any?) {
        let indexes = browser.selectedIndexes
        guard indexes.count == 1, let index = indexes.first, !browser.items[index].isVolume else { return }
        browser.beginRename(at: index)
    }

    @objc func showProperties(_ sender: Any?) {
        if let item = browser.selectedItems.first {
            PropertiesWindowController.show(for: item, near: window)
        } else if let url = location.url {
            PropertiesWindowController.show(for: FileItem(url: url), near: window)
        }
    }

    // MARK: Правка

    @objc func copy(_ sender: Any?) {
        writeToPasteboard(cut: false)
    }

    @objc func cut(_ sender: Any?) {
        writeToPasteboard(cut: true)
    }

    private func writeToPasteboard(cut: Bool) {
        let urls = selectedURLs
        guard !urls.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        // Отметка «вырезано» лежит в самом буфере обмена — её видят и другие экземпляры программы.
        let items = urls.enumerated().map { index, url -> NSPasteboardItem in
            let item = NSPasteboardItem()
            item.setString(url.absoluteString, forType: .fileURL)
            if cut && index == 0 { item.setData(Data(), forType: CutFiles.marker) }
            return item
        }
        pasteboard.writeObjects(items)
        CutFiles.refresh()
        status.leftText = cut
            ? tr(.cutStatus, urls.count)
            : tr(.copiedStatus, urls.count)
    }

    @objc func paste(_ sender: Any?) {
        let pasteboard = NSPasteboard.general
        let isCut = pasteboard.pasteboardItems?.contains { $0.types.contains(CutFiles.marker) } == true
        pasteFiles(move: isCut)
    }

    /// Cmd+Option+V — как в Finder: переместить скопированные объекты сюда.
    @objc func pasteMove(_ sender: Any?) {
        pasteFiles(move: true)
    }

    private func pasteFiles(move: Bool) {
        guard let dest = location.url else { return }
        let pasteboard = NSPasteboard.general
        guard let urls = pasteboard.readObjects(
            forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty
        else { return }
        ops.transfer(urls, to: dest, kind: move ? .move : .copy) { [weak self] created in
            guard let self else { return }
            if move {
                pasteboard.clearContents()
                CutFiles.refresh()
            }
            self.pendingSelection = created
            self.reload(preserveSelection: true)
        }
    }

    /// Копирует путь текущей папки (или выделенных объектов) как текст.
    @objc func copyPath(_ sender: Any?) {
        let selected = browser.selectedItems.map(\.url.path)
        let paths = selected.isEmpty ? [location.url?.path].compactMap { $0 } : selected
        guard !paths.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(paths.joined(separator: "\n"), forType: .string)
        status.leftText = paths.count == 1 ? tr(.pathCopied, paths[0]) : tr(.pathsCopied, paths.count)
    }

    @objc override func selectAll(_ sender: Any?) {
        browser.selectAllItems()
    }

    @objc func invertSelection(_ sender: Any?) {
        browser.invertSelection()
    }

    @objc func selectNone(_ sender: Any?) {
        browser.select(IndexSet())
    }

    @objc func copyToFolder(_ sender: Any?) {
        chooseFolder(for: .copy)
    }

    @objc func moveToFolder(_ sender: Any?) {
        chooseFolder(for: .move)
    }

    private func chooseFolder(for kind: FileOperations.Kind) {
        let urls = selectedURLs
        guard !urls.isEmpty, let window else { return }
        let verb = kind == .copy ? tr(.copy) : tr(.move)
        let what = urls.count == 1 ? tr(.quotedName, urls[0].lastPathComponent) : tr(.selectedItemsCount, urls.count)
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = verb
        panel.message = kind == .copy ? tr(.chooseCopyDestination, what, verb) : tr(.chooseMoveDestination, what, verb)
        panel.directoryURL = location.url
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let dest = panel.url, let self else { return }
            self.transfer(urls, to: dest, kind: kind)
        }
    }

    private func transfer(_ urls: [URL], to dest: URL, kind: FileOperations.Kind) {
        ops.transfer(urls, to: dest, kind: kind) { [weak self] _ in
            self?.reload(preserveSelection: kind == .copy)
        }
    }

    /// «Переместить в ▾» / «Копировать в ▾» ленты: папка — в representedObject пункта.
    @objc func moveToPlace(_ sender: NSMenuItem) {
        guard let dest = sender.representedObject as? URL, !selectedURLs.isEmpty else { return }
        transfer(selectedURLs, to: dest, kind: .move)
    }

    @objc func copyToPlace(_ sender: NSMenuItem) {
        guard let dest = sender.representedObject as? URL, !selectedURLs.isEmpty else { return }
        transfer(selectedURLs, to: dest, kind: .copy)
    }

    // MARK: Поделиться

    /// Системное меню «Поделиться». Из ленты — под кнопкой, из меню — у списка файлов.
    @objc func shareSelection(_ sender: Any?) {
        share(from: (sender as? NSView) ?? browser)
    }

    func share(from view: NSView) {
        let urls = browser.selectedItems.map(\.url)
        guard !urls.isEmpty else { return }
        NSSharingServicePicker(items: urls).show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
    }

    private var emailService: NSSharingService? { NSSharingService(named: .composeEmail) }

    private var attachableURLs: [URL] {
        browser.selectedItems.filter { !$0.isDirectory }.map(\.url)
    }

    @objc func emailSelection(_ sender: Any?) {
        emailService?.perform(withItems: attachableURLs)
    }

    // MARK: Вид

    @objc func setViewMode(_ sender: NSMenuItem) {
        guard let mode = ViewMode(rawValue: sender.tag) else { return }
        applyViewMode(mode)
    }

    @objc func sortBy(_ sender: NSMenuItem) {
        guard let key = SortKey(rawValue: sender.tag) else { return }
        settings.ascending = key == settings.sortKey ? !settings.ascending : true
        settings.sortKey = key
        rememberFolderView()
        browser.setSortIndicator(key, ascending: settings.ascending)
        resort()
    }

    @objc func toggleHidden(_ sender: Any?) {
        settings.showHidden.toggle()
        settings.save()
        sidebar.folderTree.showHidden = settings.showHidden
        reload(preserveSelection: true)
        updateChrome()
    }

    /// В Windows 10 «Папки» — это область навигации: она показывается или прячется целиком.
    @objc func toggleFolders(_ sender: Any?) {
        if Theme.isWin10 { return toggleNavigationPane(sender) }
        setSidebarMode(sidebar.mode == .folders ? .tasks : .folders)
    }

    @objc func toggleNavigationPane(_ sender: Any?) {
        setNavigationPaneHidden(!sidebar.isHidden)
    }

    /// В Windows 10 поиск — поле справа от адреса, отдельной панели нет.
    @objc func toggleSearch(_ sender: Any?) {
        if Theme.isWin10 { return navBar.search.focus() }
        setSidebarMode(sidebar.mode == .search ? .tasks : .search)
    }

    @objc func refresh(_ sender: Any?) {
        sidebar.folderTree.reload()
        reload(preserveSelection: true)
        updateChrome()
    }

    // MARK: Переход

    @objc func goBack(_ sender: Any?) {
        let current = location
        guard let target = history.back(from: current) else { return }
        navigate(to: target, recordHistory: false, select: current.url.map { [$0] } ?? [])
    }

    @objc func goForward(_ sender: Any?) {
        guard let target = history.forward(from: location) else { return }
        navigate(to: target, recordHistory: false)
    }

    @objc func goUp(_ sender: Any?) {
        guard let parent = location.parent else { return }
        navigate(to: parent, select: location.url.map { [$0] } ?? [])
    }

    @objc func goDesktop(_ sender: Any?) { navigate(to: .folder(Places.desktop)) }
    @objc func goDocuments(_ sender: Any?) { navigate(to: .folder(Places.documents)) }
    @objc func goHome(_ sender: Any?) { navigate(to: .folder(Places.home)) }
    @objc func goComputer(_ sender: Any?) { navigate(to: .computer) }

    @objc func goToFolder(_ sender: Any?) {
        Theme.isWin10 ? navBar.address.focus() : address.focus()
    }

    // MARK: Избранное

    @objc func addFavorite(_ sender: Any?) {
        let selectedFolders = browser.selectedItems.filter(\.isDirectory).map(\.url)
        let urls = selectedFolders.isEmpty ? [location.url].compactMap { $0 } : selectedFolders
        urls.forEach(Favorites.add)
        if !urls.isEmpty { status.leftText = tr(.addedToFavorites, urls.map(Places.displayName).joined(separator: ", ")) }
        favoritesChanged()
    }

    /// Избранное — это «Быстрый доступ» в области навигации Windows 10.
    private func favoritesChanged() {
        guard Theme.isWin10 else { return }
        sidebar.folderTree.reload()
        sidebar.folderTree.reveal(location)
    }

    @objc func openFavorite(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        navigate(to: .folder(url))
    }

    @objc func removeFavorite(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        Favorites.remove(url)
        favoritesChanged()
    }

    // MARK: Сервис и справка

    @objc func openSystemSettings(_ sender: Any?) {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
    }

    @objc func showShortcuts(_ sender: Any?) {
        Alerts.message(tr(.keyboardShortcuts), info: tr(.shortcutsText))
    }

    // MARK: Панель задач

    func updateTaskPane() {
        guard sidebar.mode == .tasks else { return }
        let selected = browser.selectedItems
        func icon(_ kind: XPIcon) -> NSImage { XPIcons.image(kind, size: 16) }
        let finderIcon = NSWorkspace.shared.icon(forFile: "/System/Library/CoreServices/Finder.app")
        finderIcon.size = NSSize(width: 16, height: 16)
        var groups: [TaskGroup] = []

        if case .computer = location {
            groups.append(TaskGroup(title: tr(.systemTasks), entries: [
                .link(tr(.viewSystemInfo), icon(.info)) {
                    NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/System Information.app"))
                },
                .link(tr(.changeSettings), icon(.settings)) { [weak self] in
                    self?.openSystemSettings(nil)
                },
            ]))
        } else {
            var entries: [TaskEntry] = []
            let editable = !selected.isEmpty && !selected.contains { $0.isVolume }
            if editable {
                let many = selected.count > 1, folder = selected[0].isDirectory
                func text(_ items: Str, _ folderKey: Str, _ fileKey: Str) -> String {
                    tr(many ? items : (folder ? folderKey : fileKey))
                }
                if !many {
                    entries.append(.link(text(.taskRenameFile, .taskRenameFolder, .taskRenameFile), icon(.rename)) { [weak self] in
                        self?.renameSelection(nil)
                    })
                }
                entries += [
                    .link(text(.taskMoveItems, .taskMoveFolder, .taskMoveFile), icon(.moveTo)) { [weak self] in
                        self?.moveToFolder(nil)
                    },
                    .link(text(.taskCopyItems, .taskCopyFolder, .taskCopyFile), icon(.copyTo)) { [weak self] in
                        self?.copyToFolder(nil)
                    },
                    .link(text(.taskDeleteItems, .taskDeleteFolder, .taskDeleteFile), icon(.delete)) { [weak self] in
                        self?.moveToTrash(nil)
                    },
                ]
            } else if location.url != nil {
                entries.append(.link(tr(.makeNewFolder), icon(.newFolder)) {
                    [weak self] in self?.newFolder(nil)
                })
            }
            entries.append(.link(tr(.showInFinder), finderIcon) { [weak self] in
                self?.showInFinder(nil)
            })
            groups.append(TaskGroup(title: tr(.fileAndFolderTasks), entries: entries))
        }

        var places: [Location] = []
        if let parent = location.parent { places.append(parent) }
        for place in [Location.folder(Places.desktop), .folder(Places.documents), .computer, .folder(Places.home)]
        where place != location && !places.contains(place) {
            places.append(place)
        }
        groups.append(TaskGroup(title: tr(.otherPlaces), entries: places.map { place in
            .link(place.title, place.icon) { [weak self] in
                if NSEvent.modifierFlags.contains(.command) {
                    self?.openNewWindow(at: place)
                } else {
                    self?.navigate(to: place)
                }
            }
        }))

        groups.append(TaskGroup(title: tr(.details), entries: detailEntries(selected)))
        sidebar.taskPane.update(groups)
    }

    private func detailEntries(_ selected: [FileItem]) -> [TaskEntry] {
        if selected.count == 1 {
            let item = selected[0]
            var entries: [TaskEntry] = [.heading(item.displayName), .text(item.typeName)]
            if let detail = item.detail { entries.append(.text(detail)) }
            if let modified = item.modified { entries.append(.text(tr(.modifiedAt, Format.date(modified)))) }
            if !item.isDirectory, let size = item.size { entries.append(.text(tr(.sizeIs, Format.size(size)))) }
            return entries
        }
        if selected.count > 1 {
            var entries: [TaskEntry] = [.heading(tr(.selectedCount, selected.count))]
            let size = selected.filter { !$0.isDirectory }.compactMap(\.size).reduce(0, +)
            if size > 0 { entries.append(.text(tr(.totalSize, Format.size(size)))) }
            return entries
        }
        switch location {
        case .folder(let url):
            var entries: [TaskEntry] = [.heading(location.title), .text(tr(.typeFolder))]
            if let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate {
                entries.append(.text(tr(.modifiedAt, Format.date(modified))))
            }
            return entries
        case .computer:
            return [.heading(Places.computerTitle), .text(tr(.typeSystemFolder))]
        case .search(let query, let scope):
            return [.heading(tr(.searchFor, query)), .text(tr(.searchIn, Places.displayName(of: scope)))]
        }
    }

    // MARK: Доступность команд

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        let selected = browser.selectedItems
        let editable = !selected.isEmpty && !selected.contains { $0.isVolume }
        switch item.action {
        case #selector(newFolder(_:)), #selector(newTextFile(_:)):
            return location.url != nil
        case #selector(openSelection(_:)):
            return !isEditingText && !selected.isEmpty
        case #selector(openInNewWindow(_:)):
            return selected.contains { $0.isDirectory }
        case #selector(deletePermanently(_:)):
            return !isEditingText && editable
        case #selector(openWithOther(_:)), #selector(openWithApp(_:)):
            return !openWithURLs.isEmpty
        case #selector(toggleHideExtensions(_:)):
            item.state = FileExtensions.hidden ? .on : .off
            return true
        case #selector(toggleShowExtensions(_:)):
            item.state = FileExtensions.hidden ? .off : .on
            return true
        case #selector(moveToTrash(_:)), #selector(cut(_:)), #selector(copyToFolder(_:)), #selector(moveToFolder(_:)):
            return !isEditingText && editable
        case #selector(copy(_:)):
            return editable
        case #selector(renameSelection(_:)):
            return !isEditingText && selected.count == 1 && editable
        case #selector(paste(_:)), #selector(pasteMove(_:)):
            return location.url != nil && pasteboardHasFiles
        case #selector(selectAll(_:)), #selector(invertSelection(_:)):
            return !browser.items.isEmpty
        case #selector(selectNone(_:)):
            return !selected.isEmpty
        case #selector(moveToPlace(_:)), #selector(copyToPlace(_:)):
            return !isEditingText && editable
        case #selector(shareSelection(_:)):
            return !selected.isEmpty
        case #selector(emailSelection(_:)):
            let files = attachableURLs
            return !files.isEmpty && emailService?.canPerform(withItems: files) == true
        case #selector(archiveAddToZip(_:)):
            return !selected.isEmpty && !selected.contains { $0.isVolume } && ArchiveKind(rawValue: item.tag)?.archiver != nil
        case #selector(toggleNavigationPane(_:)):
            item.state = sidebar.isHidden ? .off : .on
            return true
        case #selector(setViewMode(_:)):
            item.state = item.tag == settings.viewMode.rawValue ? .on : .off
            return true
        case #selector(sortBy(_:)):
            item.state = item.tag == settings.sortKey.rawValue ? .on : .off
            return true
        case #selector(toggleHidden(_:)):
            item.state = settings.showHidden ? .on : .off
            return true
        case #selector(toggleFolders(_:)):
            item.state = (Theme.isWin10 ? !sidebar.isHidden : sidebar.mode == .folders) ? .on : .off
            return true
        case #selector(toggleSearch(_:)):
            item.state = sidebar.mode == .search ? .on : .off
            return true
        case #selector(goBack(_:)):
            return history.canGoBack
        case #selector(goForward(_:)):
            return history.canGoForward
        case #selector(goUp(_:)):
            return !isEditingText && location.parent != nil
        case #selector(copyPath(_:)):
            return !isEditingText && (location.url != nil || !selected.isEmpty)
        case #selector(addFavorite(_:)):
            return location.url != nil || selected.contains { $0.isDirectory }
        default:
            return true
        }
    }
}
