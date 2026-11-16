import AppKit

/// Файловые операции окна: копирование, перемещение, корзина, переименование — с отменой (Cmd+Z).
final class FileOperations {
    enum Kind { case copy, move }

    private struct Step {
        let source: URL
        let destination: URL
        let replace: Bool
    }

    /// Выполненный шаг: `replaced` — куда в корзине лёг объект, который заменили.
    private struct Done {
        let source: URL
        let destination: URL
        var replaced: URL?
    }

    /// Прерывает копирование и удаление папки посреди неё: FileManager спрашивает про каждый вложенный
    /// объект. Для перемещения не годится — между дисками оно копирует и затем удаляет источник,
    /// и пропущенные при копировании объекты пропали бы.
    private final class CancelGuard: NSObject, FileManagerDelegate {
        private let isCancelled: () -> Bool
        init(_ isCancelled: @escaping () -> Bool) { self.isCancelled = isCancelled }
        func fileManager(_ fileManager: FileManager, shouldCopyItemAt srcURL: URL, to dstURL: URL) -> Bool { !isCancelled() }
        func fileManager(_ fileManager: FileManager, shouldRemoveItemAt URL: URL) -> Bool { !isCancelled() }
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
            let guardian = CancelGuard { progress.isCancelled }
            var done: [Done] = []
            var errors: [String] = []
            for (index, step) in steps.enumerated() {
                if progress.isCancelled { break }
                DispatchQueue.main.async {
                    progress.update(index: index, total: steps.count, source: step.source, destination: folder)
                }
                var replaced: NSURL?
                do {
                    if step.replace {
                        try fm.trashItem(at: step.destination, resultingItemURL: &replaced)
                    }
                    switch kind {
                    case .copy:
                        fm.delegate = guardian
                        defer { fm.delegate = nil }
                        try fm.copyItem(at: step.source, to: step.destination)
                    case .move:
                        try fm.moveItem(at: step.source, to: step.destination)
                    }
                    if kind == .copy && progress.isCancelled {
                        // Отменили посреди папки: недописанную копию убираем, заменённое возвращаем.
                        try? fm.removeItem(at: step.destination)
                        if let replaced = replaced as URL? { try? fm.moveItem(at: replaced, to: step.destination) }
                        break
                    }
                    done.append(Done(source: step.source, destination: step.destination, replaced: replaced as URL?))
                } catch {
                    errors.append("«\(step.source.lastPathComponent)»: \(error.localizedDescription)")
                    // Не получилось — прежний объект возвращаем из корзины на место, убрав недописанную копию.
                    if let replaced = replaced as URL? {
                        try? fm.removeItem(at: step.destination)
                        try? fm.moveItem(at: replaced, to: step.destination)
                    }
                }
            }
            DispatchQueue.main.async {
                progress.close()
                withExtendedLifetime(guardian) {}
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
        // Имена, уже занятые этой же операцией: два одноимённых объекта из разных папок.
        var claimed = Set<String>()
        for raw in sources {
            let src = raw.standardizedFileURL
            let name = src.lastPathComponent
            let cannot = kind == .copy ? tr(.cannotCopyItem, name) : tr(.cannotMoveItem, name)
            if FileIdentity.isInside(dest, src) {
                Alerts.error(cannot, info: tr(.destinationInsideSource))
                return nil
            }
            if FileIdentity.sameFolder(src.deletingLastPathComponent(), dest) {
                if kind == .move { continue }
                steps.append(Step(source: src, destination: uniqueCopyURL(for: src), replace: false))
                continue
            }
            let target = dest.appendingPathComponent(name)
            guard claimed.insert(target.path.lowercased()).inserted else {
                // Иначе второй объект отправил бы в корзину только что перенесённый первый.
                Alerts.error(cannot, info: tr(.nameExists, name))
                continue
            }
            var replace = false
            if fm.fileExists(atPath: target.path) {
                // Замена отправляет прежний объект в корзину — это не должен быть сам источник
                // и не папка, в которой он лежит.
                if FileIdentity.same(target, src) { continue }
                if FileIdentity.isInside(src, target) {
                    Alerts.error(cannot, info: tr(.nameExists, name))
                    continue
                }
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

    private func registerUndo(for done: [Done], kind: Kind) {
        guard !done.isEmpty else { return }
        undoManager?.registerUndo(withTarget: self) { ops in ops.undoTransfer(done, kind: kind) }
        undoManager?.setActionName(kind == .copy ? tr(.actionCopy) : tr(.actionMove))
    }

    /// Отмена копирования или перемещения: копия уходит в корзину (перемещённое — обратно), а то, что
    /// было заменено, возвращается из корзины на своё место.
    private func undoTransfer(_ done: [Done], kind: Kind) {
        // `parked` — куда в корзине легла отменённая копия: оттуда её вернёт повтор.
        var undone: [(step: Done, parked: URL?)] = []
        var errors: [String] = []
        for step in done {
            do {
                var parked: NSURL?
                switch kind {
                case .copy: try fm.trashItem(at: step.destination, resultingItemURL: &parked)
                case .move: try moveItem(step.destination, step.source)
                }
                if let replaced = step.replaced { try fm.moveItem(at: replaced, to: step.destination) }
                undone.append((step, parked as URL?))
            } catch {
                errors.append("«\(step.destination.lastPathComponent)»: \(error.localizedDescription)")
            }
        }
        report(errors, kind: kind)
        guard !undone.isEmpty else { return }
        undoManager?.registerUndo(withTarget: self) { ops in ops.redoTransfer(undone, kind: kind) }
        undoManager?.setActionName(kind == .copy ? tr(.actionCopy) : tr(.actionMove))
    }

    private func redoTransfer(_ undone: [(step: Done, parked: URL?)], kind: Kind) {
        var done: [Done] = []
        var errors: [String] = []
        for (step, parked) in undone {
            do {
                var replaced: NSURL?
                if step.replaced != nil { try fm.trashItem(at: step.destination, resultingItemURL: &replaced) }
                switch kind {
                case .copy:
                    guard let parked else { continue }
                    try fm.moveItem(at: parked, to: step.destination)
                case .move:
                    try moveItem(step.source, step.destination)
                }
                done.append(Done(source: step.source, destination: step.destination, replaced: replaced as URL?))
            } catch {
                errors.append("«\(step.source.lastPathComponent)»: \(error.localizedDescription)")
            }
        }
        report(errors, kind: kind)
        registerUndo(for: done, kind: kind)
    }

    private func report(_ errors: [String], kind: Kind) {
        guard !errors.isEmpty else { return }
        Alerts.error(kind == .copy ? tr(.copyFailedSome) : tr(.moveFailedSome), info: errors.prefix(10).joined(separator: "\n"))
    }

    // MARK: Синхронные перемещения (переименование, отмена)

    /// Перемещает пары «откуда → куда» и регистрирует обратную операцию.
    @discardableResult
    func move(_ pairs: [(URL, URL)], actionName: String) -> [URL] {
        var done: [(URL, URL)] = []
        var errors: [String] = []
        for (from, to) in pairs {
            do {
                try moveItem(from, to)
                done.append((from, to))
            } catch {
                errors.append("«\(from.lastPathComponent)»: \(error.localizedDescription)")
            }
        }
        // Одно окно на все ошибки, а не по окну на объект.
        if let first = pairs.first, !errors.isEmpty {
            Alerts.error(tr(.cannotMove, pairs.count == 1 ? first.0.lastPathComponent : "…"),
                         info: errors.prefix(10).joined(separator: "\n"))
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
            // На чувствительном к регистру диске «a.txt» и «A.txt» — разные файлы: чужой не затираем.
            if fm.fileExists(atPath: to.path) && !FileIdentity.same(from, to) {
                throw CocoaError(.fileWriteFileExists, userInfo: [NSFilePathErrorKey: to.path])
            }
            let temp = from.deletingLastPathComponent().appendingPathComponent(".wexplorer-\(UUID().uuidString)")
            try fm.moveItem(at: from, to: temp)
            do {
                try fm.moveItem(at: temp, to: to)
            } catch {
                // Иначе файл остался бы скрытым под временным именем.
                try? fm.moveItem(at: temp, to: from)
                throw error
            }
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
        var errors: [String] = []
        for url in urls {
            do {
                var result: NSURL?
                try fm.trashItem(at: url, resultingItemURL: &result)
                if let result { pairs.append((url, result as URL)) }
            } catch {
                errors.append("«\(url.lastPathComponent)»: \(error.localizedDescription)")
            }
        }
        // Одно окно на все ошибки: на диске без корзины иначе было бы по окну на каждый объект.
        if !errors.isEmpty {
            Alerts.error(tr(.cannotDelete, urls.count == 1 ? urls[0].lastPathComponent : "…"),
                         info: errors.prefix(10).joined(separator: "\n"))
        }
        guard !pairs.isEmpty else { return false }
        let restore = pairs.map { ($0.1, $0.0) }
        undoManager?.registerUndo(withTarget: self) { ops in ops.move(restore, actionName: actionName) }
        undoManager?.setActionName(actionName)
        return true
    }

    /// То же в фоне с окном прогресса и «Отменой» — для выделения пользователя: большое выделение или
    /// диск без быстрой корзины иначе подвешивали окно. `completion(true)` — что-то удалено.
    func trashInBackground(_ urls: [URL], confirm: Bool, completion: @escaping (Bool) -> Void) {
        guard !urls.isEmpty, !confirm || Alerts.confirmTrash(urls) else { return }
        let actionName = tr(.actionDelete)
        let progress = ProgressPanel(title: tr(.deleting), parent: window)
        progress.showAfterDelay()
        DispatchQueue.global(qos: .userInitiated).async {
            let fm = FileManager()
            var pairs: [(URL, URL)] = []
            var errors: [String] = []
            for (index, url) in urls.enumerated() {
                if progress.isCancelled { break }
                DispatchQueue.main.async { progress.update(index: index, total: urls.count, source: url, destination: nil) }
                do {
                    var result: NSURL?
                    try fm.trashItem(at: url, resultingItemURL: &result)
                    if let result { pairs.append((url, result as URL)) }
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
                if !pairs.isEmpty {
                    let restore = pairs.map { ($0.1, $0.0) }
                    self.undoManager?.registerUndo(withTarget: self) { ops in ops.move(restore, actionName: actionName) }
                    self.undoManager?.setActionName(actionName)
                }
                completion(!pairs.isEmpty)
            }
        }
    }

    /// Удаление мимо корзины (Shift+Delete). Отменить его нельзя, поэтому подтверждение — всегда.
    /// Удаляет в фоне с окном прогресса: большая папка удаляется не мгновенно.
    func deletePermanently(_ urls: [URL], completion: @escaping () -> Void) {
        guard !urls.isEmpty, Alerts.confirmPermanentDelete(urls) else { return }
        let progress = ProgressPanel(title: tr(.deleting), parent: window)
        progress.showAfterDelay()
        DispatchQueue.global(qos: .userInitiated).async {
            let fm = FileManager()
            // «Отмена» останавливает удаление и посреди большой папки: что не успело удалиться — остаётся.
            let guardian = CancelGuard { progress.isCancelled }
            fm.delegate = guardian
            var errors: [String] = []
            for (index, url) in urls.enumerated() {
                if progress.isCancelled { break }
                DispatchQueue.main.async {
                    progress.update(index: index, total: urls.count, source: url, destination: nil)
                }
                do {
                    try fm.removeItem(at: url)
                } catch {
                    // Прерванная папка «не удаляется, потому что не пуста» — это не ошибка.
                    if !progress.isCancelled { errors.append("«\(url.lastPathComponent)»: \(error.localizedDescription)") }
                }
            }
            withExtendedLifetime(guardian) {}
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
        if fm.fileExists(atPath: target.path) && !FileIdentity.same(target, url) {
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

/// Один ли это объект на диске и лежит ли один внутри другого. Сравнение путей строками тут не годится:
/// до одной папки ведут разные написания — ссылка, другой регистр букв в набранном адресе.
enum FileIdentity {
    static func same(_ a: URL, _ b: URL) -> Bool {
        if a.standardizedFileURL.path == b.standardizedFileURL.path { return true }
        guard let first = try? a.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier,
              let second = try? b.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier else { return false }
        return first.isEqual(second)
    }

    /// Одна ли это папка; в отличие от `same`, ссылка на папку считается самой папкой.
    static func sameFolder(_ a: URL, _ b: URL) -> Bool {
        same(a.resolvingSymlinksInPath(), b.resolvingSymlinksInPath())
    }

    /// `inner` — это сам `outer` или лежит где-то в нём.
    static func isInside(_ inner: URL, _ outer: URL) -> Bool {
        var current = inner.resolvingSymlinksInPath().standardizedFileURL
        while true {
            if same(current, outer) { return true }
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path { return false }
            current = parent
        }
    }
}
