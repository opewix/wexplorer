import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controllers: [MainWindowController] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = Menus.main()
        CutFiles.startWatching()
        FileExtensions.observeOtherInstances()
        if let directory = Self.snapshotDirectory {
            snapshot(into: directory)
            return
        }
        // Экземпляр, запущенный другим экземпляром, открывается там, куда его послали.
        openWindow(at: Instances.startLocation ?? Self.startLocation(), frame: Instances.startFrame)
        Instances.observeTheme { [weak self] theme, windowsFont in self?.apply(theme, windowsFont: windowsFont) }
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: Снимок окна

    /// `WExplorer -snapshot <папка> [-theme xp|win10] [-snapshotPath <папка для показа>]`: рисует окно
    /// в PNG и выходит — для README и проверки вида без разрешения на запись экрана.
    private static var snapshotDirectory: String? { argument(after: "-snapshot") }

    private static func argument(after flag: String) -> String? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: flag), index + 1 < args.count else { return nil }
        return args[index + 1]
    }

    private func snapshot(into directory: String) {
        let folder = URL(fileURLWithPath: Self.argument(after: "-snapshotPath") ?? "/System/Applications")
        let controller = openWindow(at: .folder(folder), frame: NSRect(x: 100, y: 100, width: 900, height: 600))
        // Список папки читается в фоне — ждём его.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            // Через рамку окна (`themeFrame`), а не `contentView`: иначе строки таблицы в снимок не попадают.
            if let view = controller.window?.contentView?.superview, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.layoutSubtreeIfNeeded()
                view.cacheDisplay(in: view.bounds, to: rep)
                let name = "window-\(Theme.current.rawValue).png"
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: directory).appendingPathComponent(name))
            }
            exit(0)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// Повторный запуск (Spotlight, Dock, `open`). Окна на этом рабочем столе нет — открываем здесь
    /// новое, как Проводник в Windows: окна на других столах не в счёт. Чтобы macOS при этом не уводила
    /// на стол со старым окном, в её настройках выключается «При переключении на программу переходить
    /// в пространство с её открытыми окнами».
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if controllers.contains(where: { $0.window.map { $0.isVisible && $0.isOnActiveSpace } ?? false }) { return true }
        // Свёрнутое окно возвращаем, а не открываем рядом ещё одно.
        if let minimized = controllers.first(where: { $0.window?.isMiniaturized == true })?.window {
            minimized.deminiaturize(nil)
            return false
        }
        // Событие получает один экземпляр, а окно этого стола может быть у другого.
        if let other = Instances.otherWithWindowHere() {
            other.activate(options: [.activateIgnoringOtherApps])
            return true
        }
        if flag {
            // Свои окна — на других столах: новое открываем по общим правилам (отдельным экземпляром).
            openNewWindow(at: .folder(Places.home), near: nil)
        } else {
            openWindow(at: .folder(Places.home))
        }
        return true
    }

    /// Открывается там, где закрыли в прошлый раз.
    private static func startLocation() -> Location {
        if let path = Settings.load().lastPath, FileManager.default.fileExists(atPath: path) {
            return .folder(URL(fileURLWithPath: path))
        }
        return .folder(Places.home)
    }

    /// frame — пересборка окна при смене темы: то же место на экране, та же история.
    @discardableResult
    func openWindow(at location: Location, history: NavigationHistory = NavigationHistory(),
                    frame: NSRect? = nil, autosave: Bool = false) -> MainWindowController {
        let controller = MainWindowController(location: location, history: history)
        if let window = controller.window {
            if let frame {
                window.setFrame(frame, display: false)
                if autosave { window.setFrameAutosaveName("MainWindow") }
            } else if let current = NSApp.keyWindow ?? controllers.last?.window {
                window.setFrame(current.frame, display: false)
                window.setFrameTopLeftPoint(window.cascadeTopLeft(from: NSPoint(x: current.frame.minX, y: current.frame.maxY)))
            } else if !window.setFrameUsingName("MainWindow") {
                window.center()
            }
            // Имя автосохранения сразу подставляет сохранённую рамку — окну с заданной рамкой его не даём.
            if frame == nil && controllers.isEmpty { window.setFrameAutosaveName("MainWindow") }
        }
        controllers.append(controller)
        controller.showWindow(nil)
        controller.applyInitialSidebarWidth()
        return controller
    }

    func windowDidClose(_ controller: MainWindowController) {
        controllers.removeAll { $0 === controller }
    }

    /// «Сервис → Язык». Язык меняется после перезапуска — тогда переводятся и системные надписи.
    @objc func setLanguage(_ sender: NSMenuItem) {
        guard let code = sender.representedObject as? String, let language = L10n.language(code),
              code != (L10n.chosenCode ?? L10n.current.code) else { return }
        L10n.choose(language)
        guard language.code != L10n.current.code else { return }
        let alert = NSAlert()
        alert.messageText = L10n.tr(.languageChangedTitle, in: language)
        alert.informativeText = L10n.tr(.languageChangedText, in: language, L10n.appName)
        alert.addButton(withTitle: L10n.tr(.restartNow, in: language))
        alert.addButton(withTitle: L10n.tr(.later, in: language))
        if alert.runModal() == .alertFirstButtonReturn { relaunch() }
    }

    /// Ждёт завершения текущего процесса и открывает приложение заново.
    private func relaunch() {
        let path = Bundle.main.bundlePath
        guard path.hasSuffix(".app") else {
            NSApp.terminate(nil)
            return
        }
        let pid = ProcessInfo.processInfo.processIdentifier
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done; /usr/bin/open \"$0\"", path]
        try? task.run()
        NSApp.terminate(nil)
    }

    /// Новое окно по команде пользователя. В режиме «отдельная иконка в Dock» — новый экземпляр.
    func openNewWindow(at location: Location, near frame: NSRect?) {
        guard Instances.separate, Instances.canLaunch else {
            openWindow(at: location)
            return
        }
        Instances.launch(at: location, near: frame) { [weak self] in
            Alerts.error(tr(.cannotOpenWindow))
            self?.openWindow(at: location)
        }
    }

    @objc func toggleSeparateInstances(_ sender: Any?) {
        Instances.separate.toggle()
        NSApp.mainMenu = Menus.main()
    }

    /// «Вид → Тема». Тема меняется и в остальных экземплярах программы.
    @objc func setTheme(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let theme = Theme(rawValue: raw),
              theme != Theme.current else { return }
        apply(theme)
        Instances.broadcast(theme)
    }

    /// «Вид → Шрифт как в Windows». Шрифт меняется и в остальных экземплярах программы.
    @objc func toggleWindowsFont(_ sender: Any?) {
        apply(Theme.current, windowsFont: !Fonts.windows)
        Instances.broadcast(Theme.current)
    }

    /// Каждое окно пересобирается на месте: та же папка, история и рамка.
    private func apply(_ theme: Theme, windowsFont: Bool = Fonts.windows) {
        guard theme != Theme.current || windowsFont != Fonts.windows else { return }
        if theme != Theme.current { Theme.choose(theme) }
        if windowsFont != Fonts.windows { Fonts.windows = windowsFont }
        NSApp.mainMenu = Menus.main()
        let key = NSApp.keyWindow
        var newKey: MainWindowController?
        // Перебираем копию: закрытие и открытие окон меняют `controllers`.
        for old in controllers {
            guard let window = old.window else { continue }
            let frame = window.frame
            let autosave = window.frameAutosaveName == "MainWindow"
            let wasKey = window === key
            // Сначала закрываем: имя автосохранения рамки должно освободиться для нового окна.
            window.setFrameAutosaveName("")
            window.close()
            let controller = openWindow(at: old.location, history: old.history, frame: frame, autosave: autosave)
            if wasKey { newKey = controller }
        }
        newKey?.window?.makeKeyAndOrderFront(nil)
    }

    @objc func newWindow(_ sender: Any?) {
        let key = NSApp.keyWindow?.windowController as? MainWindowController
        // Из «Компьютера» — снова «Компьютер», из результатов поиска — папка, где искали.
        var place = key?.location ?? .folder(Places.home)
        if case .search(_, let scope) = place { place = .folder(scope) }
        openNewWindow(at: place, near: key?.window?.frame)
    }
}
