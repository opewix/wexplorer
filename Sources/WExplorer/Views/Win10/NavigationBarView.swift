import AppKit

/// Строка навигации Проводника Windows 10: ← → ⌄ ↑, адрес «хлебными крошками», поиск.
final class NavigationBarView: LunaView {
    let back = LunaButton(title: tr(.back), symbol: nil, style: .iconOnly, imageSide: 16)
    let forward = LunaButton(title: tr(.forward), symbol: nil, style: .iconOnly, imageSide: 16)
    let recent = LunaButton(title: tr(.recentLocations), symbol: nil, style: .iconOnly, imageSide: 8)
    let up = LunaButton(title: tr(.upOneLevel), symbol: nil, style: .iconOnly, imageSide: 16)
    let address = BreadcrumbBar()
    let search = SearchBox()

    override init(frame: NSRect) {
        super.init(frame: frame)
        back.image = Self.arrow(angle: 180)
        forward.image = Self.arrow(angle: 0)
        up.image = Self.arrow(angle: -90)
        recent.image = Self.chevronDown()
        for v in [back, forward, recent, up, address, search] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
        }
        NSLayoutConstraint.activate([
            back.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            forward.leadingAnchor.constraint(equalTo: back.trailingAnchor, constant: 2),
            recent.leadingAnchor.constraint(equalTo: forward.trailingAnchor),
            up.leadingAnchor.constraint(equalTo: recent.trailingAnchor, constant: 2),
            address.leadingAnchor.constraint(equalTo: up.trailingAnchor, constant: 6),
            search.leadingAnchor.constraint(equalTo: address.trailingAnchor, constant: 6),
            search.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            search.widthAnchor.constraint(equalTo: widthAnchor, multiplier: 0.24),
            search.widthAnchor.constraint(greaterThanOrEqualToConstant: 140),
            address.heightAnchor.constraint(equalToConstant: 24),
            search.heightAnchor.constraint(equalToConstant: 24),
            recent.widthAnchor.constraint(equalToConstant: 14),
        ])
        for v in [back, forward, up] as [NSView] {
            v.widthAnchor.constraint(equalToConstant: 26).isActive = true
            v.heightAnchor.constraint(equalToConstant: 24).isActive = true
        }
        recent.heightAnchor.constraint(equalToConstant: 24).isActive = true
        for v in [back, forward, recent, up, address, search] as [NSView] {
            v.centerYAnchor.constraint(equalTo: centerYAnchor).isActive = true
        }
        address.setContentHuggingPriority(.init(1), for: .horizontal)
        address.setContentCompressionResistancePriority(.init(1), for: .horizontal)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill()
        bounds.fill()
    }

    func update(_ location: Location, canGoBack: Bool, canGoForward: Bool, canGoUp: Bool) {
        back.isEnabled = canGoBack
        forward.isEnabled = canGoForward
        up.isEnabled = canGoUp
        address.show(location)
        search.show(location)
    }

    /// Тонкая стрелка, как кнопки навигации Windows 10. angle: 0 — вправо, 180 — влево, -90 — вверх.
    private static func arrow(angle: CGFloat) -> NSImage {
        NSImage(size: NSSize(width: 16, height: 16), flipped: true) { _ in
            let transform = NSAffineTransform()
            transform.translateX(by: 8, yBy: 8)
            transform.rotate(byDegrees: angle)
            transform.translateX(by: -8, yBy: -8)
            transform.concat()
            let path = NSBezierPath()
            path.move(to: NSPoint(x: 2.5, y: 8)); path.line(to: NSPoint(x: 13.5, y: 8))
            path.move(to: NSPoint(x: 8.5, y: 3)); path.line(to: NSPoint(x: 13.5, y: 8)); path.line(to: NSPoint(x: 8.5, y: 13))
            path.lineWidth = 1.3
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            NSColor(hex: 0x333333).setStroke()
            path.stroke()
            return true
        }
    }

    static func chevronDown() -> NSImage {
        NSImage(size: NSSize(width: 8, height: 8), flipped: true) { _ in
            let path = NSBezierPath()
            path.move(to: NSPoint(x: 1, y: 2.5)); path.line(to: NSPoint(x: 4, y: 5.5)); path.line(to: NSPoint(x: 7, y: 2.5))
            path.lineWidth = 1
            Win10.glyph.setStroke()
            path.stroke()
            return true
        }
    }
}

// MARK: - Адрес «хлебными крошками»

/// Звено адреса: «Этот компьютер › Macintosh HD › Users». Щелчок по звену — переход,
/// по «›» — меню вложенных папок, по пустому месту — ввод пути с автодополнением.
final class BreadcrumbBar: LunaView, NSTextFieldDelegate {
    struct Crumb {
        let title: String
        let location: Location
    }

    var onNavigate: ((Location) -> Void)?
    var onSubmit: ((String) -> Void)?
    var onCancel: (() -> Void)?
    var onRefresh: (() -> Void)?
    var menuProvider: (() -> NSMenu)?
    var showHidden = false

    private let iconView = NSImageView()
    private let field = NSTextField()
    private let dropdown = LunaButton(title: tr(.placesList), symbol: nil, style: .iconOnly, imageSide: 8)
    private let refresh = LunaButton(title: tr(.refresh), symbol: nil, style: .iconOnly, imageSide: 14)
    private var crumbs: [Crumb] = []
    private var crumbViews: [CrumbButton] = []
    private var location: Location = .computer
    private var isEditing = false { didSet { needsDisplay = true; needsLayout = true } }
    private var isHovered = false { didSet { needsDisplay = true } }
    private var typedLength = 0
    private static let rightButtonsWidth: CGFloat = 44

    override init(frame: NSRect) {
        super.init(frame: frame)
        iconView.imageScaling = .scaleProportionallyDown
        field.font = Win10.font
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.delegate = self
        field.cell?.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.isHidden = true
        dropdown.image = NavigationBarView.chevronDown()
        dropdown.onClick = { [weak self] _ in self?.showPlacesMenu() }
        refresh.image = XPIcons.image(.refresh, size: 14)
        refresh.onClick = { [weak self] _ in self?.onRefresh?() }
        for v in [iconView, field, dropdown, refresh] as [NSView] { addSubview(v) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        let border = isEditing ? Win10.accent : (isHovered ? Win10.fieldHoverBorder : Win10.fieldBorder)
        NSBezierPath.win10Box(bounds, fill: .white, border: border)
        Win10.fieldBorder.setFill()
        NSRect(x: bounds.width - 24, y: 1, width: 1, height: bounds.height - 2).fill()
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }

    /// Щелчок мимо звеньев — ввод пути, как в Windows 10.
    override func mouseDown(with event: NSEvent) {
        beginEditing()
    }

    func show(_ location: Location) {
        self.location = location
        iconView.image = location.icon
        crumbs = Self.crumbs(for: location)
        crumbViews.forEach { $0.removeFromSuperview() }
        crumbViews = []
        // Перед каждым звеном — «›» с меню вложенных папок предыдущего звена (у первого — корневые места).
        for (i, crumb) in crumbs.enumerated() {
            let chevron = CrumbButton(kind: .chevron)
            let parent = i > 0 ? crumbs[i - 1].location : nil
            let current = crumb.location
            chevron.onClick = { [weak self] view in self?.showChildren(of: parent, current: current, from: view) }
            let text = CrumbButton(kind: .text(crumb.title))
            text.onClick = { [weak self] _ in self?.onNavigate?(current) }
            for v in [chevron, text] {
                addSubview(v)
                crumbViews.append(v)
            }
        }
        if isEditing { endEditing() }
        needsLayout = true
    }

    func focus() {
        beginEditing()
    }

    override func layout() {
        super.layout()
        let h = bounds.height
        iconView.frame = NSRect(x: 5, y: (h - 16) / 2, width: 16, height: 16)
        refresh.frame = NSRect(x: bounds.width - 23, y: 1, width: 22, height: h - 2)
        dropdown.frame = NSRect(x: bounds.width - 40, y: 1, width: 15, height: h - 2)
        let left: CGFloat = 23, right = bounds.width - Self.rightButtonsWidth
        field.frame = NSRect(x: left + 2, y: (h - 17) / 2, width: max(0, right - left - 4), height: 17)

        // Не помещается — прячем звенья с начала: в Windows 10 так же, видна только хвостовая часть пути.
        let sizes = crumbViews.map { $0.intrinsicContentSize.width }
        var first = 0
        while first < sizes.count - 2, sizes[first...].reduce(0, +) > right - left { first += 2 }
        var x = left
        for (i, view) in crumbViews.enumerated() {
            view.isHidden = isEditing || i < first
            guard !view.isHidden else { continue }
            view.frame = NSRect(x: x, y: 1, width: sizes[i], height: h - 2)
            x += sizes[i]
        }
    }

    // MARK: Меню

    private func showPlacesMenu() {
        guard let menu = menuProvider?() else { return }
        menu.minimumWidth = bounds.width
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: bounds.maxY + 2), in: self)
    }

    /// Меню «›»: вложенные папки звена; то, что идёт следом в адресе, выделено жирным.
    private func showChildren(of parent: Location?, current: Location, from view: NSView) {
        let menu = NSMenu()
        for place in Self.children(of: parent, showHidden: showHidden) {
            let item = ActionMenuItem(title: place.title) { [weak self] in self?.onNavigate?(place) }
            item.image = place.icon
            if place == current {
                item.attributedTitle = NSAttributedString(string: place.title, attributes: [.font: NSFont.boldSystemFont(ofSize: 13)])
            }
            menu.addItem(item)
        }
        guard menu.numberOfItems > 0 else { return }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: view.bounds.maxY + 2), in: view)
    }

    private static func children(of parent: Location?, showHidden: Bool) -> [Location] {
        guard let parent else {
            let quick = Favorites.all + [Places.desktop, Places.downloads, Places.documents, Places.pictures]
            var seen = Set<String>()
            return quick.filter { seen.insert($0.standardizedFileURL.path).inserted }.map { .folder($0) } + [.computer]
        }
        switch parent {
        case .computer:
            return computerFolders.map { .folder($0) } + DirectoryLoader.volumes().map { .folder($0) }
        case .folder(let url):
            return DirectoryLoader.subfolders(of: url, showHidden: showHidden).map { .folder($0) }
        case .search:
            return []
        }
    }

    // MARK: Звенья адреса

    /// Папки под «Этим компьютером» — те же, что в области навигации.
    private static var computerFolders: [URL] {
        [Places.home, Places.desktop, Places.documents, Places.downloads, Places.music, Places.pictures, Places.movies]
    }

    static func crumbs(for location: Location) -> [Crumb] {
        let computer = Crumb(title: Places.computerTitle, location: .computer)
        switch location {
        case .computer:
            return [computer]
        case .search:
            return [Crumb(title: location.title, location: location)]
        case .folder(let url):
            let path = url.standardizedFileURL.path
            func contains(_ base: String) -> Bool { path == base || path.hasPrefix(base == "/" ? "/" : base + "/") }
            // Особая папка (самая глубокая из подходящих) или диск, на котором лежит папка.
            let special = computerFolders.map(\.standardizedFileURL).filter { contains($0.path) }
                .max { $0.path.count < $1.path.count }
            let volume = (try? url.resourceValues(forKeys: [.volumeURLKey]))?.volume ?? URL(fileURLWithPath: "/")
            let base = special ?? volume.standardizedFileURL
            var result = [computer, Crumb(title: Places.displayName(of: base), location: .folder(base))]
            var current = base
            let rest = path.dropFirst(base.path == "/" ? 1 : base.path.count + 1)
            for component in rest.split(separator: "/") {
                current = current.appendingPathComponent(String(component))
                result.append(Crumb(title: String(component), location: .folder(current)))
            }
            return result
        }
    }

    // MARK: Ввод пути

    private func beginEditing() {
        guard !isEditing else { return }
        isEditing = true
        field.isHidden = false
        field.stringValue = location.addressText
        window?.makeFirstResponder(field)
        field.currentEditor()?.selectAll(nil)
        typedLength = (field.stringValue as NSString).length
    }

    private func endEditing() {
        guard isEditing else { return }
        isEditing = false
        field.isHidden = true
    }

    func controlTextDidChange(_ obj: Notification) {
        typedLength = AddressBarView.autocomplete(field, typedLength: typedLength)
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        endEditing()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.insertNewline(_:)) {
            let text = field.stringValue
            endEditing()
            onSubmit?(text)
            return true
        }
        if selector == #selector(NSResponder.cancelOperation(_:)) {
            endEditing()
            onCancel?()
            return true
        }
        return false
    }
}

/// Звено или «›» адресной строки с подсветкой при наведении.
final class CrumbButton: LunaView {
    enum Kind { case text(String), chevron }

    let kind: Kind
    var onClick: ((CrumbButton) -> Void)?
    private var isHovered = false { didSet { needsDisplay = true } }

    init(kind: Kind) {
        self.kind = kind
        super.init(frame: .zero)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
    }

    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize {
        switch kind {
        case .chevron: return NSSize(width: 17, height: 22)
        case .text(let title):
            return NSSize(width: ceil((title as NSString).size(withAttributes: [.font: Win10.font]).width) + 8, height: 22)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        if isHovered { NSBezierPath.win10Box(bounds, fill: Win10.hover, border: Win10.hoverBorder) }
        switch kind {
        case .chevron:
            let path = NSBezierPath()
            let x = bounds.midX, y = bounds.midY
            path.move(to: NSPoint(x: x - 1.5, y: y - 3.5)); path.line(to: NSPoint(x: x + 2, y: y)); path.line(to: NSPoint(x: x - 1.5, y: y + 3.5))
            path.lineWidth = 1
            Win10.glyph.setStroke()
            path.stroke()
        case .text(let title):
            let attrs: [NSAttributedString.Key: Any] = [.font: Win10.font, .foregroundColor: Win10.text]
            let size = (title as NSString).size(withAttributes: attrs)
            (title as NSString).draw(at: NSPoint(x: 4, y: (bounds.height - size.height) / 2), withAttributes: attrs)
        }
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }
    override func mouseDown(with event: NSEvent) { onClick?(self) }
}

/// Пункт меню с замыканием вместо селектора.
final class ActionMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError() }

    @objc private func run() { handler() }
}

// MARK: - Поиск

/// Поле «Поиск: Документы» справа. Ищет по мере набора (с небольшой паузой) и по Enter.
final class SearchBox: LunaView, NSTextFieldDelegate {
    var onSearch: ((String) -> Void)?
    /// Поле очищено — вернуться из результатов поиска.
    var onClear: (() -> Void)?

    private let field = NSTextField()
    private let icon = LunaButton(title: tr(.search), symbol: nil, style: .iconOnly, imageSide: 14)
    private var timer: Timer?
    private var isFocused = false { didSet { needsDisplay = true } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        field.font = Win10.font
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.delegate = self
        field.cell?.usesSingleLineMode = true
        field.cell?.isScrollable = true
        icon.image = XPIcons.image(.search, size: 14)
        icon.onClick = { [weak self] _ in self?.iconClicked() }
        for v in [field, icon] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
        }
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            field.trailingAnchor.constraint(equalTo: icon.leadingAnchor, constant: -2),
            field.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -1),
            icon.topAnchor.constraint(equalTo: topAnchor, constant: 1),
            icon.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -1),
            icon.widthAnchor.constraint(equalToConstant: 24),
        ])
        field.setContentHuggingPriority(.init(1), for: .horizontal)
        field.setContentCompressionResistancePriority(.init(1), for: .horizontal)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        NSBezierPath.win10Box(bounds, fill: .white, border: isFocused ? Win10.accent : Win10.fieldBorder)
    }

    func show(_ location: Location) {
        if case .search(let query, let scope) = location {
            if field.stringValue != query { field.stringValue = query }
            field.placeholderString = tr(.searchPlaceholder, Places.displayName(of: scope))
        } else {
            timer?.invalidate()
            field.stringValue = ""
            field.placeholderString = tr(.searchPlaceholder, location.title)
        }
        updateIcon()
    }

    func focus() {
        window?.makeFirstResponder(field)
        field.currentEditor()?.selectAll(nil)
    }

    private func updateIcon() {
        let empty = field.stringValue.isEmpty
        icon.image = empty ? XPIcons.image(.search, size: 14) : Self.cross()
        icon.toolTip = empty ? tr(.search) : tr(.close)
    }

    private func iconClicked() {
        if field.stringValue.isEmpty {
            focus()
        } else {
            field.stringValue = ""
            updateIcon()
            onClear?()
        }
    }

    private func submit() {
        timer?.invalidate()
        let text = field.stringValue.trimmingCharacters(in: .whitespaces)
        text.isEmpty ? onClear?() : onSearch?(text)
    }

    func controlTextDidBeginEditing(_ obj: Notification) { isFocused = true }
    func controlTextDidEndEditing(_ obj: Notification) { isFocused = false }

    func controlTextDidChange(_ obj: Notification) {
        updateIcon()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: false) { [weak self] _ in self?.submit() }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.insertNewline(_:)) {
            submit()
            return true
        }
        if selector == #selector(NSResponder.cancelOperation(_:)) {
            field.stringValue = ""
            updateIcon()
            timer?.invalidate()
            onClear?()
            return true
        }
        return false
    }

    private static func cross() -> NSImage {
        NSImage(size: NSSize(width: 14, height: 14), flipped: true) { _ in
            let path = NSBezierPath()
            path.move(to: NSPoint(x: 3.5, y: 3.5)); path.line(to: NSPoint(x: 10.5, y: 10.5))
            path.move(to: NSPoint(x: 10.5, y: 3.5)); path.line(to: NSPoint(x: 3.5, y: 10.5))
            path.lineWidth = 1.2
            Win10.glyph.setStroke()
            path.stroke()
            return true
        }
    }
}
