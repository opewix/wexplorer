import AppKit

/// Файловые операции окна: копирование, перемещение, корзина, переименование — с отменой (Cmd+Z).
final class FileOperations {
    enum Kind { case copy, move }

    private struct Step {
        let source: URL
        let destination: URL
        let replace: Bool
    }

    private weak var window: NSWindow?
    private var undoManager: UndoManager? { window?.undoManager }
    private let fm = FileManager.default

    init(window: NSWindow?) {
        self.window = window
    }

    // MARK: Копирование и перемещение

    /// Копирует или перемещает объекты в папку в фоне, с окном прогресса.
    /// `completion` получает адреса созданных объектов.
    func transfer(_ sources: [URL], to folder: URL, kind: Kind, completion: @escaping ([URL]) -> Void) {
        guard let steps = plan(sources, to: folder, kind: kind), !steps.isEmpty else {
            completion([])
            return
        }
        let progress = ProgressPanel(title: kind == .copy ? tr(.copying) : tr(.moving), parent: window)
        progress.showAfterDelay()
        DispatchQueue.global(qos: .userInitiated).async {
            let fm = FileManager()
            var done: [Step] = []
            var errors: [String] = []
            for (index, step) in steps.enumerated() {
                if progress.isCancelled { break }
                DispatchQueue.main.async {
                    progress.update(index: index, total: steps.count, source: step.source, destination: folder)
                }
                do {
                    if step.replace {
                        try fm.trashItem(at: step.destination, resultingItemURL: nil)
                    }
                    switch kind {
                    case .copy: try fm.copyItem(at: step.source, to: step.destination)
                    case .move: try fm.moveItem(at: step.source, to: step.destination)
                    }
                    done.append(step)
                } catch {
                    errors.append("«\(step.source.lastPathComponent)»: \(error.localizedDescription)")
                }
            }
            DispatchQueue.main.async {
                progress.close()
                self.registerUndo(for: done, kind: kind)
                if !errors.isEmpty {
                    Alerts.error(kind == .copy ? tr(.copyFailedSome) : tr(.moveFailedSome),
                                 info: errors.prefix(10).joined(separator: "\n"))
                }
                completion(done.map(\.destination))
            }
        }
    }

    /// Готовит шаги и задаёт вопросы о конфликтах имён. nil — операция отменена.
    private func plan(_ sources: [URL], to folder: URL, kind: Kind) -> [Step]? {
        let dest = folder.standardizedFileURL
        var steps: [Step] = []
        var replaceAll = false
        for raw in sources {
            let src = raw.standardizedFileURL
            if dest.path == src.path || dest.path.hasPrefix(src.path + "/") {
                let name = src.lastPathComponent
                Alerts.error(kind == .copy ? tr(.cannotCopyItem, name) : tr(.cannotMoveItem, name),
                             info: tr(.destinationInsideSource))
                return nil
            }
            if src.deletingLastPathComponent().path == dest.path {
                if kind == .move { continue }
                steps.append(Step(source: src, destination: uniqueCopyURL(for: src), replace: false))
                continue
            }
            let target = dest.appendingPathComponent(src.lastPathComponent)
            var replace = false
            if fm.fileExists(atPath: target.path) {
                if !replaceAll {
                    switch Alerts.confirmReplace(src.lastPathComponent) {
                    case .yes: break
                    case .yesToAll: replaceAll = true
                    case .no: continue
                    case .cancel: return nil
                    }
                }
                replace = true
            }
            steps.append(Step(source: src, destination: target, replace: replace))
        }
        return steps
    }

    /// «Копия файл.txt» / «Copy of file.txt», затем с номером — как в XP.
    private func uniqueCopyURL(for src: URL) -> URL {
        let dir = src.deletingLastPathComponent()
        let name = src.lastPathComponent
        var n = 1
        while true {
            let candidate = dir.appendingPathComponent(n == 1 ? tr(.copyOfName, name) : tr(.copyOfNameNumbered, name, n))
            if !fm.fileExists(atPath: candidate.path) { return candidate }
            n += 1
        }
    }

    private func registerUndo(for steps: [Step], kind: Kind) {
        guard !steps.isEmpty else { return }
        switch kind {
        case .copy:
            let created = steps.map(\.destination)
            undoManager?.registerUndo(withTarget: self) { ops in
                _ = ops.trash(created, confirm: false, actionName: tr(.actionCopy))
            }
            undoManager?.setActionName(tr(.actionCopy))
        case .move:
            register(moves: steps.map { ($0.source, $0.destination) }, actionName: tr(.actionMove))
        }
    }

    // MARK: Синхронные перемещения (переименование, отмена)

    /// Перемещает пары «откуда → куда» и регистрирует обратную операцию.
    @discardableResult
    func move(_ pairs: [(URL, URL)], actionName: String) -> [URL] {
        var done: [(URL, URL)] = []
        for (from, to) in pairs {
            do {
                try moveItem(from, to)
                done.append((from, to))
            } catch {
                Alerts.error(tr(.cannotMove, from.lastPathComponent), info: error.localizedDescription)
            }
        }
        register(moves: done, actionName: actionName)
        return done.map(\.1)
    }

    private func register(moves: [(URL, URL)], actionName: String) {
        guard !moves.isEmpty else { return }
        let inverse = moves.map { ($0.1, $0.0) }
        undoManager?.registerUndo(withTarget: self) { ops in ops.move(inverse, actionName: actionName) }
        undoManager?.setActionName(actionName)
    }

    /// Учитывает переименование с изменением только регистра на нечувствительной к регистру ФС.
    private func moveItem(_ from: URL, _ to: URL) throws {
        if from.path != to.path && from.path.lowercased() == to.path.lowercased() {
            let temp = from.deletingLastPathComponent().appendingPathComponent(".wexplorer-\(UUID().uuidString)")
            try fm.moveItem(at: from, to: temp)
            try fm.moveItem(at: temp, to: to)
        } else {
            try fm.moveItem(at: from, to: to)
        }
    }

    // MARK: Корзина, переименование, новая папка

    @discardableResult
    func trash(_ urls: [URL], confirm: Bool, actionName: String = tr(.actionDelete)) -> Bool {
        guard !urls.isEmpty else { return false }
        if confirm && !Alerts.confirmTrash(urls) { return false }
        var pairs: [(URL, URL)] = []
        for url in urls {
            do {
                var result: NSURL?
                try fm.trashItem(at: url, resultingItemURL: &result)
                if let result { pairs.append((url, result as URL)) }
            } catch {
                Alerts.error(tr(.cannotDelete, url.lastPathComponent), info: error.localizedDescription)
            }
        }
        guard !pairs.isEmpty else { return false }
        let restore = pairs.map { ($0.1, $0.0) }
        undoManager?.registerUndo(withTarget: self) { ops in ops.move(restore, actionName: actionName) }
        undoManager?.setActionName(actionName)
        return true
    }

    /// Удаление мимо корзины (Shift+Delete). Отменить его нельзя, поэтому подтверждение — всегда.
    /// Удаляет в фоне с окном прогресса: большая папка удаляется не мгновенно.
    func deletePermanently(_ urls: [URL], completion: @escaping () -> Void) {
        guard !urls.isEmpty, Alerts.confirmPermanentDelete(urls) else { return }
        let progress = ProgressPanel(title: tr(.deleting), parent: window)
        progress.showAfterDelay()
        DispatchQueue.global(qos: .userInitiated).async {
            let fm = FileManager()
            var errors: [String] = []
            for (index, url) in urls.enumerated() {
                if progress.isCancelled { break }
                DispatchQueue.main.async {
                    progress.update(index: index, total: urls.count, source: url, destination: nil)
                }
                do {
                    try fm.removeItem(at: url)
                } catch {
                    errors.append("«\(url.lastPathComponent)»: \(error.localizedDescription)")
                }
            }
            DispatchQueue.main.async {
                progress.close()
                if !errors.isEmpty {
                    Alerts.error(tr(.cannotDelete, urls.count == 1 ? urls[0].lastPathComponent : "…"),
                                 info: errors.prefix(10).joined(separator: "\n"))
                }
                completion()
            }
        }
    }

    /// Ярлыки (в macOS — псевдонимы Finder) для объектов в папке. Имя — как в Windows:
    /// «Ярлык для X» в XP, «X — ярлык» в Windows 10. Возвращает созданные ярлыки.
    @discardableResult
    func createShortcuts(_ urls: [URL], in folder: URL) -> [URL] {
        var created: [URL] = []
        for src in urls {
            let target = uniqueShortcutURL(for: src, in: folder)
            do {
                let data = try src.bookmarkData(options: .suitableForBookmarkFile,
                                                includingResourceValuesForKeys: nil, relativeTo: nil)
                try URL.writeBookmarkData(data, to: target)
                created.append(target)
            } catch {
                Alerts.error(tr(.cannotCreateShortcut, src.lastPathComponent), info: error.localizedDescription)
            }
        }
        if !created.isEmpty {
            let made = created
            undoManager?.registerUndo(withTarget: self) { ops in
                _ = ops.trash(made, confirm: false, actionName: tr(.actionCreateShortcut))
            }
            undoManager?.setActionName(tr(.actionCreateShortcut))
        }
        return created
    }

    private func uniqueShortcutURL(for src: URL, in folder: URL) -> URL {
        let name = src.lastPathComponent
        var n = 1
        while true {
            let title: String
            if Theme.isWin10 {
                title = n == 1 ? tr(.nameShortcut, name) : tr(.nameShortcutNumbered, name, n)
            } else {
                title = n == 1 ? tr(.shortcutTo, name) : tr(.shortcutToNumbered, name, n)
            }
            let candidate = folder.appendingPathComponent(title)
            if !fm.fileExists(atPath: candidate.path) { return candidate }
            n += 1
        }
    }

    func rename(_ url: URL, to newName: String) -> URL? {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, name != url.lastPathComponent else { return nil }
        if name.contains("/") || name.contains(":") {
            Alerts.error(tr(.invalidCharacters), info: "/  :")
            return nil
        }
        let target = url.deletingLastPathComponent().appendingPathComponent(name)
        if fm.fileExists(atPath: target.path) && target.path.lowercased() != url.path.lowercased() {
            Alerts.error(tr(.cannotRename, url.lastPathComponent), info: tr(.nameExists, name))
            return nil
        }
        return move([(url, target)], actionName: tr(.actionRename)).first
    }

    func createFolder(in dir: URL) -> URL? {
        var n = 1
        var url: URL
        repeat {
            url = dir.appendingPathComponent(n == 1 ? tr(.newFolderName) : tr(.newFolderNameNumbered, n))
            n += 1
        } while fm.fileExists(atPath: url.path)
        do {
            try fm.createDirectory(at: url, withIntermediateDirectories: false)
        } catch {
            Alerts.error(tr(.cannotCreateFolder), info: error.localizedDescription)
            return nil
        }
        let created = url
        undoManager?.registerUndo(withTarget: self) { ops in
            _ = ops.trash([created], confirm: false, actionName: tr(.actionNewFolder))
        }
        undoManager?.setActionName(tr(.actionNewFolder))
        return url
    }

    /// «Новый текстовый документ.txt» / «New Text Document.txt», затем с номером — как в Windows.
    func createTextFile(in dir: URL) -> URL? {
        var n = 1
        var url: URL
        repeat {
            let base = n == 1 ? tr(.newTextDocumentName) : tr(.newTextDocumentNameNumbered, n)
            url = dir.appendingPathComponent(base + ".txt")
            n += 1
        } while fm.fileExists(atPath: url.path)
        guard fm.createFile(atPath: url.path, contents: Data()) else {
            Alerts.error(tr(.cannotCreateTextDocument), info: tr(.noWritePermission))
            return nil
        }
        let created = url
        undoManager?.registerUndo(withTarget: self) { ops in
            _ = ops.trash([created], confirm: false, actionName: tr(.actionNewDocument))
        }
        undoManager?.setActionName(tr(.actionNewDocument))
        return url
    }
}
