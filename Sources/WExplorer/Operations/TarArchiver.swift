import Foundation

/// Архиватор по умолчанию: системный /usr/bin/tar (bsdtar), есть на любом Mac.
struct TarArchiver: Archiver {
    let tool: URL

    static var installed: TarArchiver? {
        let path = "/usr/bin/tar"
        return FileManager.default.isExecutableFile(atPath: path)
            ? TarArchiver(tool: URL(fileURLWithPath: path))
            : nil
    }

    private static let archiveExtensions: Set<String> = [
        "zip", "7z", "rar", "tar", "tgz", "taz", "tbz", "tbz2", "txz", "cab", "iso", "lzh", "lha", "cpio", "rpm", "xar",
    ]
    private static let compressedTarExtensions: Set<String> = ["gz", "bz2", "xz", "lzma", "z"]

    /// Одиночный сжатый файл («заметка.txt.gz») tar не читает, поэтому .gz подходит только как «.tar.gz».
    func canExtract(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        if Self.archiveExtensions.contains(ext) { return true }
        return Self.compressedTarExtensions.contains(ext)
            && url.deletingPathExtension().pathExtension.lowercased() == "tar"
    }

    /// tar не умеет дополнять zip и 7z, а существующий архив просто перезаписал бы. Поэтому имя всегда новое.
    func archiveURL(for sources: [URL], ext: String) -> URL? {
        ArchiveNames.archiveURL(for: sources, ext: ext).map(ArchiveNames.available)
    }

    // MARK: Распаковка

    /// tar молча затирает существующие файлы, поэтому распаковываем во временную папку рядом с целью
    /// и переносим оттуда сами. Заодно отмена и неверный пароль не оставляют следов.
    func extract(_ archive: URL, to dir: URL, askPassword: (_ wrong: Bool) -> String?,
                 isCancelled: @escaping () -> Bool) -> ArchiveOutcome {
        let fm = FileManager.default
        let destinationExisted = fm.fileExists(atPath: dir.path)
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            return .failed([error.localizedDescription])
        }
        func discardEmptyDestination() {
            if !destinationExisted, (try? fm.contentsOfDirectory(atPath: dir.path))?.isEmpty == true {
                try? fm.removeItem(at: dir)
            }
        }

        var passphrase = Self.placeholderPassphrase
        var wrong = false
        while true {
            let temp = dir.appendingPathComponent(".wexplorer-\(UUID().uuidString)")
            do {
                try fm.createDirectory(at: temp, withIntermediateDirectories: false)
            } catch {
                discardEmptyDestination()
                return .failed([error.localizedDescription])
            }
            defer { Self.forceRemove(temp) }

            let result = ArchiveProcess.run(tool, ["-x", "-f", archive.path, "--passphrase", passphrase],
                                            in: temp, discardStandardOutput: true, isCancelled: isCancelled)
            guard let result else {
                Self.forceRemove(temp)
                discardEmptyDestination()
                return .failed([])
            }
            if isCancelled() {
                Self.forceRemove(temp)
                discardEmptyDestination()
                return .cancelled
            }
            switch Self.classify(result) {
            case .wrongPassword:
                Self.forceRemove(temp)
                guard let entered = askPassword(wrong) else {
                    discardEmptyDestination()
                    return .cancelled
                }
                passphrase = entered
                wrong = true
                continue
            case .unsupportedEncryption:
                Self.forceRemove(temp)
                discardEmptyDestination()
                return .unsupportedEncryption
            case .other:
                break
            }

            // Как и 7-Zip, при ошибке оставляем то, что удалось распаковать: это может быть всё, что осталось.
            var errors = result.status == 0 ? [] : Self.errors(in: result)
            let items = (try? fm.contentsOfDirectory(at: temp, includingPropertiesForKeys: nil)) ?? []
            for item in items {
                do {
                    try Self.place(item, into: dir)
                } catch {
                    errors.append(error.localizedDescription)
                }
            }
            Self.forceRemove(temp)
            discardEmptyDestination()
            return errors.isEmpty ? .ok : .failed(errors)
        }
    }

    // MARK: Проверка

    /// Содержимое читается целиком: только так tar сверяет контрольные суммы.
    func test(_ archive: URL, askPassword: (_ wrong: Bool) -> String?,
              isCancelled: @escaping () -> Bool) -> ArchiveOutcome {
        var passphrase = Self.placeholderPassphrase
        var wrong = false
        while true {
            let result = ArchiveProcess.run(tool, ["-x", "-O", "-f", archive.path, "--passphrase", passphrase],
                                            in: archive.deletingLastPathComponent(),
                                            discardStandardOutput: true, isCancelled: isCancelled)
            guard let result else { return .failed([]) }
            if isCancelled() { return .cancelled }
            switch Self.classify(result) {
            case .wrongPassword:
                guard let entered = askPassword(wrong) else { return .cancelled }
                passphrase = entered
                wrong = true
            case .unsupportedEncryption:
                return .unsupportedEncryption
            case .other:
                return result.status == 0 ? .ok : .failed(Self.errors(in: result))
            }
        }
    }

    // MARK: Сжатие

    func add(_ sources: [URL], to archive: URL, isCancelled: @escaping () -> Bool) -> ArchiveOutcome {
        let fm = FileManager.default
        let dir = archive.deletingLastPathComponent()
        let ext = archive.pathExtension.lowercased()
        // Пишем во временный файл: прерванный tar оставляет на месте архива пустой файл.
        let temp = dir.appendingPathComponent(".wexplorer-\(UUID().uuidString).\(ext)")
        defer { try? fm.removeItem(at: temp) }

        // Префикс «./» не даёт принять имена вроде «@list» или «-x» за параметры, а -s убирает его из архива.
        // COPYFILE_DISABLE и --no-mac-metadata: иначе в архив попадут служебные файлы «._имя».
        let names = sources.map { "./" + $0.lastPathComponent }
        let arguments = ["-c", "-f", temp.path, "--format=\(ext == "zip" ? "zip" : "7zip")",
                         "--no-mac-metadata", "--exclude", ".DS_Store", "-s", ",^\\./,,"] + names
        let result = ArchiveProcess.run(tool, arguments, in: dir, environment: ["COPYFILE_DISABLE": "1"],
                                        discardStandardOutput: true, isCancelled: isCancelled)
        guard let result else { return .failed([]) }
        if isCancelled() { return .cancelled }
        guard result.status == 0 else { return .failed(Self.errors(in: result)) }
        do {
            try fm.moveItem(at: temp, to: ArchiveNames.available(archive))
            return .ok
        } catch {
            return .failed([error.localizedDescription])
        }
    }

    // MARK: Пароль

    /// Без --passphrase и без терминала tar бесконечно повторяет запрос пароля, поэтому пробуем заведомо
    /// неверный: обычным архивам он не мешает, а зашифрованные отвечают «Incorrect passphrase».
    /// Настоящий пароль tar принимает только аргументом, поэтому пока он работает, пароль виден в списке процессов.
    private static var placeholderPassphrase: String { UUID().uuidString }

    private enum Classification {
        case wrongPassword, unsupportedEncryption, other
    }

    private static func classify(_ result: ArchiveProcessResult) -> Classification {
        if result.lines.contains(where: { $0.contains("Incorrect passphrase") }) { return .wrongPassword }
        if result.lines.contains(where: { $0.contains("encrypted, but currently not supported") }) {
            return .unsupportedEncryption
        }
        return .other
    }

    private static func errors(in result: ArchiveProcessResult) -> [String] {
        result.lines.filter { !$0.isEmpty && !$0.contains("Error exit delayed") }
    }

    // MARK: Перенос из временной папки

    /// Папки объединяются, а при совпадении файлов новый получает суффикс.
    private static func place(_ item: URL, into dir: URL) throws {
        let fm = FileManager.default
        var target = dir.appendingPathComponent(item.lastPathComponent)
        if ArchiveNames.exists(target) {
            if isRealDirectory(item) && isRealDirectory(target) {
                addOwnerPermissions(item, 0o700)
                for child in try fm.contentsOfDirectory(at: item, includingPropertiesForKeys: nil) {
                    try place(child, into: target)
                }
                return
            }
            target = ArchiveNames.available(target)
        }
        // Папку только для чтения нельзя перенести в другую папку, пока на неё нет прав записи.
        let original = isRealDirectory(item) ? permissions(item) : nil
        if original != nil { addOwnerPermissions(item, 0o200) }
        try fm.moveItem(at: item, to: target)
        if let original {
            try? fm.setAttributes([.posixPermissions: original], ofItemAtPath: target.path)
        }
    }

    /// Обычное удаление не справляется с папками только для чтения из архива.
    private static func forceRemove(_ url: URL) {
        guard ArchiveNames.exists(url) else { return }
        if isRealDirectory(url) {
            addOwnerPermissions(url, 0o700)
            let children = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
            children.forEach(forceRemove)
        }
        try? FileManager.default.removeItem(at: url)
    }

    private static func isRealDirectory(_ url: URL) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.type] as? FileAttributeType == .typeDirectory
    }

    private static func permissions(_ url: URL) -> Int? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.posixPermissions] as? Int
    }

    private static func addOwnerPermissions(_ url: URL, _ bits: Int) {
        guard let current = permissions(url), current & bits != bits else { return }
        try? FileManager.default.setAttributes([.posixPermissions: current | bits], ofItemAtPath: url.path)
    }
}
