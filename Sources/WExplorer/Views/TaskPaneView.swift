import AppKit

struct TaskGroup {
    var title: String
    var entries: [TaskEntry]
    /// Тёмно-синий заголовок, как у первой группы на некоторых экранах XP.
    var isSpecial = false
}

enum TaskEntry {
    case link(String, NSImage?, () -> Void)
    case heading(String)
    case text(String)
}

/// Панель задач XP: голубой градиент со сворачиваемыми группами.
final class TaskPaneView: GradientView {
    private let scroll = NSScrollView()
    private let stack = NSStackView()
    private var collapsed = Set<String>()

    init() {
        super.init(start: Luna.paneTop, end: Luna.paneBottom)

        let document = LunaView()
        document.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(stack)

        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = document
        scroll.contentView.drawsBackground = false
        addSubview(scroll)

        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: topAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            document.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            document.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            stack.topAnchor.constraint(equalTo: document.topAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -12),
            stack.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -12),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func update(_ groups: [TaskGroup]) {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for group in groups {
            let view = TaskGroupView(group: group, collapsed: collapsed.contains(group.title))
            view.onToggle = { [weak self] isCollapsed in
                if isCollapsed { self?.collapsed.insert(group.title) } else { self?.collapsed.remove(group.title) }
            }
            stack.addArrangedSubview(view)
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
    }
}

/// Группа: градиентный заголовок с кнопкой-шевроном и светлое тело со ссылками.
final class TaskGroupView: LunaView {
    var onToggle: ((Bool) -> Void)?

    private let header: TaskGroupHeader
    private let body = TaskGroupBody()

    init(group: TaskGroup, collapsed: Bool) {
        header = TaskGroupHeader(title: group.title, special: group.isSpecial)
        super.init(frame: .zero)

        let content = NSStackView()
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 5
        content.edgeInsets = NSEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        content.translatesAutoresizingMaskIntoConstraints = false
        body.addSubview(content)
        for entry in group.entries {
            let view = Self.makeView(for: entry)
            content.addArrangedSubview(view)
            view.widthAnchor.constraint(equalTo: content.widthAnchor, constant: -20).isActive = true
        }

        let outer = NSStackView(views: [header, body])
        outer.orientation = .vertical
        outer.spacing = 0
        outer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(outer)

        NSLayoutConstraint.activate([
            outer.topAnchor.constraint(equalTo: topAnchor),
            outer.bottomAnchor.constraint(equalTo: bottomAnchor),
            outer.leadingAnchor.constraint(equalTo: leadingAnchor),
            outer.trailingAnchor.constraint(equalTo: trailingAnchor),
            header.widthAnchor.constraint(equalTo: outer.widthAnchor),
            body.widthAnchor.constraint(equalTo: outer.widthAnchor),
            content.topAnchor.constraint(equalTo: body.topAnchor),
            content.bottomAnchor.constraint(equalTo: body.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: body.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: body.trailingAnchor),
        ])

        header.isCollapsed = collapsed
        body.isHidden = collapsed
        header.onClick = { [weak self] in
            guard let self else { return }
            self.body.isHidden.toggle()
            self.header.isCollapsed = self.body.isHidden
            self.onToggle?(self.body.isHidden)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    private static func makeView(for entry: TaskEntry) -> NSView {
        switch entry {
        case let .link(title, icon, action):
            return LinkButton(title: title, icon: icon, action: action)
        case let .heading(text):
            return label(text, font: Luna.fontBold)
        case let .text(text):
            return label(text, font: Luna.font)
        }
    }

    private static func label(_ text: String, font: NSFont) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = font
        label.textColor = Luna.text
        label.lineBreakMode = .byTruncatingTail
        label.toolTip = text
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.setContentHuggingPriority(.init(1), for: .horizontal)
        return label
    }
}

final class TaskGroupHeader: LunaView {
    var onClick: (() -> Void)?
    var isCollapsed = false { didSet { needsDisplay = true } }

    private let title: String
    private let special: Bool
    private var hovered = false { didSet { needsDisplay = true } }

    init(title: String, special: Bool) {
        self.title = title
        self.special = special
        super.init(frame: .zero)
        addTrackingArea(NSTrackingArea(
            rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
    }

    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: 25) }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
    override func mouseEntered(with event: NSEvent) { hovered = true }
    override func mouseExited(with event: NSEvent) { hovered = false }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onClick?() }
    }

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds
        NSGraphicsContext.saveGraphicsState()
        Self.topRounded(r, radius: 5).addClip()
        let colors = special
            ? (Luna.groupSpecialLeft, Luna.groupSpecialRight)
            : (Luna.groupHeaderLeft, Luna.groupHeaderRight)
        NSGradient(starting: colors.0, ending: colors.1)?.draw(in: r, angle: 0)
        NSGraphicsContext.restoreGraphicsState()

        let color: NSColor = special ? .white : (hovered ? Luna.linkHover : Luna.linkBlue)
        let attrs: [NSAttributedString.Key: Any] = [.font: Luna.fontBold, .foregroundColor: color]
        let size = (title as NSString).size(withAttributes: attrs)
        (title as NSString).draw(at: NSPoint(x: 12, y: r.midY - size.height / 2), withAttributes: attrs)

        // Круглая кнопка с двойным шевроном.
        let circle = NSRect(x: r.maxX - 24, y: r.midY - 8.5, width: 17, height: 17)
        let path = NSBezierPath(ovalIn: circle)
        NSColor.white.setFill()
        path.fill()
        Luna.chevronBorder.setStroke()
        path.stroke()
        let cx = circle.midX, cy = circle.midY
        let chevron = NSBezierPath()
        chevron.lineWidth = 1.5
        for dy in [-2.5, 1.5] as [CGFloat] {
            let y = cy + dy
            if isCollapsed {
                chevron.move(to: NSPoint(x: cx - 3.5, y: y - 1.5))
                chevron.line(to: NSPoint(x: cx, y: y + 1.5))
                chevron.line(to: NSPoint(x: cx + 3.5, y: y - 1.5))
            } else {
                chevron.move(to: NSPoint(x: cx - 3.5, y: y + 1.5))
                chevron.line(to: NSPoint(x: cx, y: y - 1.5))
                chevron.line(to: NSPoint(x: cx + 3.5, y: y + 1.5))
            }
        }
        (hovered ? Luna.linkHover : Luna.linkBlue).setStroke()
        chevron.stroke()
    }

    static func topRounded(_ r: NSRect, radius: CGFloat) -> NSBezierPath {
        let p = NSBezierPath()
        p.move(to: NSPoint(x: r.minX, y: r.maxY))
        p.line(to: NSPoint(x: r.minX, y: r.minY + radius))
        p.appendArc(from: NSPoint(x: r.minX, y: r.minY), to: NSPoint(x: r.minX + radius, y: r.minY), radius: radius)
        p.line(to: NSPoint(x: r.maxX - radius, y: r.minY))
        p.appendArc(from: NSPoint(x: r.maxX, y: r.minY), to: NSPoint(x: r.maxX, y: r.minY + radius), radius: radius)
        p.line(to: NSPoint(x: r.maxX, y: r.maxY))
        p.close()
        return p
    }
}

final class TaskGroupBody: LunaView {
    override func draw(_ dirtyRect: NSRect) {
        Luna.groupBody.setFill()
        bounds.fill()
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 1, height: bounds.height).fill()
        NSRect(x: bounds.width - 1, y: 0, width: 1, height: bounds.height).fill()
        NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1).fill()
    }
}

/// Ссылка панели задач: значок + синий текст, подчёркивание при наведении.
final class LinkButton: LunaView {
    private let title: String
    private let action: () -> Void
    private let label = NSTextField(labelWithString: "")
    private var hovered = false { didSet { updateStyle() } }

    init(title: String, icon: NSImage?, action: @escaping () -> Void) {
        self.title = title
        self.action = action
        super.init(frame: .zero)
        toolTip = title

        let iconView = NSImageView()
        iconView.image = icon
        iconView.imageScaling = .scaleProportionallyUpOrDown
        label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        for v in [iconView, label] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
        }
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 18),
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),
            label.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 6),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        addTrackingArea(NSTrackingArea(
            rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
        updateStyle()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func updateStyle() {
        var attrs: [NSAttributedString.Key: Any] = [
            .font: Luna.font, .foregroundColor: hovered ? Luna.linkHover : Luna.linkBlue,
        ]
        if hovered { attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue }
        label.attributedStringValue = NSAttributedString(string: title, attributes: attrs)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(convert(point, from: superview)) ? self : nil
    }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
    override func mouseEntered(with event: NSEvent) { hovered = true }
    override func mouseExited(with event: NSEvent) { hovered = false }
    override func mouseDown(with event: NSEvent) {}

    override func mouseUp(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        // Действие может перестроить панель и удалить эту ссылку — выполняем после события.
        DispatchQueue.main.async(execute: action)
    }
}
