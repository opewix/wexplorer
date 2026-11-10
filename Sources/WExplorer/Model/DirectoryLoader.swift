import AppKit

/// Чтение содержимого папок и списка дисков.
enum DirectoryLoader {
    static func contents(of url: URL, showHidden: Bool) throws -> [FileItem] {
        let urls = try FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: FileItem.resourceKeys,
            options: showHidden ? [] : [.skipsHiddenFiles])
        return urls.map(FileItem.init(url:))
    }

    /// Только вложенные папки (для дерева), отсортированные по имени.
    static func subfolders(of url: URL, showHidden: Bool) -> [URL] {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isPackageKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: Array(keys),
            options: showHidden ? [] : [.skipsHiddenFiles])
        else { return [] }
        return urls
            .filter {
                let values = try? $0.resourceValues(forKeys: keys)
                return values?.isDirectory == true && values?.isPackage != true
            }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    static func volumes() -> [URL] {
        FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil, options: [.skipHiddenVolumes]) ?? []
    }

    /// Содержимое «Моего компьютера»: домашняя папка и диски.
    static func computerItems() -> [FileItem] {
        [FileItem(url: Places.home)] + volumes().map(FileItem.volume)
    }
}

/// Следит за изменениями в открытой папке и сообщает о них (с небольшой задержкой).
final class DirectoryWatcher {
    var onChange: (() -> Void)?

    private var source: DispatchSourceFileSystemObject?
    private var pending: DispatchWorkItem?

    func watch(_ url: URL?) {
        source?.cancel()
        source = nil
        guard let url else { return }
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .delete, .rename], queue: .main)
        src.setEventHandler { [weak self] in self?.scheduleChange() }
        src.setCancelHandler { close(fd) }
        src.resume()
        source = src
    }

    private func scheduleChange() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.onChange?() }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    deinit { source?.cancel() }
}

/// Поиск по имени файла через Spotlight.
final class FileSearch {
    var onResults: (([URL], Bool) -> Void)?

    private var query: NSMetadataQuery?
    private var observers: [NSObjectProtocol] = []
    private let limit = 5000

    func start(_ text: String, in scope: URL) {
        stop()
        let q = NSMetadataQuery()
        q.predicate = NSPredicate(format: "%K LIKE[cd] %@", NSMetadataItemFSNameKey, "*\(text)*")
        q.searchScopes = scope.path == "/" ? [NSMetadataQueryLocalComputerScope] : [scope]
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: .NSMetadataQueryDidFinishGathering, object: q, queue: .main) { [weak self] _ in
                self?.publish(finished: true)
            },
            center.addObserver(forName: .NSMetadataQueryDidUpdate, object: q, queue: .main) { [weak self] _ in
                self?.publish(finished: true)
            },
        ]
        query = q
        q.start()
    }

    func stop() {
        query?.stop()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        query = nil
    }

    private func publish(finished: Bool) {
        guard let q = query else { return }
        q.disableUpdates()
        defer { q.enableUpdates() }
        var urls: [URL] = []
        for i in 0..<min(q.resultCount, limit) {
            if let item = q.result(at: i) as? NSMetadataItem,
               let path = item.value(forAttribute: NSMetadataItemPathKey) as? String {
                urls.append(URL(fileURLWithPath: path))
            }
        }
        onResults?(urls, finished)
    }
}
