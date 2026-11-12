import AppKit

/// Правила перетаскивания файлов, общие для списка и дерева папок.
enum DropRules {
    /// Отметка на перетаскиваемых данных: тянут правой кнопкой. Лежит в самих данных, поэтому
    /// её видит и другой экземпляр программы; Finder её не знает и перетаскивает как обычно.
    static let rightDragMarker = NSPasteboard.PasteboardType("dev.oleg.wexplorer.right-drag")

    static func isRightDrag(_ info: NSDraggingInfo) -> Bool {
        info.draggingPasteboard.types?.contains(rightDragMarker) == true
    }

    static func urls(_ info: NSDraggingInfo) -> [URL] {
        info.draggingPasteboard.readObjects(
            forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
    }

    /// Как в Finder: на том же диске — перемещение, на другой — копирование; Option — всегда копирование.
    static func operation(_ info: NSDraggingInfo, into folder: URL) -> NSDragOperation {
        let urls = urls(info)
        guard !urls.isEmpty else { return [] }
        let folderPath = folder.standardizedFileURL.path
        if urls.contains(where: {
            let p = $0.standardizedFileURL.path
            return p == folderPath || folderPath.hasPrefix(p + "/")
        }) { return [] }
        let mask = info.draggingSourceOperationMask
        let alreadyThere = urls.allSatisfy { $0.deletingLastPathComponent().standardizedFileURL.path == folderPath }
        // Правой кнопкой можно бросить и в ту же папку: там пригодятся «Копировать» и «Создать ярлыки».
        if isRightDrag(info) { return alreadyThere || !Places.sameVolume(urls[0], folder) ? .copy : .move }
        if !mask.contains(.move) { return mask.contains(.copy) ? .copy : [] }
        if alreadyThere { return [] }
        if Places.sameVolume(urls[0], folder) { return .move }
        return mask.contains(.copy) ? .copy : .move
    }
}
