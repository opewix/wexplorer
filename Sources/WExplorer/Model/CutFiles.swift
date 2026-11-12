import AppKit

/// Вырезанные файлы: их значки в списке бледнеют, как в Проводнике, пока файлы не вставлены
/// или буфер обмена не занят другим. Источник — сам буфер обмена (файлы с отметкой «вырезано»),
/// поэтому значки бледнеют во всех окнах и экземплярах программы. Об изменениях буфера macOS
/// не сообщает — раз в полсекунды сверяется его счётчик изменений, это дёшево.
enum CutFiles {
    /// Тип в буфере обмена, которым помечены вырезанные (а не скопированные) файлы.
    static let marker = NSPasteboard.PasteboardType("dev.oleg.wexplorer.cut")
    static let didChange = Notification.Name("CutFilesDidChange")

    private(set) static var paths: Set<String> = []
    private static var changeCount = -1
    private static var timer: Timer?

    static func startWatching() {
        refresh()
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 0.5, repeats: true) { _ in refresh() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    static func contains(_ url: URL) -> Bool {
        !paths.isEmpty && paths.contains(url.standardizedFileURL.path)
    }

    static func refresh() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != changeCount else { return }
        changeCount = pasteboard.changeCount
        var current: Set<String> = []
        if pasteboard.pasteboardItems?.contains(where: { $0.types.contains(marker) }) == true,
           let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] {
            current = Set(urls.map { $0.standardizedFileURL.path })
        }
        guard current != paths else { return }
        paths = current
        NotificationCenter.default.post(name: didChange, object: nil)
    }
}
