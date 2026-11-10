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

    @discardableResult
    func openWindow(at location: Location) -> MainWindowController {
        let controller = MainWindowController(location: location)
        if let window = controller.window {
            if let current = NSApp.keyWindow ?? controllers.last?.window {
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

    @objc func newWindow(_ sender: Any?) {
        let current = (NSApp.keyWindow?.windowController as? MainWindowController)?.location.url
        openWindow(at: .folder(current ?? Places.home))
    }
}
