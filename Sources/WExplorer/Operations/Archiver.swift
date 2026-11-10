import Foundation

enum ArchiveOutcome {
    case ok
    case cancelled
    case failed([String])
    /// Архиватор не умеет читать такое шифрование.
    case unsupportedEncryption
}

/// Внешняя программа, через которую идут операции с архивами.
protocol Archiver {
    func canExtract(_ url: URL) -> Bool
    /// Какой архив создаст «Добавить к». nil — объекты лежат в разных папках.
    func archiveURL(for sources: [URL], ext: String) -> URL?
    /// Существующие файлы не затираются: новые получают суффикс («файл_1.txt»).
    func extract(_ archive: URL, to dir: URL, askPassword: (_ wrong: Bool) -> String?,
                 isCancelled: @escaping () -> Bool) -> ArchiveOutcome
    func test(_ archive: URL, askPassword: (_ wrong: Bool) -> String?,
              isCancelled: @escaping () -> Bool) -> ArchiveOutcome
    func add(_ sources: [URL], to archive: URL, isCancelled: @escaping () -> Bool) -> ArchiveOutcome
}

/// Группы в контекстном меню. Значение хранится в теге пункта меню.
enum ArchiveKind: Int, CaseIterable {
    case builtin, sevenZip

    var archiver: Archiver? {
        switch self {
        case .builtin: return TarArchiver.installed
        case .sevenZip: return SevenZip.installed
        }
    }
}

// MARK: - Имена

enum ArchiveNames {
    /// Папка для «Распаковать в»: «x.zip» и «x.tar.gz» → «x».
    static func folderName(for archive: URL) -> String {
        let stem = archive.deletingPathExtension()
        return stem.pathExtension.lowercased() == "tar"
            ? stem.deletingPathExtension().lastPathComponent
            : stem.lastPathComponent
    }

    /// Архив рядом с исходными объектами. nil — если они лежат в разных папках.
    static func archiveURL(for sources: [URL], ext: String) -> URL? {
        guard let first = sources.first else { return nil }
        let dir = first.deletingLastPathComponent()
        guard sources.allSatisfy({ $0.deletingLastPathComponent().path == dir.path }) else { return nil }
        let base: String
        if sources.count > 1 {
            base = dir.path == "/" ? "Archive" : dir.lastPathComponent
        } else {
            var isDirectory: ObjCBool = false
            FileManager.default.fileExists(atPath: first.path, isDirectory: &isDirectory)
            base = isDirectory.boolValue ? first.lastPathComponent : first.deletingPathExtension().lastPathComponent
        }
        let target = dir.appendingPathComponent(base).appendingPathExtension(ext)
        // «x.zip» → «x.zip» добавил бы архив в самого себя.
        return sources.contains { $0.path == target.path }
            ? dir.appendingPathComponent(first.lastPathComponent).appendingPathExtension(ext)
            : target
    }

    /// Свободное имя в том же виде, в каком его выбирает 7-Zip: «файл_1.txt».
    static func available(_ url: URL) -> URL {
        guard exists(url) else { return url }
        let dir = url.deletingLastPathComponent()
        let stem = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        var n = 1
        while true {
            let name = ext.isEmpty ? "\(stem)_\(n)" : "\(stem)_\(n).\(ext)"
            let candidate = dir.appendingPathComponent(name)
            if !exists(candidate) { return candidate }
            n += 1
        }
    }

    /// В отличие от fileExists, видит и «битые» символические ссылки.
    static func exists(_ url: URL) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: url.path)) != nil
    }
}

// MARK: - Запуск процесса

struct ArchiveProcessResult {
    let status: Int32
    let lines: [String]
}

enum ArchiveProcess {
    /// nil — не удалось запустить. `stdin` передаётся программе как ввод с клавиатуры.
    static func run(_ tool: URL, _ arguments: [String], in dir: URL, stdin: String? = nil,
                    environment: [String: String] = [:], discardStandardOutput: Bool = false,
                    isCancelled: () -> Bool) -> ArchiveProcessResult? {
        let process = Process()
        process.executableURL = tool
        process.arguments = arguments
        process.currentDirectoryURL = dir
        // У приложений из Dock локаль не задана, а без UTF-8 пострадают не-ASCII имена.
        process.environment = ProcessInfo.processInfo.environment
            .merging(["LC_ALL": "en_US.UTF-8"]) { _, new in new }
            .merging(environment) { _, new in new }

        if let stdin {
            // Пишем до запуска: в буфер канала это поместится, и программа не успеет его закрыть (SIGPIPE).
            let input = Pipe()
            input.fileHandleForWriting.write(Data((stdin + "\n").utf8))
            try? input.fileHandleForWriting.close()
            process.standardInput = input
        } else {
            process.standardInput = FileHandle.nullDevice
        }

        // Канал надо вычитывать параллельно: при заполнении буфера программа остановится.
        let output = Pipe()
        process.standardOutput = discardStandardOutput ? FileHandle.nullDevice : output
        process.standardError = output
        var data = Data()
        let reading = DispatchGroup()
        reading.enter()
        DispatchQueue.global(qos: .utility).async {
            data = output.fileHandleForReading.readDataToEndOfFile()
            reading.leave()
        }

        do {
            try process.run()
        } catch {
            try? output.fileHandleForWriting.close()
            reading.wait()
            return nil
        }
        try? output.fileHandleForWriting.close()

        var terminated = false
        while process.isRunning {
            if !terminated && isCancelled() {
                process.terminate()
                terminated = true
            }
            usleep(50_000)
        }
        process.waitUntilExit()
        reading.wait()
        let text = String(decoding: data, as: UTF8.self)
        return ArchiveProcessResult(status: process.terminationStatus, lines: text.components(separatedBy: .newlines))
    }
}
