import AppKit

/// Строка состояния XP: три «утопленные» секции — число объектов, размер, зона.
final class StatusBarView: LunaView {
    var leftText = "" { didSet { needsDisplay = true } }
    var middleText = "" { didSet { needsDisplay = true } }
    var rightText = "" { didSet { needsDisplay = true } }
    var rightIcon: NSImage? { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        Luna.face.setFill()
        bounds.fill()
        Luna.separator.setFill()
        NSRect(x: 0, y: 0, width: bounds.width, height: 1).fill()

        let height = bounds.height - 5
        let right = NSRect(x: bounds.width - 170 - 16, y: 3, width: 170, height: height)
        let middle = NSRect(x: right.minX - 112, y: 3, width: 110, height: height)
        let left = NSRect(x: 2, y: 3, width: max(0, middle.minX - 4), height: height)
        [left, middle, right].forEach(sunken)

        drawText(leftText, in: left.insetBy(dx: 5, dy: 0))
        drawText(middleText, in: middle.insetBy(dx: 5, dy: 0))
        var textRect = right.insetBy(dx: 5, dy: 0)
        if let rightIcon {
            rightIcon.draw(in: NSRect(x: right.minX + 4, y: right.midY - 8, width: 16, height: 16),
                           from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            textRect.origin.x += 20
            textRect.size.width -= 20
        }
        drawText(rightText, in: textRect)
    }

    private func sunken(_ r: NSRect) {
        Luna.separator.setFill()
        NSRect(x: r.minX, y: r.minY, width: r.width, height: 1).fill()
        NSRect(x: r.minX, y: r.minY, width: 1, height: r.height).fill()
        NSColor.white.setFill()
        NSRect(x: r.minX, y: r.maxY - 1, width: r.width, height: 1).fill()
        NSRect(x: r.maxX - 1, y: r.minY, width: 1, height: r.height).fill()
    }

    private func drawText(_ text: String, in rect: NSRect) {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        let attrs: [NSAttributedString.Key: Any] = [.font: Luna.font, .foregroundColor: Luna.text, .paragraphStyle: style]
        let h = (text as NSString).size(withAttributes: attrs).height
        (text as NSString).draw(in: NSRect(x: rect.minX, y: rect.midY - h / 2, width: rect.width, height: h),
                                withAttributes: attrs)
    }
}
