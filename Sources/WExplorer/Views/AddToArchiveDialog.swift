import AppKit

/// Окно «Добавить к архиву» по образцу 7-Zip для Windows.
final class AddToArchiveDialog: NSObject {
    struct Request {
        let archive: URL
        let options: SevenZipAddOptions
        let trashSources: Bool
    }

    private static var current: AddToArchiveDialog?
    private static let formatKey = "archiveDialogFormat"
    private static let levelKey = "archiveDialogLevel"

    let panel: NSPanel
    private let sources: [URL]
    private let folder: URL
    private let onConfirm: (Request) -> Void

    let nameField = NSTextField()
    let formatPopup = NSPopUpButton()
    let levelPopup = NSPopUpButton()
    let methodPopup = NSPopUpButton()
    let dictionaryPopup = NSPopUpButton()
    let wordPopup = NSPopUpButton()
    let solidPopup = NSPopUpButton()
    let threadsPopup = NSPopUpButton()
    let volumesField = NSComboBox()
    let parametersField = NSTextField()
    let updatePopup = NSPopUpButton()
    let pathPopup = NSPopUpButton()
    let deleteCheck = NSButton(checkboxWithTitle: tr(.archiveDeleteAfter), target: nil, action: nil)
    let passwordField = NSSecureTextField()
    let plainPasswordField = NSTextField()
    let repeatField = NSSecureTextField()
    let showPasswordCheck = NSButton(checkboxWithTitle: tr(.archiveShowPassword), target: nil, action: nil)
    let encryptionPopup = NSPopUpButton()
    let encryptNamesCheck = NSButton(checkboxWithTitle: tr(.archiveEncryptNames), target: nil, action: nil)
    private let repeatLabel = NSTextField(labelWithString: tr(.archivePasswordRepeatLabel))
    private var showBelowRepeat: NSLayoutConstraint?
    private var showBelowPassword: NSLayoutConstraint?

    // MARK: Показ

    static func present(sources: [URL], over parent: NSWindow, onConfirm: @escaping (Request) -> Void) {
        let dialog = AddToArchiveDialog(sources: sources, onConfirm: onConfirm)
        current = dialog
        parent.beginSheet(dialog.panel) { _ in current = nil }
    }

    init(sources: [URL], onConfirm: @escaping (Request) -> Void) {
        self.sources = sources
        folder = sources[0].deletingLastPathComponent()
        self.onConfirm = onConfirm
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 700, height: 480),
                        styleMask: [.titled], backing: .buffered, defer: false)
        super.init()
        panel.title = tr(.archiveAddTitle)
        panel.appearance = NSAppearance(named: .aqua)
        panel.isReleasedWhenClosed = false
        build()
        fillInitialValues()
    }

    /// gzip, bzip2 и xz доступны только для одного файла, как и в Windows.
    private var availableFormats: [SevenZipFormat] {
        var isDirectory: ObjCBool = false
        FileManager.default.fileExists(atPath: sources[0].path, isDirectory: &isDirectory)
        let singleFile = sources.count == 1 && !isDirectory.boolValue
        return SevenZipFormat.allCases.filter { singleFile || !$0.onlySingleFile }
    }

    // MARK: Построение

    private func build() {
        let folderLabel = NSTextField(labelWithString: folder.path)
        folderLabel.font = Luna.font
        folderLabel.lineBreakMode = .byTruncatingMiddle
        folderLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        nameField.font = Luna.font
        nameField.controlSize = .small
        let browse = NSButton(title: "...", target: self, action: #selector(browsePressed))
        browse.controlSize = .small
        browse.font = Luna.font
        browse.widthAnchor.constraint(equalToConstant: 34).isActive = true
        let nameRow = NSStackView(views: [nameField, browse])
        nameRow.spacing = 6
        let archive = NSStackView(views: [Self.label(tr(.archiveFieldArchive)), folderLabel])
        archive.spacing = 8

        for popup in [formatPopup, levelPopup, methodPopup, dictionaryPopup, wordPopup, solidPopup, threadsPopup,
                      updatePopup, pathPopup, encryptionPopup] {
            popup.controlSize = .small
            popup.font = Luna.font
        }
        for (popup, action) in [(formatPopup, #selector(formatChanged)), (levelPopup, #selector(levelChanged)),
                                (methodPopup, #selector(methodChanged))] {
            popup.target = self
            popup.action = action
        }
        for field in [parametersField, passwordField, plainPasswordField, repeatField] as [NSTextField] {
            field.font = Luna.font
            field.controlSize = .small
        }
        repeatLabel.font = Luna.font
        volumesField.font = Luna.font
        volumesField.controlSize = .small
        volumesField.completes = false
        volumesField.addItems(withObjectValues: ["10M", "100M", "1000M", "650M - CD", "700M - CD", "4092M - FAT",
                                                 "4480M - DVD", "8128M - DVD DL", "23040M - BD"])

        // Левая колонка.
        let settings = NSGridView(views: [
            [Self.label(tr(.archiveFormatLabel)), formatPopup],
            [Self.label(tr(.archiveLevelLabel)), levelPopup],
            [Self.label(tr(.archiveMethodLabel)), methodPopup],
            [Self.label(tr(.archiveDictionaryLabel)), dictionaryPopup],
            [Self.label(tr(.archiveWordLabel)), wordPopup],
            [Self.label(tr(.archiveSolidLabel)), solidPopup],
            [Self.label(tr(.archiveThreadsLabel)), threadsPopup],
        ])
        settings.rowAlignment = .firstBaseline
        settings.rowSpacing = 7
        settings.columnSpacing = 10
        settings.column(at: 0).xPlacement = .leading
        settings.column(at: 1).xPlacement = .fill
        settings.column(at: 1).width = 170
        let left = NSStackView(views: [
            settings,
            Self.label(tr(.archiveVolumesLabel)), volumesField,
            Self.label(tr(.archiveParametersLabel)), parametersField,
        ])
        left.orientation = .vertical
        left.alignment = .leading
        left.spacing = 5
        left.setCustomSpacing(14, after: settings)
        left.setCustomSpacing(12, after: volumesField)

        // Правая колонка.
        let modes = NSGridView(views: [
            [Self.label(tr(.archiveUpdateLabel)), updatePopup],
            [Self.label(tr(.archivePathModeLabel)), pathPopup],
        ])
        modes.rowAlignment = .firstBaseline
        modes.rowSpacing = 7
        modes.columnSpacing = 10
        modes.column(at: 0).xPlacement = .leading
        modes.column(at: 1).xPlacement = .fill

        deleteCheck.font = Luna.font
        deleteCheck.controlSize = .small
        deleteCheck.setContentCompressionResistancePriority(.required, for: .vertical)
        let options = Self.box(tr(.archiveOptionsGroup), deleteCheck)

        // Открытое и скрытое поля лежат друг на друге: «Показать пароль» переключает их.
        let passwordStack = NSView()
        for field in [passwordField, plainPasswordField] as [NSTextField] {
            field.translatesAutoresizingMaskIntoConstraints = false
            passwordStack.addSubview(field)
            NSLayoutConstraint.activate([
                field.topAnchor.constraint(equalTo: passwordStack.topAnchor),
                field.bottomAnchor.constraint(equalTo: passwordStack.bottomAnchor),
                field.leadingAnchor.constraint(equalTo: passwordStack.leadingAnchor),
                field.trailingAnchor.constraint(equalTo: passwordStack.trailingAnchor),
            ])
        }
        plainPasswordField.isHidden = true
        showPasswordCheck.font = Luna.font
        showPasswordCheck.controlSize = .small
        showPasswordCheck.target = self
        showPasswordCheck.action = #selector(showPasswordChanged)
        encryptNamesCheck.font = Luna.font
        encryptNamesCheck.controlSize = .small

        // Явная цепочка связей: в стеках и таблицах строки со списками схлопывались и наезжали друг на друга.
        let passwordLabel = Self.label(tr(.archivePasswordLabel))
        let methodLabel = Self.label(tr(.archiveEncryptionMethodLabel))
        let encryption = NSView()
        for view in [passwordLabel, passwordStack, repeatLabel, repeatField, showPasswordCheck,
                     methodLabel, encryptionPopup, encryptNamesCheck] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            encryption.addSubview(view)
            // Иначе прижатая по высоте рамка сжимает галочки и список, и строки наезжают друг на друга.
            view.setContentCompressionResistancePriority(.required, for: .vertical)
        }
        let controlsLeading: CGFloat = 133
        let belowRepeat = showPasswordCheck.topAnchor.constraint(equalTo: repeatField.bottomAnchor, constant: 8)
        showBelowRepeat = belowRepeat
        showBelowPassword = showPasswordCheck.topAnchor.constraint(equalTo: passwordStack.bottomAnchor, constant: 8)
        NSLayoutConstraint.activate([
            passwordStack.topAnchor.constraint(equalTo: encryption.topAnchor),
            passwordStack.heightAnchor.constraint(equalToConstant: 22),
            passwordStack.leadingAnchor.constraint(equalTo: encryption.leadingAnchor, constant: controlsLeading),
            passwordStack.trailingAnchor.constraint(equalTo: encryption.trailingAnchor),
            passwordLabel.leadingAnchor.constraint(equalTo: encryption.leadingAnchor),
            passwordLabel.centerYAnchor.constraint(equalTo: passwordStack.centerYAnchor),

            repeatField.topAnchor.constraint(equalTo: passwordStack.bottomAnchor, constant: 8),
            repeatField.heightAnchor.constraint(equalToConstant: 22),
            repeatField.leadingAnchor.constraint(equalTo: passwordStack.leadingAnchor),
            repeatField.trailingAnchor.constraint(equalTo: passwordStack.trailingAnchor),
            repeatLabel.leadingAnchor.constraint(equalTo: encryption.leadingAnchor),
            repeatLabel.centerYAnchor.constraint(equalTo: repeatField.centerYAnchor),

            belowRepeat,
            showPasswordCheck.leadingAnchor.constraint(equalTo: encryption.leadingAnchor),

            encryptionPopup.topAnchor.constraint(equalTo: showPasswordCheck.bottomAnchor, constant: 8),
            encryptionPopup.leadingAnchor.constraint(equalTo: passwordStack.leadingAnchor),
            encryptionPopup.trailingAnchor.constraint(equalTo: passwordStack.trailingAnchor),
            methodLabel.leadingAnchor.constraint(equalTo: encryption.leadingAnchor),
            methodLabel.centerYAnchor.constraint(equalTo: encryptionPopup.centerYAnchor),

            encryptNamesCheck.topAnchor.constraint(equalTo: encryptionPopup.bottomAnchor, constant: 8),
            encryptNamesCheck.leadingAnchor.constraint(equalTo: encryption.leadingAnchor),
            encryptNamesCheck.bottomAnchor.constraint(equalTo: encryption.bottomAnchor),
        ])
        let encryptionBox = Self.box(tr(.archiveEncryptionGroup), encryption)

        // Лишнюю высоту забирает распорка, иначе она появляется между строками режимов.
        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .vertical)
        for view in [modes, options, encryptionBox] as [NSView] {
            view.setContentHuggingPriority(.required, for: .vertical)
        }
        let right = NSStackView(views: [modes, options, encryptionBox, spacer])
        right.orientation = .vertical
        right.alignment = .leading
        right.spacing = 12

        let columns = NSStackView(views: [left, right])
        columns.orientation = .horizontal
        columns.alignment = .top
        columns.spacing = 18

        let ok = NSButton(title: tr(.ok), target: self, action: #selector(okPressed))
        ok.keyEquivalent = "\r"
        let cancel = NSButton(title: tr(.cancel), target: self, action: #selector(cancelPressed))
        cancel.keyEquivalent = "\u{1b}"
        for button in [ok, cancel] {
            button.font = Luna.font
            button.widthAnchor.constraint(greaterThanOrEqualToConstant: 80).isActive = true
        }

        let content = LunaView()
        content.wantsLayer = true
        content.layer?.backgroundColor = Luna.face.cgColor
        for view in [archive, nameRow, columns, ok, cancel] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(view)
        }
        NSLayoutConstraint.activate([
            archive.topAnchor.constraint(equalTo: content.topAnchor, constant: 14),
            archive.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            archive.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            nameRow.topAnchor.constraint(equalTo: archive.bottomAnchor, constant: 5),
            nameRow.leadingAnchor.constraint(equalTo: archive.leadingAnchor),
            nameRow.trailingAnchor.constraint(equalTo: archive.trailingAnchor),
            columns.topAnchor.constraint(equalTo: nameRow.bottomAnchor, constant: 14),
            columns.leadingAnchor.constraint(equalTo: archive.leadingAnchor),
            columns.trailingAnchor.constraint(equalTo: archive.trailingAnchor),
            left.widthAnchor.constraint(equalToConstant: 300),
            volumesField.widthAnchor.constraint(equalTo: left.widthAnchor),
            parametersField.widthAnchor.constraint(equalTo: left.widthAnchor),
            settings.widthAnchor.constraint(equalTo: left.widthAnchor),
            options.widthAnchor.constraint(equalTo: right.widthAnchor),
            encryptionBox.widthAnchor.constraint(equalTo: right.widthAnchor),
            modes.widthAnchor.constraint(equalTo: right.widthAnchor),
            right.widthAnchor.constraint(equalToConstant: 340),
            // Ширина задана явно: иначе длинный путь к папке раздвигал бы окно.
            content.widthAnchor.constraint(equalToConstant: 690),
            cancel.topAnchor.constraint(equalTo: columns.bottomAnchor, constant: 14),
            cancel.trailingAnchor.constraint(equalTo: archive.trailingAnchor),
            cancel.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -14),
            ok.centerYAnchor.constraint(equalTo: cancel.centerYAnchor),
            ok.trailingAnchor.constraint(equalTo: cancel.leadingAnchor, constant: -8),
        ])
        panel.contentView = content
        panel.setContentSize(content.fittingSize)
    }

    private static func label(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = Luna.font
        return label
    }

    private static func box(_ title: String, _ inner: NSView) -> NSBox {
        let box = NSBox()
        box.title = title
        box.titleFont = Luna.font
        let holder = NSView()
        inner.translatesAutoresizingMaskIntoConstraints = false
        holder.addSubview(inner)
        NSLayoutConstraint.activate([
            inner.topAnchor.constraint(equalTo: holder.topAnchor, constant: 6),
            inner.bottomAnchor.constraint(equalTo: holder.bottomAnchor, constant: -6),
            inner.leadingAnchor.constraint(equalTo: holder.leadingAnchor, constant: 8),
            inner.trailingAnchor.constraint(equalTo: holder.trailingAnchor, constant: -8),
        ])
        box.contentView = holder
        // Без этих связей рамка не знает высоту содержимого и сжимает его так, что строки наезжают друг на друга.
        holder.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            holder.topAnchor.constraint(equalTo: box.topAnchor, constant: 22),
            holder.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -4),
            holder.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 4),
            holder.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -4),
        ])
        return box
    }

    // MARK: Значения

    private func fillInitialValues() {
        let formats = availableFormats
        Self.fill(formatPopup, formats.map { ($0.rawValue, $0 as Any) })
        let saved = UserDefaults.standard.string(forKey: Self.formatKey).flatMap(SevenZipFormat.init(rawValue:))
        if let saved, let index = formats.firstIndex(of: saved) { formatPopup.selectItem(at: index) }

        Self.fill(updatePopup, [
            (tr(.archiveUpdateAddReplace), SevenZipUpdateMode.addAndReplace),
            (tr(.archiveUpdateAddUpdate), SevenZipUpdateMode.updateAndAdd),
            (tr(.archiveUpdateFreshen), SevenZipUpdateMode.freshen),
            (tr(.archiveUpdateSync), SevenZipUpdateMode.synchronize),
        ])
        Self.fill(pathPopup, [
            (tr(.archivePathRelative), SevenZipPathMode.relative),
            (tr(.archivePathFull), SevenZipPathMode.full),
            (tr(.archivePathAbsolute), SevenZipPathMode.absolute),
        ])
        Self.fill(threadsPopup, [(tr(.archiveAuto), Optional<Int>.none as Any)]
            + (1...max(ProcessInfo.processInfo.activeProcessorCount, 1)).map { (String($0), $0 as Any) })

        nameField.stringValue = ArchiveNames.archiveURL(for: sources, ext: selectedFormat.fileExtension)?
            .lastPathComponent ?? ""
        refreshForFormat(restoringSavedLevel: true)
    }

    /// Заполняет список, сохраняя выбор, если такой пункт остался.
    private static func fill(_ popup: NSPopUpButton, _ items: [(String, Any)], defaultIndex: Int = 0) {
        let previous = popup.titleOfSelectedItem
        popup.removeAllItems()
        for (title, value) in items {
            popup.addItem(withTitle: title)
            popup.lastItem?.representedObject = value
        }
        if let previous, popup.indexOfItem(withTitle: previous) >= 0 {
            popup.selectItem(withTitle: previous)
        } else if !items.isEmpty {
            popup.selectItem(at: min(defaultIndex, items.count - 1))
        }
    }

    private var selectedFormat: SevenZipFormat {
        formatPopup.selectedItem?.representedObject as? SevenZipFormat ?? .sevenZ
    }
    private var selectedLevel: Int {
        levelPopup.selectedItem?.representedObject as? Int ?? 5
    }
    private var selectedMethod: SevenZipMethod? {
        methodPopup.selectedItem?.representedObject as? SevenZipMethod
    }

    private func refreshForFormat(restoringSavedLevel: Bool = false) {
        let format = selectedFormat
        let levels = format.levels
        Self.fill(levelPopup, levels.isEmpty
            ? [(tr(.archiveLevelStore), 0 as Any)]
            : levels.map { (Self.levelTitle($0), $0 as Any) },
            defaultIndex: levels.firstIndex(of: 5) ?? 0)
        if restoringSavedLevel, let saved = UserDefaults.standard.object(forKey: Self.levelKey) as? Int,
           let index = levels.firstIndex(of: saved) {
            levelPopup.selectItem(at: index)
        }
        levelPopup.isEnabled = !levels.isEmpty

        Self.fill(solidPopup, [(tr(.archiveAuto), Optional<String>.none as Any), (tr(.archiveSolidOff), "off" as Any)]
            + ["1m", "4m", "16m", "64m", "256m", "1g", "4g", "16g", "64g"].map { (Self.blockTitle($0), $0 as Any) }
            + [(tr(.archiveSolidOn), "on" as Any)])
        threadsPopup.isEnabled = format.supportsThreads

        let canEncrypt = format.supportsPassword
        for field in [passwordField, plainPasswordField, repeatField] as [NSTextField] { field.isEnabled = canEncrypt }
        showPasswordCheck.isEnabled = canEncrypt
        encryptNamesCheck.isEnabled = format.supportsEncryptedNames
        if !format.supportsEncryptedNames { encryptNamesCheck.state = .off }
        // Без очистки выбор «AES-256» от 7z перешёл бы к zip, а по умолчанию там ZipCrypto, как и в Windows.
        encryptionPopup.removeAllItems()
        Self.fill(encryptionPopup, format == .zip
            ? [("ZipCrypto", SevenZipZipEncryption.zipCrypto as Any), ("AES-256", SevenZipZipEncryption.aes256 as Any)]
            : (format == .sevenZ ? [("AES-256", SevenZipZipEncryption.aes256 as Any)] : []))
        encryptionPopup.isEnabled = format == .zip

        refreshForLevel()
    }

    private func refreshForLevel() {
        let format = selectedFormat
        let compresses = selectedLevel > 0 && !format.levels.isEmpty
        Self.fill(methodPopup, compresses ? format.methods.map { ($0.rawValue, $0 as Any) } : [])
        methodPopup.isEnabled = compresses && format.methods.count > 1
        solidPopup.isEnabled = compresses && format.supportsSolid
        refreshForMethod()
    }

    private func refreshForMethod() {
        guard let method = selectedMethod else {
            for popup in [dictionaryPopup, wordPopup] {
                popup.removeAllItems()
                popup.isEnabled = false
            }
            return
        }
        if let fixed = method.fixedDictionary {
            Self.fill(dictionaryPopup, [(Self.sizeTitle(fixed), Optional<Int64>.none as Any)])
            dictionaryPopup.isEnabled = false
        } else {
            Self.fill(dictionaryPopup, [(tr(.archiveAuto), Optional<Int64>.none as Any)]
                + method.dictionaries(in: selectedFormat).map { (Self.sizeTitle($0), $0 as Any) })
            dictionaryPopup.isEnabled = true
        }
        let wordSizes = method.wordSizes(in: selectedFormat)
        if wordSizes.isEmpty {
            wordPopup.removeAllItems()
            wordPopup.isEnabled = false
        } else {
            Self.fill(wordPopup, [(tr(.archiveAuto), Optional<Int>.none as Any)]
                + wordSizes.map { (String($0), $0 as Any) })
            wordPopup.isEnabled = true
        }
    }

    private static func levelTitle(_ level: Int) -> String {
        switch level {
        case 0: return tr(.archiveLevelStore)
        case 1: return tr(.archiveLevelFastest)
        case 3: return tr(.archiveLevelFast)
        case 5: return tr(.archiveLevelNormal)
        case 7: return tr(.archiveLevelMaximum)
        default: return tr(.archiveLevelUltra)
        }
    }

    private static func sizeTitle(_ bytes: Int64) -> String {
        bytes < 1024 * 1024
            ? "\(bytes / 1024) \(tr(.unitKB))"
            : "\(bytes / (1024 * 1024)) \(tr(.unitMB))"
    }

    private static func blockTitle(_ value: String) -> String {
        let number = value.dropLast()
        return "\(number) \(value.hasSuffix("g") ? tr(.unitGB) : tr(.unitMB))"
    }

    // MARK: Реакция на выбор

    @objc private func formatChanged() {
        let format = selectedFormat
        let name = nameField.stringValue as NSString
        let known = SevenZipFormat.allCases.map(\.fileExtension)
        let base = known.contains(name.pathExtension.lowercased()) ? name.deletingPathExtension : name as String
        nameField.stringValue = (base as NSString).appendingPathExtension(format.fileExtension) ?? base
        refreshForFormat()
    }

    @objc private func levelChanged() {
        refreshForLevel()
    }

    @objc private func methodChanged() {
        refreshForMethod()
    }

    @objc private func showPasswordChanged() {
        let show = showPasswordCheck.state == .on
        if show {
            plainPasswordField.stringValue = passwordField.stringValue
        } else {
            passwordField.stringValue = plainPasswordField.stringValue
            repeatField.stringValue = ""
        }
        plainPasswordField.isHidden = !show
        passwordField.isHidden = show
        // Как и в Windows: открытый пароль видно, поэтому повторять его незачем.
        repeatField.isHidden = show
        repeatLabel.isHidden = show
        showBelowRepeat?.isActive = !show
        showBelowPassword?.isActive = show
    }

    @objc private func browsePressed() {
        let save = NSSavePanel()
        save.directoryURL = resolvedArchive?.deletingLastPathComponent() ?? folder
        save.nameFieldStringValue = resolvedArchive?.lastPathComponent ?? nameField.stringValue
        save.canCreateDirectories = true
        save.beginSheetModal(for: panel) { [weak self] response in
            guard response == .OK, let self, let url = save.url else { return }
            self.nameField.stringValue = url.deletingLastPathComponent().path == self.folder.path
                ? url.lastPathComponent
                : url.path
        }
    }

    @objc private func cancelPressed() {
        finish()
    }

    @objc private func okPressed() {
        guard let request = validatedRequest() else { return }
        UserDefaults.standard.set(request.options.format.rawValue, forKey: Self.formatKey)
        UserDefaults.standard.set(request.options.level, forKey: Self.levelKey)
        finish()
        onConfirm(request)
    }

    private func finish() {
        if let parent = panel.sheetParent {
            parent.endSheet(panel)
        } else {
            panel.orderOut(nil)
        }
    }

    // MARK: Результат

    /// Имя можно ввести относительно папки объектов или целиком; «~» тоже понимается.
    private var resolvedArchive: URL? {
        let text = nameField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        let expanded = (text as NSString).expandingTildeInPath
        let url = expanded.hasPrefix("/")
            ? URL(fileURLWithPath: expanded)
            : folder.appendingPathComponent(expanded)
        return url.standardizedFileURL
    }

    private var currentPassword: String {
        showPasswordCheck.state == .on ? plainPasswordField.stringValue : passwordField.stringValue
    }

    private static func realPath(_ url: URL) -> String {
        guard let resolved = realpath(url.path, nil) else { return url.path }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    /// Показывает ошибку и возвращает nil, если что-то заполнено неверно.
    private func validatedRequest() -> Request? {
        guard let archive = resolvedArchive else {
            Alerts.error(tr(.archiveBadDestination))
            return nil
        }
        var isDirectory: ObjCBool = false
        let parentExists = FileManager.default.fileExists(
            atPath: archive.deletingLastPathComponent().path, isDirectory: &isDirectory)
        guard parentExists, isDirectory.boolValue,
              !(FileManager.default.fileExists(atPath: archive.path, isDirectory: &isDirectory) && isDirectory.boolValue)
        else {
            Alerts.error(tr(.archiveBadDestination), info: archive.path)
            return nil
        }
        // Сравниваем настоящие пути: иначе /tmp и /private/tmp выглядели бы разными папками,
        // а архив внутри выбранной папки потом ушёл бы в корзину вместе с ней.
        let archivePath = Self.realPath(archive.deletingLastPathComponent()) + "/" + archive.lastPathComponent
        for source in sources.map(Self.realPath)
        where archivePath == source || archivePath.hasPrefix(source + "/") {
            Alerts.error(tr(.archiveBadDestination), info: tr(.destinationInsideSource))
            return nil
        }

        guard let volume = SevenZipAddOptions.volumeSwitch(from: volumesField.stringValue) else {
            Alerts.error(tr(.archiveBadVolumeSize), info: volumesField.stringValue)
            return nil
        }

        let format = selectedFormat
        let password = format.supportsPassword ? currentPassword : ""
        if showPasswordCheck.state == .off && format.supportsPassword && password != repeatField.stringValue {
            Alerts.error(tr(.archivePasswordMismatch))
            return nil
        }
        if format == .zip && !SevenZipAddOptions.isValidZipPassword(password) {
            Alerts.error(tr(.archivePasswordASCII))
            return nil
        }

        var options = SevenZipAddOptions()
        options.format = format
        options.level = selectedLevel
        options.method = selectedMethod
        options.dictionary = dictionaryPopup.isEnabled ? dictionaryPopup.selectedItem?.representedObject as? Int64 : nil
        options.wordSize = wordPopup.isEnabled ? wordPopup.selectedItem?.representedObject as? Int : nil
        options.solid = solidPopup.isEnabled ? solidPopup.selectedItem?.representedObject as? String : nil
        options.threads = threadsPopup.isEnabled ? threadsPopup.selectedItem?.representedObject as? Int : nil
        options.volumeSize = volume.isEmpty ? nil : volume
        options.parameters = parametersField.stringValue
        options.updateMode = updatePopup.selectedItem?.representedObject as? SevenZipUpdateMode ?? .addAndReplace
        options.pathMode = pathPopup.selectedItem?.representedObject as? SevenZipPathMode ?? .relative
        options.password = password
        options.zipEncryption = encryptionPopup.selectedItem?.representedObject as? SevenZipZipEncryption ?? .zipCrypto
        options.encryptNames = encryptNamesCheck.isEnabled && encryptNamesCheck.state == .on
        return Request(archive: archive, options: options, trashSources: deleteCheck.state == .on)
    }

    /// Для проверок: что получится при нажатии OK.
    func requestForTesting() -> Request? {
        validatedRequest()
    }

    /// Для проверок: выбор пункта с тем же эффектом, что и у пользователя.
    func simulateFormat(_ format: SevenZipFormat) {
        formatPopup.selectItem(withTitle: format.rawValue)
        formatChanged()
    }
    func simulateLevel(at index: Int) {
        levelPopup.selectItem(at: index)
        levelChanged()
    }
    func simulateMethod(_ method: SevenZipMethod) {
        methodPopup.selectItem(withTitle: method.rawValue)
        methodChanged()
    }
    func simulateShowPassword(_ show: Bool) {
        showPasswordCheck.state = show ? .on : .off
        showPasswordChanged()
    }
}
