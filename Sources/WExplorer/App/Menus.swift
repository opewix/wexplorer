import AppKit

/// Все меню приложения: строка меню в окне, системная строка меню macOS и контекстные меню.
/// Пункты без target идут по цепочке ответчиков к активному окну, поэтому одни и те же
/// меню работают везде.
enum Menus {
    typealias W = MainWindowController


    // MARK: Строительные блоки

    static func item(_ title: String, _ action: Selector?, _ key: String = "",
                     _ modifiers: NSEvent.ModifierFlags = .command, tag: Int = 0) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = key.isEmpty ? [] : modifiers
        item.tag = tag
        return item
    }

    static func submenu(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = menu(title, items)
        return item
    }

    static func menu(_ title: String, _ items: [NSMenuItem]) -> NSMenu {
        let menu = NSMenu(title: title)
        items.forEach(menu.addItem)
        return menu
    }

    private static func key(_ code: Int) -> String {
        String(Character(UnicodeScalar(UInt32(code))!))
    }

    // MARK: Строка меню в окне

    static var titles: [String] {
        [tr(.menuFile), tr(.menuEdit), tr(.menuView), tr(.menuFavorites), tr(.menuTools), tr(.menuHelp)]
    }

    static func windowMenu(at index: Int) -> NSMenu? {
        switch index {
        case 0: return file()
        case 1: return edit()
        case 2: return view(includeGo: true)
        case 3: return favorites()
        case 4: return tools()
        case 5: return help()
        default: return nil
        }
    }

    // MARK: Меню

    static func file() -> NSMenu {
        menu(tr(.menuFile), [
            item(tr(.newWindow), #selector(AppDelegate.newWindow(_:)), "n"),
            item(tr(.newFolder), #selector(W.newFolder(_:)), "n", [.command, .shift]),
            item(tr(.newTextDocument), #selector(W.newTextFile(_:))),
            .separator(),
            item(tr(.open), #selector(W.openSelection(_:)), key(NSDownArrowFunctionKey)),
            item(tr(.openInNewWindow), #selector(W.openInNewWindow(_:))),
            item(tr(.showInFinder), #selector(W.showInFinder(_:))),
            .separator(),
            item(tr(.delete), #selector(W.moveToTrash(_:)), key(NSBackspaceCharacter)),
            item(tr(.rename), #selector(W.renameSelection(_:)), key(NSF2FunctionKey), []),
            item(tr(.properties), #selector(W.showProperties(_:)), "i"),
            .separator(),
            item(tr(.close), #selector(NSWindow.performClose(_:)), "w"),
        ])
    }

    static func edit() -> NSMenu {
        menu(tr(.menuEdit), [
            item(tr(.undo), Selector(("undo:")), "z"),
            item(tr(.redo), Selector(("redo:")), "z", [.command, .shift]),
            .separator(),
            item(tr(.cut), #selector(NSText.cut(_:)), "x"),
            item(tr(.copy), #selector(NSText.copy(_:)), "c"),
            item(tr(.paste), #selector(NSText.paste(_:)), "v"),
            item(tr(.moveHere), #selector(W.pasteMove(_:)), "v", [.command, .option]),
            item(tr(.copyPath), #selector(W.copyPath(_:)), "c", [.command, .option]),
            .separator(),
            item(tr(.copyToFolder), #selector(W.copyToFolder(_:))),
            item(tr(.moveToFolder), #selector(W.moveToFolder(_:))),
            .separator(),
            item(tr(.selectAll), #selector(NSText.selectAll(_:)), "a"),
            item(tr(.invertSelection), #selector(W.invertSelection(_:))),
        ])
    }

    static func viewModes() -> [NSMenuItem] {
        ViewMode.allCases.map {
            item($0.title, #selector(W.setViewMode(_:)), "\($0.rawValue + 1)", tag: $0.rawValue)
        }
    }

    static func sortItems() -> [NSMenuItem] {
        SortKey.allCases.map { item($0.menuTitle, #selector(W.sortBy(_:)), tag: $0.rawValue) }
    }

    static func goItems() -> [NSMenuItem] {
        [
            item(tr(.back), #selector(W.goBack(_:)), "["),
            item(tr(.forward), #selector(W.goForward(_:)), "]"),
            item(tr(.upOneLevel), #selector(W.goUp(_:)), key(NSUpArrowFunctionKey)),
            .separator(),
            item(tr(.desktop), #selector(W.goDesktop(_:)), "d", [.command, .shift]),
            item(tr(.myDocuments), #selector(W.goDocuments(_:)), "o", [.command, .shift]),
            item(tr(.homeFolder), #selector(W.goHome(_:)), "h", [.command, .shift]),
            item(tr(.myComputer), #selector(W.goComputer(_:)), "c", [.command, .shift]),
            .separator(),
            item(tr(.goToFolder), #selector(W.goToFolder(_:)), "l"),
        ]
    }

    static func view(includeGo: Bool) -> NSMenu {
        var items: [NSMenuItem] = [
            submenu(tr(.explorerBar), [
                item(tr(.search), #selector(W.toggleSearch(_:)), "f"),
                item(tr(.folders), #selector(W.toggleFolders(_:)), "f", [.command, .option]),
            ]),
            .separator(),
        ]
        items += viewModes()
        items += [
            .separator(),
            submenu(tr(.arrangeIcons), sortItems()),
            item(tr(.hiddenFiles), #selector(W.toggleHidden(_:)), ".", [.command, .shift]),
            .separator(),
        ]
        if includeGo { items.append(submenu(tr(.menuGo), goItems())) }
        items.append(item(tr(.refresh), #selector(W.refresh(_:)), "r"))
        return menu(tr(.menuView), items)
    }

    static func favorites() -> NSMenu {
        let menu = NSMenu(title: tr(.menuFavorites))
        menu.delegate = FavoritesMenuDelegate.shared
        FavoritesMenuDelegate.shared.menuNeedsUpdate(menu)
        return menu
    }

    static func tools() -> NSMenu {
        menu(tr(.menuTools), [
            item(tr(.openInTerminal), #selector(W.openInTerminal(_:)), "t", [.command, .option]),
            item(tr(.showInFinder), #selector(W.showInFinder(_:))),
            .separator(),
            item(tr(.showHiddenFiles), #selector(W.toggleHidden(_:))),
            .separator(),
            item(tr(.systemSettings), #selector(W.openSystemSettings(_:))),
            .separator(),
            languageMenu(),
        ])
    }

    /// «Язык ▸ English / Русский …» — список берётся из L10n.languages.
    static func languageMenu() -> NSMenuItem {
        submenu(tr(.language), L10n.languages.map { language in
            let item = Menus.item(language.name, #selector(AppDelegate.setLanguage(_:)))
            item.representedObject = language.code
            item.state = language.code == (L10n.chosenCode ?? L10n.current.code) ? .on : .off
            return item
        })
    }

    static func help() -> NSMenu {
        menu(tr(.menuHelp), [
            item(tr(.keyboardShortcuts), #selector(W.showShortcuts(_:)), "/", [.command, .shift]),
            .separator(),
            item(tr(.about, L10n.appName), #selector(NSApplication.orderFrontStandardAboutPanel(_:))),
        ])
    }

    // MARK: Контекстные меню

    static func itemContext(hasFolder: Bool, archives: [NSMenuItem]) -> NSMenu {
        let open = item(tr(.open), #selector(W.openSelection(_:)))
        open.attributedTitle = NSAttributedString(string: tr(.open), attributes: [.font: NSFont.boldSystemFont(ofSize: 13)])
        var items = [open]
        if hasFolder { items.append(item(tr(.openInNewWindow), #selector(W.openInNewWindow(_:)))) }
        items.append(item(tr(.showInFinder), #selector(W.showInFinder(_:))))
        if !archives.isEmpty { items += [.separator()] + archives }
        items += [
            .separator(),
            item(tr(.cut), #selector(NSText.cut(_:))),
            item(tr(.copy), #selector(NSText.copy(_:))),
            item(tr(.copyPath), #selector(W.copyPath(_:))),
            .separator(),
            item(tr(.delete), #selector(W.moveToTrash(_:))),
            item(tr(.rename), #selector(W.renameSelection(_:))),
            .separator(),
            item(tr(.addToFavorites), #selector(W.addFavorite(_:))),
            item(tr(.properties), #selector(W.showProperties(_:))),
        ]
        return menu("", items)
    }

    /// Подменю архиваторов: встроенный есть всегда, «7-Zip» — только если он установлен.
    static func archiveMenus(for selected: [FileItem]) -> [NSMenuItem] {
        ArchiveKind.allCases.compactMap { archiveMenu($0, for: selected) }
    }

    /// Распаковка для архивов и сжатие для любых объектов, кроме дисков.
    private static func archiveMenu(_ kind: ArchiveKind, for selected: [FileItem]) -> NSMenuItem? {
        guard let archiver = kind.archiver else { return nil }
        let tag = kind.rawValue
        let archives = selected.filter { !$0.isDirectory && archiver.canExtract($0.url) }.map(\.url)
        var items: [NSMenuItem] = []
        if !archives.isEmpty && archives.count == selected.count {
            let toFolder = archives.count == 1
                ? tr(.archiveExtractTo, ArchiveNames.folderName(for: archives[0]) + "/")
                : tr(.archiveExtractToEach)
            items += [
                item(tr(.archiveExtractEllipsis), #selector(W.archiveExtract(_:)), tag: tag),
                item(tr(.archiveExtractHere), #selector(W.archiveExtractHere(_:)), tag: tag),
                item(toFolder, #selector(W.archiveExtractToFolder(_:)), tag: tag),
                item(tr(.archiveTest), #selector(W.archiveTest(_:)), tag: tag),
            ]
        }
        let sources = selected.map(\.url)
        if !selected.contains(where: \.isVolume),
           let to7z = archiver.archiveURL(for: sources, ext: "7z"),
           let toZip = archiver.archiveURL(for: sources, ext: "zip") {
            if !items.isEmpty { items.append(.separator()) }
            // Окна настроек нет у встроенного архиватора: tar не умеет большую часть этих настроек.
            if kind == .sevenZip { items.append(item(tr(.archiveAddDialog), #selector(W.archiveAddWithDialog(_:)))) }
            items += [
                item(tr(.archiveAddTo, to7z.lastPathComponent), #selector(W.archiveAddTo7z(_:)), tag: tag),
                item(tr(.archiveAddTo, toZip.lastPathComponent), #selector(W.archiveAddToZip(_:)), tag: tag),
            ]
        }
        guard !items.isEmpty else { return nil }
        return submenu(kind == .builtin ? tr(.archiveMenu) : "7-Zip", items)
    }

    static func backgroundContext() -> NSMenu {
        menu("", [
            submenu(tr(.menuView), viewModes()),
            submenu(tr(.arrangeIcons), sortItems()),
            item(tr(.refresh), #selector(W.refresh(_:))),
            .separator(),
            item(tr(.paste), #selector(NSText.paste(_:))),
            item(tr(.moveHere), #selector(W.pasteMove(_:))),
            item(tr(.copyPath), #selector(W.copyPath(_:))),
            .separator(),
            submenu(tr(.create), [
                item(tr(.createFolder), #selector(W.newFolder(_:))),
                .separator(),
                item(tr(.createTextDocument), #selector(W.newTextFile(_:))),
            ]),
            .separator(),
            item(tr(.openInTerminal), #selector(W.openInTerminal(_:))),
            item(tr(.properties), #selector(W.showProperties(_:))),
        ])
    }

    // MARK: Системная строка меню macOS

    static func main() -> NSMenu {
        let main = NSMenu()
        func add(_ menu: NSMenu) {
            let top = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
            top.submenu = menu
            main.addItem(top)
        }
        add(menu(L10n.appName, [
            item(tr(.about, L10n.appName), #selector(NSApplication.orderFrontStandardAboutPanel(_:))),
            .separator(),
            item(tr(.hideApp, L10n.appName), #selector(NSApplication.hide(_:)), "h"),
            item(tr(.hideOthers), #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]),
            .separator(),
            item(tr(.quitApp, L10n.appName), #selector(NSApplication.terminate(_:)), "q"),
        ]))
        add(file())
        add(edit())
        add(view(includeGo: false))
        add(menu(tr(.menuGo), goItems()))
        add(favorites())
        add(tools())
        let window = menu(tr(.menuWindow), [
            item(tr(.minimize), #selector(NSWindow.performMiniaturize(_:)), "m"),
            item(tr(.zoom), #selector(NSWindow.performZoom(_:))),
            .separator(),
            item(tr(.bringAllToFront), #selector(NSApplication.arrangeInFront(_:))),
        ])
        add(window)
        NSApp.windowsMenu = window
        add(help())
        return main
    }
}

/// Пересобирает меню «Избранное» при каждом открытии.
final class FavoritesMenuDelegate: NSObject, NSMenuDelegate {
    static let shared = FavoritesMenuDelegate()

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(Menus.item(tr(.addToFavorites), #selector(MainWindowController.addFavorite(_:)), "d"))
        let favorites = Favorites.all
        let remove = Menus.submenu(tr(.removeFromFavorites), favorites.map { url in
            let item = Menus.item(Places.displayName(of: url), #selector(MainWindowController.removeFavorite(_:)))
            item.representedObject = url
            return item
        })
        menu.addItem(remove)
        guard !favorites.isEmpty else { return }
        menu.addItem(.separator())
        for url in favorites {
            let item = Menus.item(Places.displayName(of: url), #selector(MainWindowController.openFavorite(_:)))
            item.representedObject = url
            item.image = Places.icon(url)
            item.toolTip = url.path
            menu.addItem(item)
        }
    }
}
