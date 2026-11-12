import AppKit

/// Открытие файла по двойному щелчку: образы дисков — через `DiskImages`, остальное — как в Finder.
enum FileOpener {
    static func open(_ url: URL) {
        if DiskImages.isDiskImage(url) {
            DiskImages.open(url)
        } else {
            NSWorkspace.shared.open(url)
        }
    }
}

/// Образы дисков (.dmg) открываем, как Finder: подключаем и показываем окно тома в самом Finder.
/// Своё окно для тома не годится: окно установки (фон, раскладка значков, стрелка «в Программы»)
/// рисует Finder по .DS_Store образа, и повторить его можно только им самим.
///
/// Подключает системный DiskImageMounter — он же спрашивает пароль, показывает лицензию и проверку.
/// Мы ждём появления тома и открываем его в Finder; уже подключённый образ просто показываем.
enum DiskImages {
    static let extensions: Set<String> = ["dmg", "sparseimage"]

    /// Сколько ждать подключения: пароль и лицензия ждут человека.
    private static let waitLimit: TimeInterval = 180

    /// Образы, которые подключаются сейчас: путь → когда перестать ждать.
    private static var pending: [String: Date] = [:]
    private static var mountObserver: NSObjectProtocol?

    static func isDiskImage(_ url: URL) -> Bool {
        extensions.contains(url.pathExtension.lowercased())
    }

    static func open(_ url: URL) {
        let path = canonical(url.path)
        DispatchQueue.global(qos: .userInitiated).async {
            let mounted = mountPoints()[path] ?? []
            DispatchQueue.main.async {
                if !mounted.isEmpty {
                    showInFinder(mounted)
                    return
                }
                watch(path)
                NSWorkspace.shared.open(url)
            }
        }
    }

    private static func watch(_ path: String) {
        pending[path] = Date().addingTimeInterval(waitLimit)
        guard mountObserver == nil else { return }
        mountObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didMountNotification, object: nil, queue: .main) { _ in volumeMounted() }
    }

    private static func volumeMounted() {
        let now = Date()
        pending = pending.filter { $0.value > now }
        guard !pending.isEmpty else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            let all = mountPoints()
            DispatchQueue.main.async {
                for (path, _) in pending {
                    guard let mounted = all[path], !mounted.isEmpty else { continue }
                    pending[path] = nil
                    showInFinder(mounted)
                }
            }
        }
    }

    private static func showInFinder(_ volumes: [URL]) {
        guard let finder = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.finder") else {
            volumes.forEach { NSWorkspace.shared.open($0) }
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open(volumes, withApplicationAt: finder, configuration: configuration)
    }

    /// Подключённые образы по `hdiutil info`: путь к образу → точки подключения его томов.
    private static func mountPoints() -> [String: [URL]] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = ["info", "-plist"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return [:] }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let images = plist["images"] as? [[String: Any]] else { return [:] }
        var result: [String: [URL]] = [:]
        for image in images {
            guard let path = image["image-path"] as? String else { continue }
            let entities = image["system-entities"] as? [[String: Any]] ?? []
            let mounts = entities.compactMap { $0["mount-point"] as? String }.map { URL(fileURLWithPath: $0) }
            // Один образ бывает подключён несколько раз («Том», «Том 1») — показываем первое подключение.
            let key = canonical(path)
            if result[key] == nil, !mounts.isEmpty { result[key] = mounts }
        }
        return result
    }

    private static func canonical(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
    }
}
