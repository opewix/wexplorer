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

/// Настройки, общие для всех окон.
struct Settings {
    var viewMode: ViewMode = .details
    var sortKey: SortKey = .name
    var ascending = true
    var showHidden = false
    var lastPath: String?

    private static let defaults = UserDefaults.standard

    static func load() -> Settings {
        var s = Settings()
        if let raw = defaults.object(forKey: "viewMode") as? Int, let mode = ViewMode(rawValue: raw) { s.viewMode = mode }
        if let raw = defaults.object(forKey: "sortKey") as? Int, let key = SortKey(rawValue: raw) { s.sortKey = key }
        if defaults.object(forKey: "ascending") != nil { s.ascending = defaults.bool(forKey: "ascending") }
        s.showHidden = defaults.bool(forKey: "showHidden")
        s.lastPath = defaults.string(forKey: "lastPath")
        return s
    }

    func save() {
        let d = Settings.defaults
        d.set(viewMode.rawValue, forKey: "viewMode")
        d.set(sortKey.rawValue, forKey: "sortKey")
        d.set(ascending, forKey: "ascending")
        d.set(showHidden, forKey: "showHidden")
        d.set(lastPath, forKey: "lastPath")
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
