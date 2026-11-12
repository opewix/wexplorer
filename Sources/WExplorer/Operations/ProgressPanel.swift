import AppKit

/// Окно «Копирование...» с полосой прогресса и кнопкой «Отмена».
/// Появляется, только если операция длится дольше 0,4 с.
final class ProgressPanel: NSObject {
    private let panel: NSPanel
    private let nameLabel = NSTextField(labelWithString: "")
    private let pathLabel = NSTextField(labelWithString: "")
    private let bar = NSProgressIndicator()
    private weak var parent: NSWindow?
    private let lock = NSLock()
    private var cancelled = false
    private var finished = false

    /// Читается из фонового потока.
    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    init(title: String, parent: NSWindow?) {
        self.parent = parent
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 130),
            styleMask: [.titled], backing: .buffered, defer: true)
        super.init()
        panel.title = title
        panel.appearance = NSAppearance(named: .aqua)
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false

        let content = LunaView()
        content.wantsLayer = true
        content.layer?.backgroundColor = Luna.face.cgColor

        for label in [nameLabel, pathLabel] {
            label.font = Luna.font
            label.lineBreakMode = .byTruncatingMiddle
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }
        bar.isIndeterminate = false
        bar.minValue = 0
        bar.maxValue = 1
        bar.style = .bar

        let cancel = NSButton(title: tr(.cancel), target: self, action: #selector(cancelPressed))
        cancel.keyEquivalent = "\u{1b}"

        for v in [nameLabel, pathLabel, bar, cancel] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(v)
        }
        NSLayoutConstraint.activate([
            nameLabel.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            nameLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            nameLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            pathLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 4),
            pathLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            pathLabel.trailingAnchor.constraint(equalTo: nameLabel.trailingAnchor),
            bar.topAnchor.constraint(equalTo: pathLabel.bottomAnchor, constant: 10),
            bar.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: nameLabel.trailingAnchor),
            cancel.topAnchor.constraint(equalTo: bar.bottomAnchor, constant: 12),
            cancel.trailingAnchor.constraint(equalTo: nameLabel.trailingAnchor),
        ])
        panel.contentView = content
    }

    func showAfterDelay() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [self] in
            guard !finished else { return }
            if let parent {
                panel.setFrameOrigin(NSPoint(
                    x: parent.frame.midX - panel.frame.width / 2,
                    y: parent.frame.midY - panel.frame.height / 2))
            } else {
                panel.center()
            }
            panel.orderFront(nil)
        }
    }

    /// destination == nil — операция без места назначения (удаление): показывается только папка источника.
    func update(index: Int, total: Int, source: URL, destination: URL?) {
        guard !isCancelled else { return }
        nameLabel.stringValue = source.lastPathComponent
        let from = source.deletingLastPathComponent().lastPathComponent
        pathLabel.stringValue = destination.map { tr(.progressFromTo, from, $0.lastPathComponent) } ?? from
        bar.doubleValue = Double(index) / Double(max(total, 1))
    }

    func close() {
        finished = true
        panel.orderOut(nil)
    }

    @objc private func cancelPressed() {
        lock.lock()
        cancelled = true
        lock.unlock()
        nameLabel.stringValue = tr(.cancelling)
    }
}
