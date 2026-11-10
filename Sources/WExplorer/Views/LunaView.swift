import AppKit

/// Базовое представление: начало координат сверху слева, как в Windows.
class LunaView: NSView {
    override var isFlipped: Bool { true }
}

/// Горизонтальный/вертикальный градиент как фон.
class GradientView: LunaView {
    var startColor: NSColor { didSet { needsDisplay = true } }
    var endColor: NSColor { didSet { needsDisplay = true } }
    var angle: CGFloat

    init(start: NSColor, end: NSColor, angle: CGFloat = 90) {
        self.startColor = start
        self.endColor = end
        self.angle = angle
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        NSGradient(starting: startColor, ending: endColor)?.draw(in: bounds, angle: angle)
    }
}

/// Тонкая линия-разделитель в стиле XP (тёмная + светлая).
final class SeparatorView: LunaView {
    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: 2) }

    override func draw(_ dirtyRect: NSRect) {
        Luna.separator.setFill()
        NSRect(x: 0, y: 0, width: bounds.width, height: 1).fill()
        Luna.separatorLight.setFill()
        NSRect(x: 0, y: 1, width: bounds.width, height: 1).fill()
    }
}
