import AppKit

/// Строка меню внутри окна в стиле macOS: фон заголовка окна, шрифт строки меню,
/// скруглённая подсветка открытого пункта. Как в системной строке меню, пока одно меню
/// открыто, наведение на соседний заголовок переключает меню без щелчка.
final class MenuBarView: LunaView {
    var menuProvider: ((Int) -> NSMenu?)?

    private let font = NSFont.menuBarFont(ofSize: 0)
    private var itemRects: [NSRect] = []
    private var opened: Int? { didSet { needsDisplay = true } }
    private var switchTo: Int?

    override func layout() {
        super.layout()
        var x: CGFloat = 6
        itemRects = Menus.titles.map { title in
            let w = (title as NSString).size(withAttributes: [.font: font]).width + 18
            defer { x += w }
            return NSRect(x: x, y: 2, width: w, height: bounds.height - 4)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
        for (i, title) in Menus.titles.enumerated() where i < itemRects.count {
            let r = itemRects[i]
            if opened == i {
                NSColor.labelColor.withAlphaComponent(0.12).setFill()
                NSBezierPath(roundedRect: r, xRadius: 5, yRadius: 5).fill()
            }
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.labelColor]
            let size = (title as NSString).size(withAttributes: attrs)
            (title as NSString).draw(
                at: NSPoint(x: r.midX - size.width / 2, y: r.midY - size.height / 2),
                withAttributes: attrs)
        }
        NSColor.separatorColor.setFill()
        NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1).fill()
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        guard let index = itemRects.firstIndex(where: { $0.contains(p) }) else { return }
        open(index)
    }

    /// Открывает меню и, пока оно открыто, следит за мышью: если она ушла на другой заголовок,
    /// закрывает текущее меню и сразу открывает соседнее.
    private func open(_ first: Int) {
        var next: Int? = first
        while let index = next, let menu = menuProvider?(index) {
            next = nil
            switchTo = nil
            opened = index
            displayIfNeeded()

            let timer = Timer(timeInterval: 0.03, repeats: true) { [weak self, weak menu] _ in
                guard let self, let menu, let window = self.window else { return }
                let p = self.convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
                if let hovered = self.itemRects.firstIndex(where: { $0.contains(p) }), hovered != index {
                    self.switchTo = hovered
                    menu.cancelTrackingWithoutAnimation()
                }
            }
            RunLoop.current.add(timer, forMode: .eventTracking)
            menu.popUp(positioning: nil, at: NSPoint(x: itemRects[index].minX, y: bounds.maxY), in: self)
            timer.invalidate()
            next = switchTo
        }
        opened = nil
    }
}
