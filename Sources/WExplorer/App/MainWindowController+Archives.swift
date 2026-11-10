import AppKit

/// Команды подменю архивов в контекстном меню. Тег пункта меню указывает на архиватор (`ArchiveKind`).
extension MainWindowController {
    private func archives(for archiver: Archiver) -> [URL] {
        browser.selectedItems.filter { !$0.isDirectory && archiver.canExtract($0.url) }.map(\.url)
    }

    private func archiver(from sender: NSMenuItem) -> Archiver? {
        ArchiveKind(rawValue: sender.tag)?.archiver
    }

    // MARK: Распаковка

    @objc func archiveExtract(_ sender: NSMenuItem) {
        guard let archiver = archiver(from: sender), let window else { return }
        let archives = archives(for: archiver)
        guard !archives.isEmpty else { return }
        let what = archives.count == 1
            ? tr(.quotedName, archives[0].lastPathComponent)
            : tr(.selectedItemsCount, archives.count)
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = tr(.archiveExtract)
        panel.message = tr(.archiveChooseDestination, what)
        panel.directoryURL = location.url ?? archives[0].deletingLastPathComponent()
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let dest = panel.url else { return }
            self?.extract(archives.map { ($0, dest) }, with: archiver, select: [])
        }
    }

    @objc func archiveExtractHere(_ sender: NSMenuItem) {
        guard let archiver = archiver(from: sender) else { return }
        extract(archives(for: archiver).map { ($0, $0.deletingLastPathComponent()) }, with: archiver, select: [])
    }

    @objc func archiveExtractToFolder(_ sender: NSMenuItem) {
        guard let archiver = archiver(from: sender) else { return }
        let jobs = archives(for: archiver).map {
            ($0, $0.deletingLastPathComponent().appendingPathComponent(ArchiveNames.folderName(for: $0)))
        }
        extract(jobs, with: archiver, select: jobs.map(\.1))
    }

    private func extract(_ jobs: [(archive: URL, destination: URL)], with archiver: Archiver, select: [URL]) {
        runArchiver(tr(.archiveExtracting), jobs: jobs) { job, progress in
            archiver.extract(job.archive, to: job.destination, askPassword: { wrong in
                Self.askPassword(for: job.archive, wrong: wrong)
            }, isCancelled: { progress.isCancelled })
        } completion: { [weak self] _ in
            self?.pendingSelection = select.isEmpty ? nil : select
            self?.reload(preserveSelection: true)
        }
    }

    // MARK: Проверка

    @objc func archiveTest(_ sender: NSMenuItem) {
        guard let archiver = archiver(from: sender) else { return }
        let archives = archives(for: archiver)
        let jobs = archives.map { ($0, $0.deletingLastPathComponent()) }
        runArchiver(tr(.archiveTesting), jobs: jobs) { job, progress in
            archiver.test(job.archive, askPassword: { wrong in
                Self.askPassword(for: job.archive, wrong: wrong)
            }, isCancelled: { progress.isCancelled })
        } completion: { allOK in
            if allOK {
                Alerts.message(tr(.archiveTestPassed),
                               info: archives.map(\.lastPathComponent).joined(separator: "\n"))
            }
        }
    }

    // MARK: Сжатие

    @objc func archiveAddTo7z(_ sender: NSMenuItem) {
        addToArchive(ext: "7z", sender)
    }

    @objc func archiveAddToZip(_ sender: NSMenuItem) {
        addToArchive(ext: "zip", sender)
    }

    private func addToArchive(ext: String, _ sender: NSMenuItem) {
        let sources = browser.selectedItems.map(\.url)
        guard let archiver = archiver(from: sender),
              let archive = archiver.archiveURL(for: sources, ext: ext) else { return }
        runArchiver(tr(.archiveCompressing), jobs: [(archive, archive.deletingLastPathComponent())]) { job, progress in
            archiver.add(sources, to: job.archive, isCancelled: { progress.isCancelled })
        } completion: { [weak self] _ in
            self?.pendingSelection = [archive]
            self?.reload(preserveSelection: true)
        }
    }

    /// «Добавить к архиву...»: окно настроек, затем сжатие. Исходные файлы уходят в корзину, только если всё прошло успешно.
    @objc func archiveAddWithDialog(_ sender: NSMenuItem) {
        let sources = browser.selectedItems.map(\.url)
        guard !sources.isEmpty, let window, let sevenZip = SevenZip.installed else { return }
        AddToArchiveDialog.present(sources: sources, over: window) { [weak self] request in
            guard let self else { return }
            let jobs = [(archive: request.archive, destination: request.archive.deletingLastPathComponent())]
            self.runArchiver(tr(.archiveCompressing), jobs: jobs) { job, progress in
                sevenZip.add(sources, to: job.archive, options: request.options, isCancelled: { progress.isCancelled })
            } completion: { [weak self] allOK in
                guard let self else { return }
                if allOK && request.trashSources {
                    self.ops.trash(sources, confirm: false)
                }
                self.pendingSelection = [request.archive]
                self.reload(preserveSelection: true)
            }
        }
    }

    // MARK: Общий запуск

    /// Выполняет задания в фоне по очереди. `completion` получает true, если все прошли без ошибок и отмены.
    private func runArchiver(_ title: String, jobs: [(archive: URL, destination: URL)],
                             work: @escaping ((archive: URL, destination: URL), ProgressPanel) -> ArchiveOutcome,
                             completion: @escaping (Bool) -> Void) {
        guard !jobs.isEmpty else { return }
        let progress = ProgressPanel(title: title, parent: window)
        progress.showAfterDelay()
        DispatchQueue.global(qos: .userInitiated).async {
            var errors: [String] = []
            var finished = true
            for (index, job) in jobs.enumerated() {
                if progress.isCancelled {
                    finished = false
                    break
                }
                DispatchQueue.main.async {
                    progress.update(index: index, total: jobs.count, source: job.archive, destination: job.destination)
                }
                let name = job.archive.lastPathComponent
                switch work(job, progress) {
                case .ok:
                    break
                case .cancelled:
                    finished = false
                case .unsupportedEncryption:
                    errors.append("«\(name)»:\n\(tr(.archiveEncryptionUnsupported))")
                case .failed(let lines):
                    let details = lines.isEmpty ? tr(.archiveCannotRun) : lines.prefix(10).joined(separator: "\n")
                    errors.append("«\(name)»:\n\(details)")
                }
                if !finished { break }
            }
            let allOK = finished && errors.isEmpty
            DispatchQueue.main.async {
                progress.close()
                if !errors.isEmpty {
                    Alerts.error(tr(.archiveFailed), info: errors.prefix(5).joined(separator: "\n\n"))
                }
                completion(allOK)
            }
        }
    }

    /// Вызывается из фонового потока, а окно показывает в главном.
    private static func askPassword(for archive: URL, wrong: Bool) -> String? {
        DispatchQueue.main.sync { Alerts.password(for: archive.lastPathComponent, wrong: wrong) }
    }
}
