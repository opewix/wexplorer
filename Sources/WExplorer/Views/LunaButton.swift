import AppKit

/// Плоская кнопка в стиле XP: подсветка при наведении, «вдавленность» при нажатии,
/// серое состояние, когда недоступна.
final class LunaButton: LunaView {
    enum Style {
        case vertical    // значок сверху, подпись снизу
        case horizontal  // значок слева, подпись справа
        case iconOnly
    }

    var title: String { didSet { invalidateIntrinsicContentSize(); needsDisplay = true } }
    var image: NSImage? { didSet { needsDisplay = true } }
    var isEnabled = true {
        didSet {
            if !isEnabled { isHovered = false; isPressed = false }
            needsDisplay = true
        }
    }
    var isToggled = false { didSet { needsDisplay = true } }
    var showsMenuArrow = false { didSet { invalidateIntrinsicContentSize(); needsDisplay = true } }
    var onClick: ((LunaButton) -> Void)?

    private let style: Style
    private let imageSide: CGFloat
    private var isHovered = false { didSet { needsDisplay = true } }
    private var isPressed = false { didSet { needsDisplay = true } }

    init(title: String, symbol: String?, colors: [NSColor] = [], style: Style = .vertical, imageSide: CGFloat = 20) {
        self.title = title
        self.style = style
        self.imageSide = imageSide
        if let symbol, let base = NSImage(systemSymbolName: symbol, accessibilityDescription: title) {
            var config = NSImage.SymbolConfiguration(pointSize: imageSide * 0.8, weight: .regular)
            if !colors.isEmpty {
                config = config.applying(NSImage.SymbolConfiguration(paletteColors: colors))
            }
            self.image = base.withSymbolConfiguration(config)
        }
        super.init(frame: .zero)
        toolTip = title
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self))
    }

    required init?(coder: NSCoder) { fatalError() }

    private var arrowWidth: CGFloat { showsMenuArrow ? 10 : 0 }

    override var intrinsicContentSize: NSSize {
        let textW = (title as NSString).size(withAttributes: [.font: Theme.font]).width
        switch style {
        case .vertical:
            return NSSize(width: max(36, textW + 14) + arrowWidth, height: Luna.toolbarHeight - 8)
        case .horizontal:
            return NSSize(width: imageSide + textW + 18 + arrowWidth, height: imageSide + 6)
        case .iconOnly:
            return NSSize(width: imageSide + 10 + arrowWidth, height: imageSide + 8)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds.insetBy(dx: 0.5, dy: 0.5)
        if Theme.isWin10 {
            // Windows 10: плоская голубая подсветка без скруглений.
            if isEnabled && (isPressed || isToggled) {
                NSBezierPath.win10Box(bounds, fill: Win10.selection, border: Win10.selectionBorder)
            } else if isEnabled && isHovered {
                NSBezierPath.win10Box(bounds, fill: Win10.hover, border: Win10.hoverBorder)
            }
        } else if isEnabled && (isPressed || isToggled || isHovered) {
            let path = NSBezierPath(roundedRect: r, xRadius: 3, yRadius: 3)
            ((isPressed || isToggled) ? Luna.buttonPressed : Luna.buttonHover).setFill()
            path.fill()
            Luna.buttonHoverBorder.setStroke()
            path.stroke()
        }

        let offset: CGFloat = isPressed && !Theme.isWin10 ? 1 : 0
        let contentWidth = bounds.width - arrowWidth
        let textColor = isEnabled ? Luna.text : (Theme.isWin10 ? Win10.disabledText : Luna.secondaryText)
        let attrs: [NSAttributedString.Key: Any] = [.font: Theme.font, .foregroundColor: textColor]
        let textSize = (title as NSString).size(withAttributes: attrs)

        var imageBox: NSRect
        switch style {
        case .vertical:
            imageBox = NSRect(x: contentWidth / 2 - imageSide / 2, y: 3, width: imageSide, height: imageSide)
            (title as NSString).draw(
                at: NSPoint(x: contentWidth / 2 - textSize.width / 2 + offset,
                            y: bounds.height - textSize.height - 3 + offset),
                withAttributes: attrs)
        case .horizontal:
            imageBox = NSRect(x: 5, y: bounds.midY - imageSide / 2, width: imageSide, height: imageSide)
            (title as NSString).draw(
                at: NSPoint(x: imageBox.maxX + 4 + offset, y: bounds.midY - textSize.height / 2 + offset),
                withAttributes: attrs)
        case .iconOnly:
            imageBox = NSRect(x: contentWidth / 2 - imageSide / 2, y: bounds.midY - imageSide / 2,
                              width: imageSide, height: imageSide)
        }

        if let image {
            imageBox = imageBox.offsetBy(dx: offset, dy: offset)
            image.draw(in: Self.fit(image.size, in: imageBox), from: .zero, operation: .sourceOver,
                       fraction: isEnabled ? 1 : 0.35, respectFlipped: true, hints: nil)
        }

        if showsMenuArrow {
            let x = bounds.width - arrowWidth + 1, y = bounds.midY
            let arrow = NSBezierPath()
            arrow.move(to: NSPoint(x: x, y: y - 1.5))
            arrow.line(to: NSPoint(x: x + 5, y: y - 1.5))
            arrow.line(to: NSPoint(x: x + 2.5, y: y + 1.5))
            arrow.close()
            textColor.setFill()
            arrow.fill()
        }
    }

    static func fit(_ size: NSSize, in rect: NSRect) -> NSRect {
        guard size.width > 0, size.height > 0 else { return rect }
        let scale = min(rect.width / size.width, rect.height / size.height)
        let w = size.width * scale, h = size.height * scale
        return NSRect(x: rect.midX - w / 2, y: rect.midY - h / 2, width: w, height: h)
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
