import Foundation

enum ViewMode: Int, CaseIterable {
    case thumbnails, tiles, icons, list, details

    var title: String {
        switch self {
        case .thumbnails: return tr(.viewThumbnails)
        case .tiles: return tr(.viewTiles)
        case .icons: return tr(.viewIcons)
        case .list: return tr(.viewList)
        case .details: return tr(.viewDetails)
        }
    }
}

enum SortKey: Int, CaseIterable {
    case name, size, type, modified

    var title: String {
        switch self {
        case .name: return tr(.columnName)
        case .size: return tr(.columnSize)
        case .type: return tr(.columnType)
        case .modified: return tr(.columnModified)
        }
    }

    var menuTitle: String {
        switch self {
        case .name: return tr(.columnName)
        case .size: return tr(.columnSize)
        case .type: return tr(.columnType)
        case .modified: return tr(.sortModified)
        }
    }

    var columnID: String {
        switch self {
        case .name: return "name"
        case .size: return "size"
        case .type: return "type"
        case .modified: return "modified"
        }
    }

    init?(columnID: String) {
        guard let key = SortKey.allCases.first(where: { $0.columnID == columnID }) else { return nil }
        self = key
    }
}

/// Настройки окна. Вид и сортировка — текущей папки (`FolderViews`); остальное общее для всех окон.
struct Settings {
    var viewMode: ViewMode = .details
    var sortKey: SortKey = .name
    var ascending = true
    var showHidden = false
    var lastPath: String?

    private static let defaults = UserDefaults.standard

    /// Вид текущей папки.
    var folderView: FolderView {
        get { FolderView(mode: viewMode, sortKey: sortKey, ascending: ascending) }
        set { viewMode = newValue.mode; sortKey = newValue.sortKey; ascending = newValue.ascending }
    }

    /// Вид папки, где его не меняли. Ключи — от времён, когда вид был один на все папки:
    /// выбранный тогда вид и становится видом по умолчанию.
    static var defaultView: FolderView {
        var view = FolderView(mode: .details, sortKey: .name, ascending: true)
        if let raw = defaults.object(forKey: "viewMode") as? Int, let mode = ViewMode(rawValue: raw) { view.mode = mode }
        if let raw = defaults.object(forKey: "sortKey") as? Int, let key = SortKey(rawValue: raw) { view.sortKey = key }
        if defaults.object(forKey: "ascending") != nil { view.ascending = defaults.bool(forKey: "ascending") }
        return view
    }

    static func load() -> Settings {
        var s = Settings()
        s.folderView = defaultView
        s.showHidden = defaults.bool(forKey: "showHidden")
        s.lastPath = defaults.string(forKey: "lastPath")
        return s
    }

    func save() {
        let d = Settings.defaults
        d.set(showHidden, forKey: "showHidden")
        d.set(lastPath, forKey: "lastPath")
    }
}

/// Вид папки: режим и сортировка. Как в XP («Помнить параметры отображения каждой папки»):
/// выбранное в папке запоминается за ней, а папка, где вид не меняли, открывается видом по умолчанию.
struct FolderView: Equatable {
    var mode: ViewMode
    var sortKey: SortKey
    var ascending: Bool
}

enum FolderViews {
    private static let key = "folderViews"
    /// Сколько папок помнить; сверх этого вытесняются самые давние.
    private static let limit = 2000
    private static let defaults = UserDefaults.standard

    /// Ключ места: путь папки, «Компьютер» — отдельной строкой. Результаты поиска не запоминаются.
    static func storageKey(_ location: Location) -> String? {
        switch location {
        case .folder(let url): return url.standardizedFileURL.path
        case .computer: return ":computer"
        case .search: return nil
        }
    }

    /// Вид места: запомненный, иначе вид по умолчанию.
    static func view(for location: Location) -> FolderView {
        guard let key = storageKey(location),
              let entry = (defaults.dictionary(forKey: Self.key) ?? [:])[key] as? [String: Any],
              let mode = (entry["mode"] as? Int).flatMap(ViewMode.init(rawValue:)),
              let sortKey = (entry["sort"] as? Int).flatMap(SortKey.init(rawValue:)),
              let ascending = entry["asc"] as? Bool
        else { return Settings.defaultView }
        return FolderView(mode: mode, sortKey: sortKey, ascending: ascending)
    }

    static func remember(_ view: FolderView, for location: Location) {
        guard let key = storageKey(location) else { return }
        var all = defaults.dictionary(forKey: Self.key) ?? [:]
        all[key] = ["mode": view.mode.rawValue, "sort": view.sortKey.rawValue, "asc": view.ascending,
                    "used": Date().timeIntervalSince1970]
        if all.count > limit {
            func used(_ value: Any) -> Double { (value as? [String: Any])?["used"] as? Double ?? 0 }
            for (old, _) in all.sorted(by: { used($0.value) < used($1.value) }).prefix(all.count - limit) {
                all[old] = nil
            }
        }
        defaults.set(all, forKey: Self.key)
    }
}

/// Ширина левой панели — своя у каждой темы, как и ширина по умолчанию.
enum SidebarWidth {
    private static func key(_ theme: Theme) -> String { "sidebarWidth.\(theme.rawValue)" }

    static func saved(_ theme: Theme) -> CGFloat? {
        let value = UserDefaults.standard.double(forKey: key(theme))
        return value > 0 ? CGFloat(value) : nil
    }

    static func save(_ width: CGFloat, _ theme: Theme) {
        UserDefaults.standard.set(Double(width), forKey: key(theme))
    }
}

/// «Избранное»: список папок в UserDefaults.
enum Favorites {
    private static let key = "favorites"

    static var all: [URL] {
        (UserDefaults.standard.stringArray(forKey: key) ?? []).map { URL(fileURLWithPath: $0) }
    }

    static func add(_ url: URL) {
        var paths = UserDefaults.standard.stringArray(forKey: key) ?? []
        guard !paths.contains(url.path) else { return }
        paths.append(url.path)
        UserDefaults.standard.set(paths, forKey: key)
    }

    static func remove(_ url: URL) {
        let paths = (UserDefaults.standard.stringArray(forKey: key) ?? []).filter { $0 != url.path }
        UserDefaults.standard.set(paths, forKey: key)
    }
}
