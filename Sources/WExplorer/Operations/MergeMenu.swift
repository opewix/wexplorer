import AppKit

/// Пункт «WMerge» в контекстных меню — как «WinMerge» в Проводнике Windows.
///
/// Работает через программу WMerge (github.com/opewix/wmerge): пункт открывает её ссылкой
/// `wmerge://compare?path=…&path=…`. Не установлена — пункта нет. Что делать с путями, решает она:
/// ничего не выбрано — пустое окно выбора, один объект — он слева, два — сразу сравнение.
enum MergeMenu {
    private static let bundleID = "dev.oleg.wmerge"

    /// Пункт для выбранных объектов; пустой список — щелчок по пустому месту папки.
    static func items(for urls: [URL]) -> [NSMenuItem] {
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return [] }
        let paths = urls.map(\.path)
        let item = ActionMenuItem(title: "WMerge") { run(paths: paths) }
        let icon = NSWorkspace.shared.icon(forFile: app.path)
        icon.size = NSSize(width: 16, height: 16)
        item.image = icon
        return [item]
    }

    private static func run(paths: [String]) {
        var parts = URLComponents()
        parts.scheme = "wmerge"
        parts.host = "compare"
        if !paths.isEmpty { parts.queryItems = paths.map { URLQueryItem(name: "path", value: $0) } }
        if let url = parts.url { NSWorkspace.shared.open(url) }
    }
}
