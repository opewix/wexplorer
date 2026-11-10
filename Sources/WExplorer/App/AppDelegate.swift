import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controllers: [MainWindowController] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = Menus.main()
        openWindow(at: Self.startLocation())
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { openWindow(at: .folder(Places.home)) }
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
            if controllers.isEmpty { window.setFrameAutosaveName("MainWindow") }
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

    /// «Вид → Тема». Каждое окно пересобирается на месте: та же папка, история и рамка.
    @objc func setTheme(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let theme = Theme(rawValue: raw),
              theme != Theme.current else { return }
        Theme.choose(theme)
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
        let current = (NSApp.keyWindow?.windowController as? MainWindowController)?.location.url
        openWindow(at: .folder(current ?? Places.home))
    }
}
