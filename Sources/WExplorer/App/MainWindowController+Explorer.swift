import AppKit
import UniformTypeIdentifiers

/// Команды, повторяющие Проводник: «Открыть с помощью», удаление без корзины,
/// скрытие расширений, меню перетаскивания правой кнопкой.
extension MainWindowController {
    // MARK: Открыть с помощью

    /// Файлы для «Открыть с помощью»: только файлы, без папок, дисков и программ.
    var openWithURLs: [URL] {
        let selected = browser.selectedItems
        guard !selected.isEmpty,
              !selected.contains(where: { $0.isDirectory || $0.isVolume || $0.contentType?.conforms(to: .application) == true })
        else { return [] }
        return selected.map(\.url)
    }

    @objc func openWithApp(_ sender: NSMenuItem) {
        guard let app = sender.representedObject as? URL else { return }
        open(openWithURLs, with: app)
    }

    @objc func openWithOther(_ sender: Any?) {
        let urls = openWithURLs
        guard !urls.isEmpty, let window else { return }
        let panel = NSOpenPanel()
        panel.title = tr(.openWith)
        panel.prompt = tr(.open)
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.canChooseDirectories = false
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let app = panel.url else { return }
            self?.open(urls, with: app)
        }
    }

    private func open(_ urls: [URL], with app: URL) {
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.open(urls, withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            guard let error else { return }
            DispatchQueue.main.async {
                Alerts.error(tr(.cannotOpenWith, FileManager.default.displayName(atPath: app.path)),
                             info: error.localizedDescription)
            }
        }
    }

    // MARK: Удаление без корзины

    @objc func deletePermanently(_ sender: Any?) {
        let urls = browser.selectedItems.filter { !$0.isVolume }.map(\.url)
        guard !urls.isEmpty else { return }
        ops.deletePermanently(urls) { [weak self] in self?.reload(preserveSelection: false) }
    }

    // MARK: Расширения имён

    /// «Сервис → Скрывать расширения…» (отметка — когда спрятаны).
    @objc func toggleHideExtensions(_ sender: Any?) {
        FileExtensions.setHidden(!FileExtensions.hidden)
        selectionChanged()
    }

    /// Флажок «Расширения имён файлов» на ленте Windows 10 (отметка — когда видны).
    @objc func toggleShowExtensions(_ sender: Any?) {
        toggleHideExtensions(sender)
    }

    // MARK: Перетаскивание правой кнопкой

    /// Что перетащили и куда — для пунктов меню после отпускания правой кнопки.
    private final class DropRequest: NSObject {
        let urls: [URL]
        let folder: URL
        init(urls: [URL], folder: URL) { self.urls = urls; self.folder = folder }
    }

    /// Меню после перетаскивания правой кнопкой, как в Windows: «Копировать», «Переместить»,
    /// «Создать ярлыки», «Отменить». Жирным — то, что сделало бы обычное перетаскивание.
    func showRightDropMenu(_ urls: [URL], into folder: URL, suggested: NSDragOperation) {
        guard !urls.isEmpty else { return }
        let request = DropRequest(urls: urls, folder: folder)
        let folderPath = folder.standardizedFileURL.path
        let alreadyThere = urls.allSatisfy { $0.deletingLastPathComponent().standardizedFileURL.path == folderPath }
        // Меню — после того, как сеанс перетаскивания закончится, а не внутри него.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let copy = Menus.item(tr(.dropCopyHere), #selector(self.dropCopyHere(_:)))
            let move = Menus.item(tr(.dropMoveHere), #selector(self.dropMoveHere(_:)))
            let shortcuts = Menus.item(tr(.dropShortcutsHere), #selector(self.dropShortcutsHere(_:)))
            let cancel = Menus.item(tr(.dropCancel), #selector(self.dropCancel(_:)))
            move.isEnabled = !alreadyThere
            let preferred = suggested == .move && !alreadyThere ? move : copy
            preferred.attributedTitle = NSAttributedString(
                string: preferred.title, attributes: [.font: NSFont.boldSystemFont(ofSize: 13)])
            let menu = Menus.menu("", [copy, move, shortcuts, .separator(), cancel])
            menu.autoenablesItems = false
            for item in menu.items {
                item.target = self
                item.representedObject = request
            }
            menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        }
    }

    @objc private func dropCopyHere(_ sender: NSMenuItem) {
        guard let request = sender.representedObject as? DropRequest else { return }
        _ = browserDrop(request.urls, into: request.folder, copy: true)
    }

    @objc private func dropMoveHere(_ sender: NSMenuItem) {
        guard let request = sender.representedObject as? DropRequest else { return }
        _ = browserDrop(request.urls, into: request.folder, copy: false)
    }

    @objc private func dropShortcutsHere(_ sender: NSMenuItem) {
        guard let request = sender.representedObject as? DropRequest else { return }
        let created = ops.createShortcuts(request.urls, in: request.folder)
        if request.folder.standardizedFileURL.path == location.url?.standardizedFileURL.path {
            pendingSelection = created
        }
        reload(preserveSelection: true)
    }

    @objc private func dropCancel(_ sender: Any?) {}
}

/// Подменю «Открыть с помощью»: программа по умолчанию, остальные подходящие по алфавиту,
/// «Выбрать программу…». Для нескольких файлов — программы, которые открывают их все.
enum OpenWithMenu {
    static func item(for urls: [URL]) -> NSMenuItem? {
        guard let first = urls.first else { return nil }
        let workspace = NSWorkspace.shared
        var apps = workspace.urlsForApplications(toOpen: first)
        for url in urls.dropFirst() {
            let paths = Set(workspace.urlsForApplications(toOpen: url).map(\.path))
            apps = apps.filter { paths.contains($0.path) }
        }
        // Одна программа в нескольких копиях (разные версии) — оставляем первую.
        var seen = Set<String>()
        apps = apps.filter { seen.insert(Bundle(url: $0)?.bundleIdentifier ?? $0.path).inserted }
        let defaultApp = workspace.urlForApplication(toOpen: first).flatMap { app in
            apps.first { $0.path == app.path } ?? (urls.count == 1 ? app : nil)
        }
        let others = apps
            .filter { $0.path != defaultApp?.path }
            .sorted { name($0).localizedStandardCompare(name($1)) == .orderedAscending }

        var items: [NSMenuItem] = []
        if let defaultApp { items.append(appItem(defaultApp, title: tr(.openWithDefault, name(defaultApp)))) }
        if !others.isEmpty {
            if !items.isEmpty { items.append(.separator()) }
            items += others.map { appItem($0, title: name($0)) }
        }
        if items.isEmpty {
            let none = Menus.item(tr(.openWithNoApps), nil)
            none.isEnabled = false
            items.append(none)
        }
        items += [.separator(), Menus.item(tr(.openWithOther), #selector(MainWindowController.openWithOther(_:)))]
        return Menus.submenu(tr(.openWith), items)
    }

    private static func name(_ app: URL) -> String {
        FileManager.default.displayName(atPath: app.path)
    }

    private static func appItem(_ app: URL, title: String) -> NSMenuItem {
        let item = Menus.item(title, #selector(MainWindowController.openWithApp(_:)))
        item.representedObject = app
        let icon = NSWorkspace.shared.icon(forFile: app.path)
        icon.size = NSSize(width: 16, height: 16)
        item.image = icon
        item.toolTip = app.path
        return item
    }
}
