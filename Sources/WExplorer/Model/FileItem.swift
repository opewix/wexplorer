import AppKit
import UniformTypeIdentifiers

/// Один объект в списке: файл, папка или диск.
final class FileItem {
    let url: URL
    let name: String
    /// Папка, в которую можно перейти (пакеты вроде .app считаются файлами).
    let isDirectory: Bool
    let size: Int64?
    let modified: Date?
    let created: Date?
    let typeName: String
    let isHidden: Bool
    let isVolume: Bool
    let contentType: UTType?
    /// Доп. строка для «Плитки» и панели «Подробно» (например, свободное место на диске).
    let detail: String?

    private(set) lazy var icon: NSImage = XPIcons.icon(for: self)
    /// Расширение, которое прячется при «Скрывать расширения…» (см. `FileExtensions`).
    private(set) lazy var knownExtension: String? =
        FileExtensions.knownExtension(name: name, isDirectory: isDirectory, isVolume: isVolume, contentType: contentType)

    static let resourceKeys: [URLResourceKey] = [
        .isDirectoryKey, .isPackageKey, .fileSizeKey, .contentModificationDateKey,
        .creationDateKey, .localizedTypeDescriptionKey, .isHiddenKey, .contentTypeKey,
    ]

    init(url: URL, name: String, isDirectory: Bool, size: Int64?, modified: Date?, created: Date?,
         typeName: String, isHidden: Bool, isVolume: Bool = false, contentType: UTType? = nil,
         detail: String? = nil) {
        self.url = url
        self.name = name
        self.isDirectory = isDirectory
        self.size = size
        self.modified = modified
        self.created = created
        self.typeName = typeName
        self.isHidden = isHidden
        self.isVolume = isVolume
        self.contentType = contentType
        self.detail = detail
    }

    convenience init(url: URL) {
        let values = try? url.resourceValues(forKeys: Set(Self.resourceKeys))
        let isDirectory = (values?.isDirectory ?? false) && !(values?.isPackage ?? false)
        self.init(
            url: url,
            name: url.lastPathComponent,
            isDirectory: isDirectory,
            size: isDirectory ? nil : values?.fileSize.map(Int64.init),
            modified: values?.contentModificationDate,
            created: values?.creationDate,
            typeName: isDirectory ? tr(.typeFolder) : (values?.localizedTypeDescription ?? tr(.typeFile)),
            isHidden: values?.isHidden ?? false,
            contentType: values?.contentType)
    }

    static func volume(_ url: URL) -> FileItem {
        let keys: Set<URLResourceKey> = [
            .volumeLocalizedNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey,
            .volumeIsRemovableKey, .volumeIsLocalKey, .volumeIsInternalKey,
        ]
        let values = try? url.resourceValues(forKeys: keys)
        let type: String
        if values?.volumeIsLocal == false {
            type = tr(.diskNetwork)
        } else if values?.volumeIsRemovable == true || values?.volumeIsInternal == false {
            type = tr(.diskRemovable)
        } else {
            type = tr(.diskLocal)
        }
        let total = values?.volumeTotalCapacity.map(Int64.init)
        let free = values?.volumeAvailableCapacity.map(Int64.init)
        var detail: String?
        if let total, let free {
            detail = tr(.diskFree, Format.size(free), Format.size(total))
        }
        return FileItem(
            url: url, name: values?.volumeLocalizedName ?? url.lastPathComponent, isDirectory: true,
            size: total, modified: nil, created: nil, typeName: type, isHidden: false,
            isVolume: true, detail: detail)
    }
}

extension FileItem {
    var isShortcut: Bool { contentType?.conforms(to: .aliasFile) == true }

    /// Папка, на которую ведёт ярлык (псевдоним Finder), или nil — не ярлык или ведёт на файл.
    var shortcutFolder: URL? {
        guard isShortcut, let target = try? URL(resolvingAliasFileAt: url),
              let values = try? target.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey]),
              values.isDirectory == true, values.isPackage != true else { return nil }
        return target
    }

    /// Сортировка как в XP: папки всегда выше файлов.
    static func sorted(_ items: [FileItem], by key: SortKey, ascending: Bool) -> [FileItem] {
        items.sorted { a, b in
            if a.isDirectory != b.isDirectory { return a.isDirectory }
            let result: ComparisonResult
            switch key {
            case .name: result = a.name.localizedStandardCompare(b.name)
            case .size: result = compare(a.size ?? -1, b.size ?? -1)
            case .type: result = a.typeName.localizedStandardCompare(b.typeName)
            case .modified: result = compare(a.modified ?? .distantPast, b.modified ?? .distantPast)
            }
            if result == .orderedSame {
                return a.name.localizedStandardCompare(b.name) == .orderedAscending
            }
            return ascending ? result == .orderedAscending : result == .orderedDescending
        }
    }

    private static func compare<T: Comparable>(_ a: T, _ b: T) -> ComparisonResult {
        a < b ? .orderedAscending : (a > b ? .orderedDescending : .orderedSame)
    }
}
