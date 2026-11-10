import AppKit

/// Содержимое ленты Windows 10. Кнопки вызывают те же команды, что и меню, и проверяются тем же
/// `validateMenuItem`, поэтому доступность и отметки совпадают с меню.
extension MainWindowController {
    typealias Command = RibbonCommand

    func ribbonTabs() -> [RibbonTab] {
        [
            RibbonTab(title: tr(.ribbonHome), groups: [
                RibbonGroup(title: tr(.groupClipboard), items: [
                    .large(Command(tr(.pinToQuickAccess), .pin, #selector(addFavorite(_:)))),
                    .large(Command(tr(.copy), .copy, #selector(copy(_:)))),
                    .large(Command(tr(.paste), .paste, #selector(paste(_:)))),
                    .small([
                        Command(tr(.cut), .cut, #selector(cut(_:))),
                        Command(tr(.copyPath), .copyPath, #selector(copyPath(_:))),
                        Command(tr(.moveHere), .moveTo, #selector(pasteMove(_:))),
                    ]),
                ]),
                RibbonGroup(title: tr(.groupOrganize), items: [
                    .large(Command(tr(.moveTo), .moveTo, #selector(moveToFolder(_:)),
                                   menu: { [weak self] in self?.placesMenu(move: true) ?? NSMenu() })),
                    .large(Command(tr(.copyTo), .copyToFolder, #selector(copyToFolder(_:)),
                                   menu: { [weak self] in self?.placesMenu(move: false) ?? NSMenu() })),
                    .large(Command(tr(.delete), .delete, #selector(moveToTrash(_:)))),
                    .large(Command(tr(.rename), .rename, #selector(renameSelection(_:)))),
                ]),
                RibbonGroup(title: tr(.create), items: [
                    .large(Command(tr(.ribbonNewFolder), .newFolder, #selector(newFolder(_:)))),
                    .small([
                        Command(tr(.newItem), .newItem, #selector(newTextFile(_:)), menu: { Menus.menu("", [
                            Menus.item(tr(.createFolder), #selector(MainWindowController.newFolder(_:))),
                            Menus.item(tr(.createTextDocument), #selector(MainWindowController.newTextFile(_:))),
                        ]) }),
                    ]),
                ]),
                RibbonGroup(title: tr(.open), items: [
                    .large(Command(tr(.properties), .properties, #selector(showProperties(_:)))),
                    .small([
                        Command(tr(.open), .folderOpen, #selector(openSelection(_:))),
                        Command(tr(.openInNewWindow), .program, #selector(openInNewWindow(_:))),
                        Command(tr(.showInFinder), .search, #selector(showInFinder(_:))),
                    ]),
                ]),
                RibbonGroup(title: tr(.groupSelect), items: [
                    .small([
                        Command(tr(.selectAll), .selectAll, #selector(selectAll(_:))),
                        Command(tr(.selectNone), .selectNone, #selector(selectNone(_:))),
                        Command(tr(.invertSelection), .invertSelection, #selector(invertSelection(_:))),
                    ]),
                ]),
            ]),
            RibbonTab(title: tr(.ribbonShare), groups: [
                RibbonGroup(title: tr(.groupSend), items: [
                    .large(Command(tr(.share), .share, #selector(shareSelection(_:)),
                                   custom: { [weak self] view in self?.share(from: view) })),
                    .large(Command(tr(.email), .email, #selector(emailSelection(_:)))),
                    .large(Command(tr(.zip), .archive, #selector(archiveAddToZip(_:)), tag: ArchiveKind.builtin.rawValue)),
                ]),
            ]),
            RibbonTab(title: tr(.menuView), groups: [
                RibbonGroup(title: tr(.groupPanes), items: [
                    .large(Command(tr(.navigationPane), .navigationPane, #selector(toggleNavigationPane(_:)))),
                ]),
                RibbonGroup(title: tr(.groupLayout), items: [
                    .gallery(ViewMode.allCases.map { mode in
                        Command(mode.title, mode.icon, #selector(setViewMode(_:)), tag: mode.rawValue)
                    }, columns: 2),
                ]),
                RibbonGroup(title: tr(.groupCurrentView), items: [
                    .large(Command(tr(.sortBy), .sortBy, nil, menu: { Menus.menu("", Menus.sortItems()) })),
                ]),
                RibbonGroup(title: tr(.groupShowHide), items: [
                    .checks([Command(tr(.hiddenItems), nil, #selector(toggleHidden(_:)))]),
                ]),
            ]),
        ]
    }

    /// Синяя вкладка «Файл».
    func ribbonFileMenu() -> NSMenu {
        Menus.menu(tr(.menuFile), [
            Menus.item(tr(.newWindow), #selector(AppDelegate.newWindow(_:))),
            Menus.item(tr(.openInTerminal), #selector(openInTerminal(_:))),
            .separator(),
            Menus.item(tr(.keyboardShortcuts), #selector(showShortcuts(_:))),
            .separator(),
            Menus.item(tr(.close), #selector(NSWindow.performClose(_:))),
        ])
    }

    /// Кнопка ленты нажата: своё действие или селектор с пунктом меню в роли отправителя —
    /// так команды получают тот же тег, что и из меню.
    func performRibbon(_ command: RibbonCommand, from view: NSView) {
        if let custom = command.custom {
            custom(view)
            return
        }
        guard let action = command.action else { return }
        let item = NSMenuItem(title: command.title, action: action, keyEquivalent: "")
        item.tag = command.tag
        NSApp.sendAction(action, to: responds(to: action) ? self : nil, from: item)
    }

    /// «Переместить в ▾» / «Копировать в ▾»: избранное и особые папки, затем «Выбрать расположение...».
    private func placesMenu(move: Bool) -> NSMenu {
        let action = move ? #selector(moveToPlace(_:)) : #selector(copyToPlace(_:))
        var seen = Set<String>()
        let places = (Favorites.all + [Places.desktop, Places.documents, Places.downloads, Places.music,
                                       Places.pictures, Places.movies, Places.home])
            .filter { seen.insert($0.standardizedFileURL.path).inserted }
        var items = places.map { url -> NSMenuItem in
            let item = Menus.item(Places.displayName(of: url), action)
            item.representedObject = url
            item.image = Places.icon(url)
            return item
        }
        items += [.separator(), Menus.item(tr(.chooseLocation), move ? #selector(moveToFolder(_:)) : #selector(copyToFolder(_:)))]
        return Menus.menu("", items)
    }
}

extension ViewMode {
    var icon: XPIcon {
        switch self {
        case .thumbnails: return .views
        case .tiles: return .viewTiles
        case .icons: return .viewIcons
        case .list: return .viewList
        case .details: return .viewDetails
        }
    }
}
