import AppKit
import UniformTypeIdentifiers

/// «Сервис → Использовать вместо Finder». Две системные настройки пользователя:
/// - `NSFileViewer` в общих настройках — кого зовёт `NSWorkspace`, когда программа просит «показать
///   в Finder» (так же заменяют Finder Path Finder и ForkLift; настройка не документирована).
///   Действует сразу, уже запущенным программам иногда нужен перезапуск;
/// - программа по умолчанию для папок (`public.folder`) в LaunchServices — кому достаётся `open <папка>`.
///   Штатный вызов (`setDefaultApplication`) macOS 26 для папок отклоняет (paramErr), поэтому запись
///   ещё и кладётся в список обработчиков LaunchServices напрямую — его система читает при входе.
///
/// И показ файла, и открытие папки приходят одним событием «открыть документ» (проверено на macOS 26:
/// ничем, кроме самого пути, они не отличаются) — разбирает его `AppDelegate.application(_:open:)`.
/// Мимо идут программы, которые обращаются к Finder напрямую (AppleScript, идентификатор Finder),
/// и сам Finder: рабочий стол, корзина, диалоги открытия и сохранения.
enum FinderReplacement {
    private static let viewerKey = "NSFileViewer" as CFString
    private static let finderID = "com.apple.finder"
    private static let handlersDomain = "com.apple.LaunchServices/com.apple.launchservices.secure" as CFString
    private static let handlersKey = "LSHandlers" as CFString
    private static let folderType = "public.folder"

    /// Заменить Finder может только собранный .app: системе нужен идентификатор программы.
    private static var bundleID: String? { Instances.canLaunch ? Bundle.main.bundleIdentifier : nil }

    static var available: Bool { bundleID != nil }

    /// Состояние читается из системы, а не хранится у себя: его меняет и другой экземпляр, и `defaults`.
    static var isOn: Bool {
        guard let bundleID else { return false }
        let value = CFPreferencesCopyValue(viewerKey, kCFPreferencesAnyApplication,
                                           kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        return value as? String == bundleID
    }

    static func set(_ on: Bool) {
        guard let bundleID else { return }
        CFPreferencesSetValue(viewerKey, on ? bundleID as CFString : nil, kCFPreferencesAnyApplication,
                              kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        setFolderHandler(on, bundleID: bundleID)
    }

    private static func setFolderHandler(_ on: Bool, bundleID: String) {
        // Список обработчиков: чужие записи не трогаем, свою про папки заменяем или убираем.
        let stored = CFPreferencesCopyValue(handlersKey, handlersDomain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        var handlers = (stored as? [[String: Any]] ?? []).filter { handler in
            guard handler["LSHandlerContentType"] as? String == folderType else { return true }
            // Включаем — прежняя запись о папках (любой программы) уступает нашей; выключаем — уходит только наша.
            return !on && handler["LSHandlerRoleAll"] as? String != bundleID
        }
        if on { handlers.append(["LSHandlerContentType": folderType, "LSHandlerRoleAll": bundleID]) }
        CFPreferencesSetValue(handlersKey, handlers as CFArray, handlersDomain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        CFPreferencesSynchronize(handlersDomain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)

        // Там, где система штатный вызов принимает, смена действует сразу; отказ не ошибка — запись выше остаётся.
        let workspace = NSWorkspace.shared
        let handler: URL?
        if on {
            handler = Bundle.main.bundleURL
        } else {
            let current = workspace.urlForApplication(toOpen: .folder).flatMap { Bundle(url: $0)?.bundleIdentifier }
            handler = current == bundleID ? workspace.urlForApplication(withBundleIdentifier: finderID) : nil
        }
        if let handler { workspace.setDefaultApplication(at: handler, toOpen: .folder) { _ in } }
    }

    /// «Показать в Finder» из самой программы. Пока Finder заменён, системный показ вернулся бы к нам же,
    /// поэтому папку открываем в Finder напрямую — без выделения: выделить файл в Finder можно только
    /// сценарием, а это отдельное разрешение на управление Finder.
    static func showInFinder(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        let workspace = NSWorkspace.shared
        guard isOn, let finder = workspace.urlForApplication(withBundleIdentifier: finderID) else {
            workspace.activateFileViewerSelecting(urls)
            return
        }
        var folders: [URL] = []
        for url in urls {
            let folder = url.deletingLastPathComponent()
            if !folders.contains(where: { $0.path == folder.path }) { folders.append(folder) }
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        workspace.open(folders, withApplicationAt: finder, configuration: configuration)
    }
}
