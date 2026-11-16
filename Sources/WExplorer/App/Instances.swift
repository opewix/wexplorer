import AppKit

/// Режим «отдельная иконка в Dock для каждого окна». Dock показывает одну иконку на процесс,
/// поэтому новое окно в этом режиме — новый экземпляр программы. Экземпляры общаются через
/// общие настройки, буфер обмена (отметка «вырезано») и системные уведомления (смена темы).
enum Instances {
    private static let key = "separateInstances"
    private static let pathFlag = "--wexplorer-path"
    private static let computerFlag = "--wexplorer-computer"
    private static let frameFlag = "--wexplorer-frame"
    private static let themeChanged = Notification.Name("dev.oleg.wexplorer.themeChanged")

    /// Включён по умолчанию: пока пользователь не выключил, ключа в настройках нет.
    static var separate: Bool {
        get { UserDefaults.standard.object(forKey: key) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    /// Запустить второй экземпляр можно только из собранного .app (не из `swift run`).
    static var canLaunch: Bool { Bundle.main.bundleURL.pathExtension == "app" }

    /// Новый экземпляр: открыться в `location`, окно — уступом от `frame`. При ошибке — `failure`.
    static func launch(at location: Location, near frame: NSRect?, failure: @escaping () -> Void) {
        var arguments: [String] = []
        switch location {
        case .folder(let url): arguments += [pathFlag, url.path]
        case .computer: arguments.append(computerFlag)
        case .search(_, let scope): arguments += [pathFlag, scope.path]
        }
        if let frame {
            let r = frame.offsetBy(dx: 24, dy: -24)
            arguments += [frameFlag, [r.minX, r.minY, r.width, r.height].map { "\(Int($0))" }.joined(separator: ",")]
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.arguments = arguments
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, error in
            guard error != nil else { return }
            DispatchQueue.main.async(execute: failure)
        }
    }

    /// Другой экземпляр программы, у которого есть окно на текущем рабочем столе. Список окон
    /// «на экране» WindowServer отдаёт только с текущего стола; разрешений для номера процесса не нужно.
    static func otherWithWindowHere() -> NSRunningApplication? {
        let own = ProcessInfo.processInfo.processIdentifier
        let others = NSWorkspace.shared.runningApplications.filter {
            $0.processIdentifier != own && $0.bundleURL == Bundle.main.bundleURL
        }
        guard !others.isEmpty else { return nil }
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        for info in list {
            // Обычный уровень и размер окна, а не всплывашки или служебной полоски.
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  let bounds = (info[kCGWindowBounds as String] as? NSDictionary).flatMap({ CGRect(dictionaryRepresentation: $0) }),
                  bounds.width >= 150, bounds.height >= 150,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  let app = others.first(where: { $0.processIdentifier == pid }) else { continue }
            return app
        }
        return nil
    }

    // MARK: Аргументы запуска этого экземпляра

    private static func value(after flag: String) -> String? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: flag), index + 1 < args.count else { return nil }
        return args[index + 1]
    }

    /// Куда открыть первое окно, если экземпляр запущен другим экземпляром.
    static var startLocation: Location? {
        if ProcessInfo.processInfo.arguments.contains(computerFlag) { return .computer }
        guard let path = value(after: pathFlag), FileManager.default.fileExists(atPath: path) else { return nil }
        return .folder(URL(fileURLWithPath: path))
    }

    static var startFrame: NSRect? {
        let parts = value(after: frameFlag)?.split(separator: ",").compactMap { Double($0) } ?? []
        guard parts.count == 4 else { return nil }
        return NSRect(x: parts[0], y: parts[1], width: parts[2], height: parts[3])
    }

    // MARK: Смена темы во всех экземплярах

    /// Тема и шрифт уходят вместе: получатель применяет то, что у него отличается.
    static func broadcast(_ theme: Theme) {
        DistributedNotificationCenter.default().postNotificationName(
            themeChanged, object: theme.rawValue,
            userInfo: ["pid": Int(ProcessInfo.processInfo.processIdentifier), "windowsFont": Fonts.windows],
            deliverImmediately: true)
    }

    static func observeTheme(_ handler: @escaping (Theme, Bool) -> Void) {
        DistributedNotificationCenter.default().addObserver(forName: themeChanged, object: nil, queue: .main) { note in
            let pid = note.userInfo?["pid"] as? Int
            guard pid != Int(ProcessInfo.processInfo.processIdentifier),
                  let raw = note.object as? String, let theme = Theme(rawValue: raw) else { return }
            handler(theme, note.userInfo?["windowsFont"] as? Bool ?? Fonts.windows)
        }
    }
}
