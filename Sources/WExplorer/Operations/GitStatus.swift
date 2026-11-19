import AppKit

/// Состояние файла в Git — значок поверх иконки, как у TortoiseGit в Проводнике.
enum GitBadge {
    case normal, modified, added, conflicted

    /// Иконка со значком состояния в левом нижнем углу.
    func overlay(on base: NSImage) -> NSImage {
        let size = base.size
        return NSImage(size: size, flipped: false) { rect in
            base.draw(in: rect)
            let side = max(8, (min(size.width, size.height) * 0.5).rounded())
            let transform = NSAffineTransform()
            transform.scale(by: side / 16)
            transform.concat()
            self.draw()
            return true
        }
    }

    /// Рисунок на сетке 16×16 (ось Y вверх): цветной кружок с белым знаком; конфликт — жёлтый треугольник.
    private func draw() {
        func dot(_ r: CGFloat, _ color: NSColor) {
            color.setFill()
            NSBezierPath(ovalIn: NSRect(x: 8 - r, y: 8 - r, width: r * 2, height: r * 2)).fill()
        }
        func stroke(_ points: [NSPoint], _ color: NSColor, _ width: CGFloat) {
            let path = NSBezierPath()
            path.move(to: points[0])
            points.dropFirst().forEach(path.line)
            path.lineWidth = width
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            color.setStroke()
            path.stroke()
        }
        func triangle(_ top: CGFloat, _ left: CGFloat, _ bottom: CGFloat, _ color: NSColor) {
            let path = NSBezierPath()
            path.move(to: NSPoint(x: 8, y: top))
            path.line(to: NSPoint(x: left, y: bottom))
            path.line(to: NSPoint(x: 16 - left, y: bottom))
            path.close()
            color.setFill()
            path.fill()
        }
        func rgb(_ hex: Int) -> NSColor {
            NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                    blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        }
        switch self {
        case .normal:
            dot(7.5, .white); dot(6.5, rgb(0x2E9E3F))
            stroke([NSPoint(x: 4.6, y: 8.2), NSPoint(x: 7.1, y: 5.6), NSPoint(x: 11.5, y: 10.8)], .white, 2)
        case .modified:
            dot(7.5, .white); dot(6.5, rgb(0xD43A2F))
            stroke([NSPoint(x: 8, y: 11.6), NSPoint(x: 8, y: 7.6)], .white, 2.2)
            stroke([NSPoint(x: 8, y: 4.6), NSPoint(x: 8, y: 4.5)], .white, 2.2)
        case .added:
            dot(7.5, .white); dot(6.5, rgb(0x2F6FD4))
            stroke([NSPoint(x: 8, y: 4.4), NSPoint(x: 8, y: 11.6)], .white, 2.1)
            stroke([NSPoint(x: 4.4, y: 8), NSPoint(x: 11.6, y: 8)], .white, 2.1)
        case .conflicted:
            triangle(15.5, 0.3, 1.5, .white)
            triangle(13.6, 2.2, 2.6, rgb(0xF2C230))
            stroke([NSPoint(x: 8, y: 10.4), NSPoint(x: 8, y: 7)], rgb(0x3A2E00), 1.8)
            stroke([NSPoint(x: 8, y: 4.6), NSPoint(x: 8, y: 4.5)], rgb(0x3A2E00), 1.8)
        }
    }
}

/// Снимок `git status` одной рабочей копии.
struct GitSnapshot {
    let root: String
    fileprivate var changed: [String: GitBadge] = [:]
    fileprivate var changedDirs: Set<String> = []
    /// Не под версией и игнорируемые: значка нет. Папки — с «/» на конце.
    fileprivate var excluded: [String] = []

    func contains(_ path: String) -> Bool { path == root || path.hasPrefix(root + "/") }

    /// Значок самой корневой папки: есть ли в рабочей копии изменения.
    var rootBadge: GitBadge {
        if changed.values.contains(.conflicted) { return .conflicted }
        return changed.isEmpty ? .normal : .modified
    }

    func badge(for path: String) -> GitBadge? {
        guard path.hasPrefix(root + "/") else { return nil }
        let relative = String(path.dropFirst(root.count + 1))
        if relative == ".git" || relative.hasPrefix(".git/") { return nil }
        for item in excluded {
            if item.hasSuffix("/") ? (relative + "/").hasPrefix(item) : relative == item { return nil }
        }
        if let badge = changed[relative] { return badge }
        return changedDirs.contains(relative) ? .modified : .normal
    }
}

/// Значки состояния Git на файлах. Показываются, когда установлена WTortoise (см. `GitMenu`):
/// без неё с git в Проводнике делать нечего. Только читаем: `git status` без блокировок.
enum GitStatus {
    private static let git: String? = ["/opt/homebrew/bin/git", "/usr/local/bin/git", "/usr/bin/git"]
        .first { FileManager.default.isExecutableFile(atPath: $0) }

    /// Состояние рабочей копии, в которой лежит папка; nil — не рабочая копия или значки выключены.
    static func load(for folder: URL, completion: @escaping (GitSnapshot?) -> Void) {
        guard GitMenu.isAvailable, let git else { return completion(nil) }
        let path = folder.path
        DispatchQueue.global(qos: .utility).async {
            let snapshot = GitMenu.root(of: path).flatMap { read(root: $0, git: git) }
            DispatchQueue.main.async { completion(snapshot) }
        }
    }

    /// Значки для папок, которые сами — корень рабочей копии (в них лежит `.git`): изменено ли что-то внутри.
    /// Нужны, когда открыта папка вне рабочей копии: её состояние такие папки не покрывает.
    static func loadRoots(among folders: [URL], completion: @escaping ([String: GitBadge]) -> Void) {
        guard GitMenu.isAvailable, let git, !folders.isEmpty else { return completion([:]) }
        DispatchQueue.global(qos: .utility).async {
            var badges: [String: GitBadge] = [:]
            for folder in folders where FileManager.default.fileExists(atPath: folder.path + "/.git") {
                guard let snapshot = read(root: folder.path, git: git) else { continue }
                badges[folder.path] = snapshot.rootBadge
            }
            DispatchQueue.main.async { completion(badges) }
        }
    }

    private static func read(root: String, git: String) -> GitSnapshot? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: git)
        process.arguments = ["--no-optional-locks", "-c", "core.quotepath=false", "-C", root,
                             "status", "--porcelain", "-z", "-unormal", "--ignored"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }

        var snapshot = GitSnapshot(root: root)
        let records = String(decoding: data, as: UTF8.self).split(separator: "\0", omittingEmptySubsequences: false).map(String.init)
        var index = 0
        while index < records.count {
            let record = records[index]
            index += 1
            guard record.count > 3 else { continue }
            let chars = Array(record)
            let x = chars[0], y = chars[1], path = String(chars[3...])
            // У переименованного следом идёт прежнее имя.
            if x == "R" || x == "C" { index += 1 }
            if x == "?" || x == "!" {
                snapshot.excluded.append(path)
                continue
            }
            if x == "U" || y == "U" || (x == "A" && y == "A") || (x == "D" && y == "D") {
                snapshot.changed[path] = .conflicted
            } else {
                snapshot.changed[path] = x == "A" ? .added : .modified
            }
            var dir = (path as NSString).deletingLastPathComponent
            while !dir.isEmpty {
                snapshot.changedDirs.insert(dir)
                dir = (dir as NSString).deletingLastPathComponent
            }
        }
        return snapshot
    }
}
