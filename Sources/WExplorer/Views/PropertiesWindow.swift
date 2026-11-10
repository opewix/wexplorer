import AppKit

/// Упрощённое окно «Свойства»: тип, расположение, размер (папки считаются в фоне), даты, атрибуты.
final class PropertiesWindowController: NSWindowController, NSWindowDelegate {
    private static var openControllers: [PropertiesWindowController] = []

    private let sizeLabel = PropertiesWindowController.value(tr(.calculating))
    private let containsLabel = PropertiesWindowController.value(tr(.calculating))
    private var cancelled = false

    static func show(for item: FileItem, near parent: NSWindow?) {
        let controller = PropertiesWindowController(item: item)
        openControllers.append(controller)
        if let parent, let window = controller.window {
            window.setFrameTopLeftPoint(NSPoint(x: parent.frame.midX - window.frame.width / 2,
                                                y: parent.frame.maxY - 60))
        }
        controller.showWindow(nil)
    }

    private init(item: FileItem) {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 380, height: 400),
                            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.title = tr(.propertiesTitle, item.name)
        panel.appearance = NSAppearance(named: .aqua)
        panel.isReleasedWhenClosed = false
        super.init(window: panel)
        panel.delegate = self
        build(item, in: panel)
        computeSize(item)
    }

    required init?(coder: NSCoder) { fatalError() }

    private func build(_ item: FileItem, in panel: NSPanel) {
        let icon = NSImageView(image: item.icon)
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.widthAnchor.constraint(equalToConstant: 32).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 32).isActive = true
        let name = NSTextField(labelWithString: item.name)
        name.font = Luna.fontBold
        name.isSelectable = true

        let fm = FileManager.default
        let readOnly = NSButton(checkboxWithTitle: tr(.readOnly), target: nil, action: nil)
        readOnly.state = fm.isWritableFile(atPath: item.url.path) ? .off : .on
        readOnly.isEnabled = false
        let hidden = NSButton(checkboxWithTitle: tr(.hidden), target: nil, action: nil)
        hidden.state = item.isHidden ? .on : .off
        hidden.isEnabled = false
        let attributes = NSStackView(views: [readOnly, hidden])
        attributes.orientation = .horizontal

        let location = Self.value(item.url.deletingLastPathComponent().path)
        location.lineBreakMode = .byTruncatingMiddle
        location.toolTip = item.url.path

        var rows: [[NSView]] = [
            [icon, name],
            [Self.separator(), NSGridCell.emptyContentView],
            [Self.key(tr(.propType)), Self.value(item.typeName)],
            [Self.key(tr(.propLocation)), location],
            [Self.key(tr(.propSize)), sizeLabel],
        ]
        if item.isDirectory && !item.isVolume {
            rows.append([Self.key(tr(.propContains)), containsLabel])
        }
        rows += [
            [Self.separator(), NSGridCell.emptyContentView],
            [Self.key(tr(.propCreated)), Self.value(Format.date(item.created))],
            [Self.key(tr(.propModified)), Self.value(Format.date(item.modified))],
            [Self.separator(), NSGridCell.emptyContentView],
            [Self.key(tr(.propAttributes)), attributes],
        ]

        let grid = NSGridView(views: rows)
        grid.rowSpacing = 8
        grid.columnSpacing = 10
        grid.column(at: 0).xPlacement = .leading
        grid.column(at: 1).width = 240
        for i in 0..<grid.numberOfRows where rows[i].first is NSBox {
            grid.row(at: i).mergeCells(in: NSRange(location: 0, length: 2))
        }

        let ok = NSButton(title: tr(.ok), target: self, action: #selector(closeWindow))
        ok.keyEquivalent = "\r"

        let content = LunaView()
        content.wantsLayer = true
        content.layer?.backgroundColor = Luna.face.cgColor
        for v in [grid, ok] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(v)
        }
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            grid.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            grid.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            ok.topAnchor.constraint(equalTo: grid.bottomAnchor, constant: 16),
            ok.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            ok.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -14),
            ok.widthAnchor.constraint(greaterThanOrEqualToConstant: 80),
        ])
        panel.contentView = content
        panel.setContentSize(content.fittingSize)
    }

    private func computeSize(_ item: FileItem) {
        if item.isVolume {
            sizeLabel.stringValue = item.detail ?? "—"
            return
        }
        guard item.isDirectory else {
            sizeLabel.stringValue = Self.sizeText(item.size ?? 0)
            return
        }
        let url = item.url
        DispatchQueue.global(qos: .utility).async { [weak self] in
            var total: Int64 = 0, files = 0, folders = 0
            var lastUpdate = Date()
            let enumerator = FileManager.default.enumerator(
                at: url, includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
                options: [], errorHandler: { _, _ in true })
            while let next = enumerator?.nextObject() as? URL {
                if self?.cancelled ?? true { return }
                let values = try? next.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
                if values?.isDirectory == true {
                    folders += 1
                } else {
                    files += 1
                    total += Int64(values?.fileSize ?? 0)
                }
                if Date().timeIntervalSince(lastUpdate) > 0.3 {
                    lastUpdate = Date()
                    let snapshot = (total, files, folders)
                    DispatchQueue.main.async { self?.show(snapshot.0, snapshot.1, snapshot.2) }
                }
            }
            DispatchQueue.main.async { self?.show(total, files, folders) }
        }
    }

    private func show(_ total: Int64, _ files: Int, _ folders: Int) {
        sizeLabel.stringValue = Self.sizeText(total)
        containsLabel.stringValue = tr(.filesAndFolders, files, folders)
    }

    private static func sizeText(_ bytes: Int64) -> String {
        "\(Format.size(bytes)) (\(Format.bytesExact(bytes)))"
    }

    private static func key(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = Luna.font
        return label
    }

    private static func value(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = Luna.font
        label.isSelectable = true
        label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }

    private static func separator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        return box
    }

    @objc private func closeWindow() {
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        cancelled = true
        Self.openControllers.removeAll { $0 === self }
    }
}
