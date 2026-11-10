import Foundation

/// Запуск консольного 7-Zip, установленного пользователем отдельно. Сами мы архивы не разбираем.
struct SevenZip: Archiver {
    let tool: URL

    /// Приложения из Dock не видят PATH из профиля оболочки, поэтому ищем в обычных местах установки.
    /// Проверяем при каждом обращении: 7-Zip подхватится без перезапуска проводника.
    static var installed: SevenZip? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let dirs = ["/opt/homebrew/bin", "/usr/local/bin", "/opt/local/bin", "\(home)/.local/bin", "\(home)/bin"]
        for name in ["7zz", "7zzs", "7z"] {
            for dir in dirs {
                let path = "\(dir)/\(name)"
                if FileManager.default.isExecutableFile(atPath: path) {
                    return SevenZip(tool: URL(fileURLWithPath: path))
                }
            }
        }
        return nil
    }

    private static let archiveExtensions: Set<String> = [
        "7z", "zip", "rar", "tar", "gz", "tgz", "bz2", "tbz", "tbz2", "xz", "txz", "lzma", "z", "taz",
        "zst", "tzst", "cab", "iso", "wim", "arj", "lzh", "lha", "cpio", "rpm", "deb", "001",
    ]

    func canExtract(_ url: URL) -> Bool {
        Self.archiveExtensions.contains(url.pathExtension.lowercased())
    }

    func archiveURL(for sources: [URL], ext: String) -> URL? {
        ArchiveNames.archiveURL(for: sources, ext: ext)
    }

    // MARK: Команды

    func extract(_ archive: URL, to dir: URL, askPassword: (_ wrong: Bool) -> String?,
                 isCancelled: @escaping () -> Bool) -> ArchiveOutcome {
        var password: String?
        if isEncrypted(archive, isCancelled: isCancelled) {
            // Неверный пароль оставил бы после «x» пустые файлы, поэтому сначала проверяем его.
            switch verify(archive, askPassword: askPassword, isCancelled: isCancelled) {
            case .password(let verified): password = verified
            case .finished(let outcome): return outcome
            }
        }
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            return .failed([error.localizedDescription])
        }
        // -aou: при совпадении имён новые файлы получают суффикс.
        // Папку задаём как текущую: в значении -o знак * имеет особый смысл.
        return outcome(of: ["x", archive.path, "-bd", "-y", "-aou", "-spd"], in: dir,
                       password: password, isCancelled: isCancelled)
    }

    func test(_ archive: URL, askPassword: (_ wrong: Bool) -> String?,
              isCancelled: @escaping () -> Bool) -> ArchiveOutcome {
        if isEncrypted(archive, isCancelled: isCancelled) {
            if case .finished(let outcome) = verify(archive, askPassword: askPassword, isCancelled: isCancelled) {
                return outcome
            }
            return .ok
        }
        return outcome(of: testArguments(archive), in: archive.deletingLastPathComponent(),
                       password: nil, isCancelled: isCancelled)
    }

    /// Как и в 7-Zip для Windows, существующий архив обновляется, а не заменяется.
    func add(_ sources: [URL], to archive: URL, isCancelled: @escaping () -> Bool) -> ArchiveOutcome {
        // Префикс «./» не даёт принять имена вроде «@list» или «-x» за команды 7-Zip.
        // -snl хранит ссылки как ссылки, а не архивирует то, на что они указывают.
        let names = sources.map { "./" + $0.lastPathComponent }
        let type = archive.pathExtension.lowercased() == "zip" ? "-tzip" : "-t7z"
        return outcome(of: ["a", type, "-bd", "-y", "-snl", "-spd", "-xr!.DS_Store", "--", archive.path] + names,
                       in: archive.deletingLastPathComponent(), password: nil, isCancelled: isCancelled)
    }

    /// Сжатие с настройками из окна «Добавить к архиву». Пути в аргументах строятся от папки исходных объектов.
    func add(_ sources: [URL], to archive: URL, options: SevenZipAddOptions,
             isCancelled: @escaping () -> Bool) -> ArchiveOutcome {
        guard let dir = sources.first?.deletingLastPathComponent() else { return .failed([]) }
        return outcome(of: options.arguments(sources: sources, archive: archive), in: dir,
                       password: options.password.isEmpty ? nil : options.password, isCancelled: isCancelled)
    }

    // MARK: Пароль

    private enum Verification {
        case password(String)
        case finished(ArchiveOutcome)
    }

    private func isEncrypted(_ archive: URL, isCancelled: @escaping () -> Bool) -> Bool {
        guard let result = run(["l", "-slt", "-spd", archive.path], in: archive.deletingLastPathComponent(),
                               password: nil, isCancelled: isCancelled) else { return false }
        return result.lines.contains { $0.hasPrefix("Encrypted = +") || $0.hasPrefix("Enter password") }
    }

    private func verify(_ archive: URL, askPassword: (_ wrong: Bool) -> String?,
                        isCancelled: @escaping () -> Bool) -> Verification {
        var wrong = false
        while true {
            guard let password = askPassword(wrong) else { return .finished(.cancelled) }
            guard let result = run(testArguments(archive), in: archive.deletingLastPathComponent(),
                                   password: password, isCancelled: isCancelled) else {
                return .finished(.failed([]))
            }
            if isCancelled() { return .finished(.cancelled) }
            if result.status == 0 { return .password(password) }
            guard result.lines.contains(where: { $0.contains("Wrong password") }) else {
                return .finished(.failed(errors(in: result)))
            }
            wrong = true
        }
    }

    private func testArguments(_ archive: URL) -> [String] {
        ["t", archive.path, "-bd", "-spd"]
    }

    // MARK: Запуск

    private func errors(in result: ArchiveProcessResult) -> [String] {
        let found = result.lines.filter {
            $0.contains("ERROR") || $0.hasPrefix("WARNING") || $0.hasPrefix("Is not archive")
        }
        return found.isEmpty ? Array(result.lines.filter { !$0.isEmpty }.suffix(3)) : found
    }

    private func outcome(of arguments: [String], in dir: URL, password: String?,
                         isCancelled: @escaping () -> Bool) -> ArchiveOutcome {
        guard let result = run(arguments, in: dir, password: password, isCancelled: isCancelled) else {
            return .failed([])
        }
        if isCancelled() { return .cancelled }
        return result.status == 0 ? .ok : .failed(errors(in: result))
    }

    /// Пароль передаём через stdin: в аргументах его видно в списке процессов.
    /// Без stdin 7-Zip на запросе пароля завершается, а не ждёт ввода вечно.
    private func run(_ arguments: [String], in dir: URL, password: String?,
                     isCancelled: () -> Bool) -> ArchiveProcessResult? {
        ArchiveProcess.run(tool, arguments, in: dir, stdin: password, isCancelled: isCancelled)
    }
}
