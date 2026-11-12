import AppKit

/// Рамка выделения («резинка»), одна для всех видов списка. NSTableView своей не рисует вовсе
/// (строки выделяет, но рамки не видно), а у NSCollectionView она системная, серая. Здесь —
/// полупрозрачная в цвет выделения темы, как в XP и Windows 10.
final class MarqueeView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.zPosition = 1000
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        let color = Theme.isWin10 ? Win10.accent : Luna.selection
        color.withAlphaComponent(Theme.isWin10 ? 0.2 : 0.3).setFill()
        bounds.fill()
        let border = NSBezierPath(rect: bounds.insetBy(dx: 0.5, dy: 0.5))
        border.lineWidth = 1
        color.setStroke()
        border.stroke()
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

enum Marquee {
    enum Result {
        /// Мышь не сдвинулась — это щелчок; отпускание кнопки отдаётся вызывающему.
        case click(NSEvent)
        case dragged
    }

    /// Порог, после которого нажатие становится рамкой, а не щелчком.
    private static let threshold: CGFloat = 3

    /// Ведёт рамку после нажатия в `view` до отпускания кнопки. `items` — какие элементы задевает
    /// прямоугольник, `apply` — выставить выделение. Cmd переключает задетые, Shift добавляет их.
    static func track(in view: NSView, from event: NSEvent, selected: IndexSet,
                      items: (NSRect) -> IndexSet, apply: (IndexSet) -> Void) -> Result {
        guard let window = view.window else { return .dragged }
        let start = view.convert(event.locationInWindow, from: nil)
        let toggle = event.modifierFlags.contains(.command)
        let extend = event.modifierFlags.contains(.shift)
        var marquee: MarqueeView?
        var lastDrag = event
        var current = selected
        NSEvent.startPeriodicEvents(afterDelay: 0.1, withPeriod: 0.05)
        defer {
            NSEvent.stopPeriodicEvents()
            marquee?.removeFromSuperview()
        }
        while let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp, .periodic],
                                          until: .distantFuture, inMode: .eventTracking, dequeue: true) {
            switch next.type {
            case .leftMouseUp:
                return marquee == nil ? .click(next) : .dragged
            case .leftMouseDragged:
                lastDrag = next
            default:
                // Мышь за краем списка — прокручиваем, пока кнопка зажата, даже если мышь стоит.
                guard marquee != nil else { continue }
                view.autoscroll(with: lastDrag)
            }
            let point = view.convert(window.mouseLocationOutsideOfEventStream, from: nil)
            if marquee == nil {
                guard hypot(point.x - start.x, point.y - start.y) >= threshold else { continue }
                let created = MarqueeView(frame: .zero)
                view.addSubview(created)
                marquee = created
            }
            let rect = NSRect(x: min(start.x, point.x), y: min(start.y, point.y),
                              width: abs(point.x - start.x), height: abs(point.y - start.y))
            marquee?.frame = rect.intersection(view.bounds)
            let hit = items(rect)
            let selection = toggle ? selected.symmetricDifference(hit) : extend ? selected.union(hit) : hit
            if selection != current {
                current = selection
                apply(selection)
            }
        }
        return .dragged
    }
}
