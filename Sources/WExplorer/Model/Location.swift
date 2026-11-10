import AppKit

/// Особые места в стиле XP и их соответствие папкам macOS.
enum Places {
    private static let fm = FileManager.default

    static var home: URL { fm.homeDirectoryForCurrentUser }
    static var desktop: URL {
        fm.urls(for: .desktopDirectory, in: .userDomainMask).first ?? home.appendingPathComponent("Desktop")
    }
    static var documents: URL {
        fm.urls(for: .documentDirectory, in: .userDomainMask).first ?? home.appendingPathComponent("Documents")
    }

    static var computerTitle: String { tr(.myComputer) }

    static var computerIcon: NSImage { XPIcons.image(.computer, size: 16) }

    static func displayName(of url: URL) -> String {
        let path = url.standardizedFileURL.path
        if path == desktop.standardizedFileURL.path { return tr(.desktop) }
        if path == documents.standardizedFileURL.path { return tr(.myDocuments) }
        if isVolumeRoot(url), let name = try? url.resourceValues(forKeys: [.volumeLocalizedNameKey]).volumeLocalizedName {
            return name
        }
        return fm.displayName(atPath: path)
    }

    static func icon(_ url: URL, size: CGFloat = 16) -> NSImage {
        XPIcons.icon(forLocation: url, size: size)
    }

    static func isVolumeRoot(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isVolumeKey]))?.isVolume == true
    }

    static func isPackage(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isPackageKey]))?.isPackage == true
    }

    static func sameVolume(_ a: URL, _ b: URL) -> Bool {
        let ia = (try? a.resourceValues(forKeys: [.volumeIdentifierKey]))?.volumeIdentifier as? NSObject
        let ib = (try? b.resourceValues(forKeys: [.volumeIdentifierKey]))?.volumeIdentifier as? NSObject
        guard let ia, let ib else { return false }
        return ia.isEqual(ib)
    }

    static func freeSpace(_ url: URL) -> Int64? {
        (try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?
            .volumeAvailableCapacityForImportantUsage
    }
}

/// Где сейчас находится окно: папка, «Мой компьютер» или результаты поиска.
enum Location: Equatable {
    case folder(URL)
    case computer
    case search(query: String, scope: URL)

    var url: URL? {
        if case .folder(let url) = self { return url }
        return nil
    }

    var title: String {
        switch self {
        case .folder(let url): return Places.displayName(of: url)
        case .computer: return Places.computerTitle
        case .search(let query, _): return tr(.searchResults, query)
        }
    }

    var addressText: String {
        switch self {
        case .folder(let url): return url.path
        case .computer: return Places.computerTitle
        case .search: return title
        }
    }

    var icon: NSImage {
        switch self {
        case .folder(let url): return Places.icon(url)
        case .computer: return Places.computerIcon
        case .search:
            return XPIcons.image(.search, size: 16)
        }
    }

    var parent: Location? {
        switch self {
        case .folder(let url):
            if url.path == "/" || Places.isVolumeRoot(url) { return .computer }
            return .folder(url.deletingLastPathComponent())
        case .computer:
            return nil
        case .search(_, let scope):
            return scope.path == "/" ? .computer : .folder(scope)
        }
    }

    static func == (a: Location, b: Location) -> Bool {
        switch (a, b) {
        case let (.folder(x), .folder(y)):
            return x.standardizedFileURL.path == y.standardizedFileURL.path
        case (.computer, .computer):
            return true
        case let (.search(q1, s1), .search(q2, s2)):
            return q1 == q2 && s1.path == s2.path
        default:
            return false
        }
    }
}

/// Обёртка, чтобы класть Location в representedObject пунктов меню.
final class LocationRef: NSObject {
    let location: Location
    init(_ location: Location) { self.location = location }
}
