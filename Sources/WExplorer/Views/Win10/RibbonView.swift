import AppKit

/// Команда ленты. Работает как пункт меню: тот же селектор и тег, та же проверка доступности
/// (`validateMenuItem` окна), поэтому лента всегда согласована с меню.
struct RibbonCommand {
    var title: String
    var icon: XPIcon?
    /// Действие и одновременно ключ проверки доступности. nil — кнопка доступна всегда.
    var action: Selector?
    var tag = 0
    /// Кнопка с ▾: щелчок открывает меню.
    var menu: (() -> NSMenu)?
    /// Своё действие вместо селектора, когда нужна сама кнопка (например, якорь для «Поделиться»).
    var custom: ((NSView) -> Void)?

    init(_ title: String, _ icon: XPIcon?, _ action: Selector?, tag: Int = 0,
         menu: (() -> NSMenu)? = nil, custom: ((NSView) -> Void)? = nil) {
        self.title = title
        self.icon = icon
        self.action = action
        self.tag = tag
        self.menu = menu
        self.custom = custom
    }
}

enum RibbonItem {
    /// Большая кнопка: значок 32×32, подпись в одну-две строки.
    case large(RibbonCommand)
    /// Столбик до трёх маленьких кнопок.
    case small([RibbonCommand])
    /// Столбик флажков.
    case checks([RibbonCommand])
    /// Галерея переключателей в белой рамке (виды «Структуры»).
    case gallery([RibbonCommand], columns: Int)
}

struct RibbonGroup {
    var title: String
    var items: [RibbonItem]
}

struct RibbonTab {
    var title: String
    var groups: [RibbonGroup]
}

/// Лента Проводника Windows 10: синяя вкладка «Файл», вкладки команд и панель с группами.
/// По умолчанию свёрнута: щелчок по вкладке открывает панель поверх списка, команда или щелчок
/// мимо — закрывают. Закреплённая лента (шеврон справа или двойной щелчок по вкладке) стоит на месте.
final class RibbonView: LunaView {
    var tabs: [RibbonTab] = [] { didSet { selected = min(selected, max(tabs.count - 1, 0)); rebuildPanel() } }
    var fileMenu: (() -> NSMenu)?
    var validate: ((NSMenuItem) -> Bool)?
    var perform: ((RibbonCommand, NSView) -> Void)?
    var onHelp: (() -> Void)?
    /// Вид окна, поверх которого открывается свёрнутая лента.
    weak var overlayHost: NSView?

    private static let pinnedKey = "ribbonPinned"
    private(set) var isPinned = UserDefaults.standard.bool(forKey: RibbonView.pinnedKey)
    private var selected = 0
    private var isOpenTemporarily = false

    private let strip = RibbonTabStrip()
    private let panel = RibbonPanel()
    private var height: NSLayoutConstraint!
    private var panelConstraints: [NSLayoutConstraint] = []
    private var monitor: Any?

    override init(frame: NSRect) {
        super.init(frame: frame)
        strip.translatesAutoresizingMaskIntoConstraints = false
        addSubview(strip)
        height = heightAnchor.constraint(equalToConstant: Win10.tabStripHeight)
        NSLayoutConstraint.activate([
            strip.topAnchor.constraint(equalTo: topAnchor),
            strip.leadingAnchor.constraint(equalTo: leadingAnchor),
            strip.trailingAnchor.constraint(equalTo: trailingAnchor),
            strip.heightAnchor.constraint(equalToConstant: Win10.tabStripHeight),
            height,
        ])
        strip.onFile = { [weak self] view in self?.showFileMenu(from: view) }
        strip.onTab = { [weak self] index, clicks in self?.tabClicked(index, clicks: clicks) }
        strip.onTogglePin = { [weak self] in self?.setPinned(!(self?.isPinned ?? false)) }
        strip.onHelp = { [weak self] in self?.onHelp?() }
        panel.onPerform = { [weak self] command, view in self?.run(command, from: view) }
        panel.translatesAutoresizingMaskIntoConstraints = false
        applyState()
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit { stopMonitor() }

    /// Обновляет доступность и отметки кнопок — после смены выделения, папки, настроек.
    func refresh() {
        panel.refresh(validate)
    }

    // MARK: Состояние

    private var isPanelVisible: Bool { isPinned || isOpenTemporarily }

    private func setPinned(_ pinned: Bool) {
        isPinned = pinned
        isOpenTemporarily = false
        UserDefaults.standard.set(pinned, forKey: Self.pinnedKey)
        applyState()
    }

    private func tabClicked(_ index: Int, clicks: Int) {
        if clicks >= 2 {
            selected = index
            rebuildPanel()
            setPinned(!isPinned)
            return
        }
        if isPinned {
            selected = index
            rebuildPanel()
        } else if isOpenTemporarily && selected == index {
            closeTemporary()
        } else {
            selected = index
            rebuildPanel()
            isOpenTemporarily = true
            applyState()
        }
    }

    private func closeTemporary() {
        guard isOpenTemporarily else { return }
        isOpenTemporarily = false
        applyState()
    }

    private func applyState() {
        strip.titles = tabs.map(\.title)
        strip.selected = isPanelVisible ? selected : nil
        strip.isPinned = isPinned
        NSLayoutConstraint.deactivate(panelConstraints)
        panel.removeFromSuperview()
        stopMonitor()
        panel.showsShadow = false

        if isPinned {
            addSubview(panel)
            panelConstraints = [
                panel.topAnchor.constraint(equalTo: strip.bottomAnchor),
                panel.leadingAnchor.constraint(equalTo: leadingAnchor),
                panel.trailingAnchor.constraint(equalTo: trailingAnchor),
                panel.heightAnchor.constraint(equalToConstant: Win10.ribbonPanelHeight),
            ]
            height.constant = Win10.tabStripHeight + Win10.ribbonPanelHeight
        } else if isOpenTemporarily, let host = overlayHost {
            // Поверх списка, последним подвидом — чтобы перекрывать всё под лентой.
            host.addSubview(panel)
            panel.showsShadow = true
            panelConstraints = [
                panel.topAnchor.constraint(equalTo: strip.bottomAnchor),
                panel.leadingAnchor.constraint(equalTo: host.leadingAnchor),
                panel.trailingAnchor.constraint(equalTo: host.trailingAnchor),
                panel.heightAnchor.constraint(equalToConstant: Win10.ribbonPanelHeight),
            ]
            height.constant = Win10.tabStripHeight
            startMonitor()
        } else {
            panelConstraints = []
            height.constant = Win10.tabStripHeight
        }
        NSLayoutConstraint.activate(panelConstraints)
        refresh()
    }

    private func rebuildPanel() {
        strip.titles = tabs.map(\.title)
        guard selected < tabs.count else { return }
        panel.show(tabs[selected])
        strip.selected = isPanelVisible ? selected : nil
        refresh()
    }

    /// Пока лента открыта поверх списка: щелчок мимо неё или Esc — закрыть.
    private func startMonitor() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            guard let self, self.isOpenTemporarily else { return event }
            if event.type == .keyDown {
                if event.keyCode == 53 { self.closeTemporary(); return nil }
                return event
            }
            guard event.window === self.window else { self.closeTemporary(); return event }
            let inPanel = self.panel.bounds.contains(self.panel.convert(event.locationInWindow, from: nil))
            let inStrip = self.strip.bounds.contains(self.strip.convert(event.locationInWindow, from: nil))
            if !inPanel && !inStrip { self.closeTemporary() }
            return event
        }
    }

    private func stopMonitor() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    // MARK: Команды

    private func run(_ command: RibbonCommand, from view: NSView) {
        if let menu = command.menu?() {
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: view.bounds.maxY + 2), in: view)
            closeTemporary()
            refresh()
            return
        }
        // Сначала закрываем ленту: команда может открыть окно или лист, и лента не должна висеть над ним.
        closeTemporary()
        perform?(command, view)
        refresh()
    }

    private func showFileMenu(from view: NSView) {
        closeTemporary()
        guard let menu = fileMenu?() else { return }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: view.bounds.maxY), in: view)
    }
}

// MARK: - Полоса вкладок

/// «Файл» (синяя), вкладки команд, справа — шеврон свернуть/развернуть и справка.
final class RibbonTabStrip: LunaView {
    var titles: [String] = [] { didSet { needsLayout = true; needsDisplay = true } }
    var selected: Int? { didSet { needsDisplay = true } }
    var isPinned = false {
        didSet {
            pin.toolTip = isPinned ? tr(.minimizeRibbon) : tr(.expandRibbon)
            pin.image = Self.chevron(up: isPinned)
        }
    }
    var onFile: ((NSView) -> Void)?
    var onTab: ((Int, Int) -> Void)?
    var onTogglePin: (() -> Void)?
    var onHelp: (() -> Void)?

    private let file = FileTabButton()
    private var tabRects: [NSRect] = []
    private var hovered: Int? { didSet { if oldValue != hovered { needsDisplay = true } } }
    private let pin = LunaButton(title: tr(.expandRibbon), symbol: nil, style: .iconOnly, imageSide: 12)
    private let help = LunaButton(title: tr(.menuHelp), symbol: nil, style: .iconOnly, imageSide: 14)

    override init(frame: NSRect) {
        super.init(frame: frame)
        file.title = tr(.menuFile)
        file.onClick = { [weak self] in
            guard let self else { return }
            self.onFile?(self.file)
        }
        pin.image = Self.chevron(up: false)
        pin.onClick = { [weak self] _ in self?.onTogglePin?() }
        help.image = XPIcons.image(.help, size: 14)
        help.onClick = { [weak self] _ in self?.onHelp?() }
        for v in [file, pin, help] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
        }
        NSLayoutConstraint.activate([
            file.leadingAnchor.constraint(equalTo: leadingAnchor),
            file.topAnchor.constraint(equalTo: topAnchor),
            file.bottomAnchor.constraint(equalTo: bottomAnchor),
            help.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            help.centerYAnchor.constraint(equalTo: centerYAnchor),
            help.widthAnchor.constraint(equalToConstant: 22),
            help.heightAnchor.constraint(equalToConstant: 20),
            pin.trailingAnchor.constraint(equalTo: help.leadingAnchor, constant: -2),
            pin.centerYAnchor.constraint(equalTo: centerYAnchor),
            pin.widthAnchor.constraint(equalToConstant: 22),
            pin.heightAnchor.constraint(equalToConstant: 20),
        ])
        addTrackingArea(NSTrackingArea(
            rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        var x = file.fittingSize.width + 2
        tabRects = titles.map { title in
            let w = (title as NSString).size(withAttributes: [.font: Win10.font]).width + 22
            defer { x += w + 1 }
            return NSRect(x: x, y: 2, width: w, height: bounds.height - 2)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill()
        bounds.fill()
        // Нижняя граница прерывается под открытой вкладкой — вкладка «перетекает» в панель.
        Win10.ribbonBorder.setFill()
        NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1).fill()
        for (i, title) in titles.enumerated() where i < tabRects.count {
            let r = tabRects[i]
            if selected == i {
                Win10.ribbonBackground.setFill()
                r.fill()
                Win10.ribbonBorder.setFill()
                NSRect(x: r.minX, y: r.minY, width: 1, height: r.height).fill()
                NSRect(x: r.maxX - 1, y: r.minY, width: 1, height: r.height).fill()
                NSRect(x: r.minX, y: r.minY, width: r.width, height: 1).fill()
            } else if hovered == i {
                Win10.hover.setFill()
                r.insetBy(dx: 0, dy: 0).fill()
            }
            let attrs: [NSAttributedString.Key: Any] = [.font: Win10.font, .foregroundColor: Win10.text]
            let size = (title as NSString).size(withAttributes: attrs)
            (title as NSString).draw(at: NSPoint(x: r.midX - size.width / 2, y: r.midY - size.height / 2), withAttributes: attrs)
        }
    }

    override func mouseMoved(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        hovered = tabRects.firstIndex { $0.contains(p) }
    }

    override func mouseExited(with event: NSEvent) { hovered = nil }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if let index = tabRects.firstIndex(where: { $0.contains(p) }) { onTab?(index, event.clickCount) }
    }

    private static func chevron(up: Bool) -> NSImage {
        NSImage(size: NSSize(width: 12, height: 12), flipped: true) { _ in
            let path = NSBezierPath()
            path.move(to: NSPoint(x: 2.5, y: up ? 8 : 4.5))
            path.line(to: NSPoint(x: 6, y: up ? 4.5 : 8))
            path.line(to: NSPoint(x: 9.5, y: up ? 8 : 4.5))
            path.lineWidth = 1.2
            Win10.glyph.setStroke()
            path.stroke()
            return true
        }
    }
}

/// Синяя вкладка «Файл».
final class FileTabButton: LunaView {
    var title = "" { didSet { invalidateIntrinsicContentSize(); needsDisplay = true } }
    var onClick: (() -> Void)?
    private var isHovered = false { didSet { needsDisplay = true } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
    }

    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize {
        NSSize(width: (title as NSString).size(withAttributes: [.font: Win10.font]).width + 28, height: Win10.tabStripHeight)
    }

    override func draw(_ dirtyRect: NSRect) {
        (isHovered ? Win10.fileTabHover : Win10.fileTab).setFill()
        bounds.fill()
        let attrs: [NSAttributedString.Key: Any] = [.font: Win10.font, .foregroundColor: NSColor.white]
        let size = (title as NSString).size(withAttributes: attrs)
        (title as NSString).draw(at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2), withAttributes: attrs)
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }
    override func mouseDown(with event: NSEvent) { onClick?() }
}

// MARK: - Панель с группами

final class RibbonPanel: LunaView {
    var onPerform: ((RibbonCommand, NSView) -> Void)?
    var showsShadow = false {
        didSet {
            wantsLayer = true
            layer?.shadowOpacity = showsShadow ? 0.25 : 0
            layer?.shadowRadius = 4
            layer?.shadowOffset = NSSize(width: 0, height: -2)
        }
    }

    private let stack = NSStackView()
    private var buttons: [RibbonButton] = []
    private var tab: RibbonTab?
    /// Сколько групп справа свёрнуто в одну кнопку с меню — как в узком окне Windows 10.
    private var collapsed = 0
    private var widths: (full: [CGFloat], collapsed: [CGFloat]) = ([], [])
    private var validate: ((NSMenuItem) -> Bool)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        stack.orientation = .horizontal
        stack.alignment = .top
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -1),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        Win10.ribbonBackground.setFill()
        bounds.fill()
        Win10.ribbonBorder.setFill()
        NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1).fill()
    }

    func show(_ tab: RibbonTab) {
        self.tab = tab
        widths = (tab.groups.map { groupView($0).fittingSize.width },
                  tab.groups.map { groupView(collapsedGroup($0)).fittingSize.width })
        collapsed = 0
        rebuild()
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let available = bounds.width - 8
        guard available > 0 else { return }
        var count = 0
        while count < widths.full.count,
              widths.full.dropLast(count).reduce(0, +) + widths.collapsed.suffix(count).reduce(0, +) > available {
            count += 1
        }
        if count != collapsed {
            collapsed = count
            rebuild()
        }
    }

    private func rebuild() {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        buttons = []
        guard let tab else { return }
        let firstCollapsed = tab.groups.count - collapsed
        for (i, group) in tab.groups.enumerated() {
            stack.addArrangedSubview(groupView(i < firstCollapsed ? group : collapsedGroup(group)))
        }
        refresh(validate)
    }

    /// Свёрнутая группа: одна большая кнопка с названием группы, команды — в её меню.
    private func collapsedGroup(_ group: RibbonGroup) -> RibbonGroup {
        var commands: [RibbonCommand] = []
        for item in group.items {
            switch item {
            case .large(let c): commands.append(c)
            case .small(let cs), .checks(let cs), .gallery(let cs, _): commands += cs
            }
        }
        let menu: () -> NSMenu = { [weak self] in
            let menu = NSMenu()
            for command in commands {
                let entry: NSMenuItem
                if let custom = command.custom {
                    entry = ActionMenuItem(title: command.title) { [weak self] in
                        guard let self else { return }
                        custom(self)
                    }
                } else {
                    entry = NSMenuItem(title: command.title, action: command.action, keyEquivalent: "")
                    entry.tag = command.tag
                    if let submenu = command.menu?() { entry.submenu = submenu }
                }
                entry.image = command.icon.map { XPIcons.image($0, size: 16) }
                menu.addItem(entry)
            }
            return menu
        }
        let icon = commands.first { $0.icon != nil }?.icon
        return RibbonGroup(title: group.title, items: [.large(RibbonCommand(group.title, icon, nil, menu: menu))])
    }

    func refresh(_ validate: ((NSMenuItem) -> Bool)?) {
        self.validate = validate
        for button in buttons {
            guard let action = button.command.action else { continue }
            let item = NSMenuItem(title: button.command.title, action: action, keyEquivalent: "")
            item.tag = button.command.tag
            button.isEnabled = validate?(item) ?? true
            button.isOn = item.state == .on
        }
    }

    private func groupView(_ group: RibbonGroup) -> NSView {
        let content = NSStackView()
        content.orientation = .horizontal
        content.alignment = .top
        content.spacing = 2
        for item in group.items {
            switch item {
            case .large(let command):
                content.addArrangedSubview(button(command, .large))
            case .small(let commands), .checks(let commands):
                let kind: RibbonButton.Kind
                if case .checks = item { kind = .check } else { kind = .small }
                let column = NSStackView(views: commands.map { button($0, kind) })
                column.orientation = .vertical
                column.alignment = .leading
                column.spacing = 0
                content.addArrangedSubview(column)
            case .gallery(let commands, let columns):
                content.addArrangedSubview(gallery(commands, columns: columns))
            }
        }

        let label = NSTextField(labelWithString: group.title)
        label.font = Win10.smallFont
        label.textColor = Win10.groupLabel
        label.alignment = .center

        let box = RibbonGroupView()
        for v in [content, label] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            box.addSubview(v)
        }
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: box.topAnchor),
            content.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 4),
            content.trailingAnchor.constraint(lessThanOrEqualTo: box.trailingAnchor, constant: -6),
            content.heightAnchor.constraint(equalToConstant: 68),
            label.topAnchor.constraint(equalTo: content.bottomAnchor, constant: 2),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: box.leadingAnchor, constant: 4),
            label.trailingAnchor.constraint(lessThanOrEqualTo: box.trailingAnchor, constant: -6),
            label.centerXAnchor.constraint(equalTo: box.centerXAnchor, constant: -1),
            box.heightAnchor.constraint(equalToConstant: Win10.ribbonPanelHeight - 4),
        ])
        return box
    }

    private func gallery(_ commands: [RibbonCommand], columns: Int) -> NSView {
        let frame = RibbonGalleryView()
        let grid = NSStackView()
        grid.orientation = .horizontal
        grid.alignment = .top
        grid.spacing = 2
        let rows = Int((Double(commands.count) / Double(columns)).rounded(.up))
        for c in 0..<columns {
            let column = NSStackView(views: commands.dropFirst(c * rows).prefix(rows).map { button($0, .galleryItem) })
            column.orientation = .vertical
            column.alignment = .leading
            column.spacing = 0
            grid.addArrangedSubview(column)
        }
        grid.translatesAutoresizingMaskIntoConstraints = false
        frame.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: frame.topAnchor, constant: 1),
            grid.leadingAnchor.constraint(equalTo: frame.leadingAnchor, constant: 1),
            grid.trailingAnchor.constraint(equalTo: frame.trailingAnchor, constant: -1),
            frame.heightAnchor.constraint(equalToConstant: 66),
        ])
        return frame
    }

    private func button(_ command: RibbonCommand, _ kind: RibbonButton.Kind) -> RibbonButton {
        let button = RibbonButton(command, kind: kind)
        button.onClick = { [weak self] button in self?.onPerform?(button.command, button) }
        buttons.append(button)
        return button
    }
}

/// Группа ленты с разделителем справа.
final class RibbonGroupView: LunaView {
    override func draw(_ dirtyRect: NSRect) {
        Win10.groupSeparator.setFill()
        NSRect(x: bounds.width - 1, y: 2, width: 1, height: bounds.height - 4).fill()
    }
}

/// Белая рамка галереи «Структура».
final class RibbonGalleryView: LunaView {
    override func draw(_ dirtyRect: NSRect) {
        NSBezierPath.win10Box(bounds, fill: .white, border: Win10.ribbonBorder)
    }
}

// MARK: - Кнопка ленты

final class RibbonButton: LunaView {
    enum Kind { case large, small, check, galleryItem }

    let command: RibbonCommand
    let kind: Kind
    var onClick: ((RibbonButton) -> Void)?
    var isEnabled = true { didSet { if oldValue != isEnabled { needsDisplay = true } } }
    var isOn = false { didSet { if oldValue != isOn { needsDisplay = true } } }
    private var isHovered = false { didSet { needsDisplay = true } }
    private var isPressed = false { didSet { needsDisplay = true } }
    private let lines: [String]

    init(_ command: RibbonCommand, kind: Kind) {
        self.command = command
        self.kind = kind
        self.lines = kind == .large ? Self.split(command.title) : [command.title]
        super.init(frame: .zero)
        toolTip = command.title
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
        setContentHuggingPriority(.required, for: .horizontal)
    }

    required init?(coder: NSCoder) { fatalError() }

    private var hasMenu: Bool { command.menu != nil }
    private static let arrowWidth: CGFloat = 9

    private func textWidth(_ text: String) -> CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: Win10.font]).width)
    }

    override var intrinsicContentSize: NSSize {
        switch kind {
        case .large:
            let widest = lines.enumerated().map { i, line in
                textWidth(line) + (hasMenu && i == lines.count - 1 ? Self.arrowWidth : 0)
            }.max() ?? 0
            return NSSize(width: max(42, widest + 10), height: 68)
        case .small, .galleryItem:
            return NSSize(width: 16 + 6 + textWidth(command.title) + 8 + (hasMenu ? Self.arrowWidth : 0), height: 22)
        case .check:
            return NSSize(width: 13 + 6 + textWidth(command.title) + 8, height: 22)
        }
    }

    /// Подпись большой кнопки — в две строки, разбитые по пробелу ближе к середине.
    private static func split(_ title: String) -> [String] {
        let words = title.split(separator: " ").map(String.init)
        guard words.count > 1 else { return [title] }
        let width = { (s: String) in (s as NSString).size(withAttributes: [.font: Win10.font]).width }
        if width(title) <= 48 { return [title] }
        var best = [title], bestWidth = CGFloat.greatestFiniteMagnitude
        for i in 1..<words.count {
            let a = words[..<i].joined(separator: " "), b = words[i...].joined(separator: " ")
            let w = max(width(a), width(b))
            if w < bestWidth { best = [a, b]; bestWidth = w }
        }
        return best
    }

    override func draw(_ dirtyRect: NSRect) {
        let active = isEnabled && (isHovered || isPressed)
        let checkedLook = isOn && kind == .galleryItem
        if isEnabled && (isPressed || checkedLook) {
            NSBezierPath.win10Box(bounds, fill: Win10.selection, border: Win10.selectionBorder)
        } else if active && kind != .check {
            NSBezierPath.win10Box(bounds, fill: Win10.hover, border: Win10.hoverBorder)
        }
        let color = isEnabled ? Win10.text : Win10.disabledText
        let attrs: [NSAttributedString.Key: Any] = [.font: Win10.font, .foregroundColor: color]
        let fraction: CGFloat = isEnabled ? 1 : 0.35

        switch kind {
        case .large:
            if let icon = command.icon {
                XPIcons.image(icon, size: 32).draw(in: NSRect(x: bounds.midX - 16, y: 4, width: 32, height: 32),
                                                   from: .zero, operation: .sourceOver, fraction: fraction,
                                                   respectFlipped: true, hints: nil)
            }
            var y: CGFloat = 38
            for (i, line) in lines.enumerated() {
                let last = i == lines.count - 1
                let w = textWidth(line) + (hasMenu && last ? Self.arrowWidth : 0)
                let x = bounds.midX - w / 2
                (line as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: attrs)
                if hasMenu && last { drawArrow(at: NSPoint(x: x + w - 6, y: y + 8), color: color) }
                y += 14
            }
        case .small, .galleryItem:
            if let icon = command.icon {
                XPIcons.image(icon, size: 16).draw(in: NSRect(x: 4, y: 3, width: 16, height: 16),
                                                   from: .zero, operation: .sourceOver, fraction: fraction,
                                                   respectFlipped: true, hints: nil)
            }
            let h = (command.title as NSString).size(withAttributes: attrs).height
            (command.title as NSString).draw(at: NSPoint(x: 22, y: (bounds.height - h) / 2), withAttributes: attrs)
            if hasMenu { drawArrow(at: NSPoint(x: bounds.width - 9, y: bounds.midY), color: color) }
        case .check:
            let box = NSRect(x: 4, y: (bounds.height - 13) / 2, width: 13, height: 13)
            NSBezierPath.win10Box(box, fill: active ? Win10.hover : .white,
                                  border: active ? Win10.accent : NSColor(hex: 0x333333))
            if isOn {
                let mark = NSBezierPath()
                mark.move(to: NSPoint(x: box.minX + 3, y: box.midY))
                mark.line(to: NSPoint(x: box.minX + 5.5, y: box.maxY - 3.5))
                mark.line(to: NSPoint(x: box.maxX - 3, y: box.minY + 3.5))
                mark.lineWidth = 1.5
                color.setStroke()
                mark.stroke()
            }
            let h = (command.title as NSString).size(withAttributes: attrs).height
            (command.title as NSString).draw(at: NSPoint(x: box.maxX + 6, y: (bounds.height - h) / 2), withAttributes: attrs)
        }
    }

    private func drawArrow(at point: NSPoint, color: NSColor) {
        let arrow = NSBezierPath()
        arrow.move(to: NSPoint(x: point.x - 3, y: point.y - 1.5))
        arrow.line(to: NSPoint(x: point.x + 3, y: point.y - 1.5))
        arrow.line(to: NSPoint(x: point.x, y: point.y + 1.5))
        arrow.close()
        color.setFill()
        arrow.fill()
    }

    override func mouseEntered(with event: NSEvent) { if isEnabled { isHovered = true } }
    override func mouseExited(with event: NSEvent) { isHovered = false; isPressed = false }
    override func mouseDown(with event: NSEvent) { if isEnabled { isPressed = true } }

    override func mouseUp(with event: NSEvent) {
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        isPressed = false
        if inside && isEnabled { onClick?(self) }
    }
}
